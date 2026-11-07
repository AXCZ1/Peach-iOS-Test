#if os(macOS)
import AVFoundation
import XCTest
@testable import PeachTestCore

@MainActor
final class OriginalPlaybackTests: XCTestCase {
    func testH264OriginalPlaysAndSeeksThroughReverseProxy() async throws {
        let fixture = try OriginalPlaybackFixture(upstreamOrigin: "http://peach-upstream.invalid:8900")
        defer { fixture.stop() }
        let controller = try makeController(fixture, id: 42001)
        defer { controller.stop(); PlayerMemory.shared.clear(42001) }
        await controller.activate()
        let player = try XCTUnwrap(controller.player, "\(controller.phase)")
        let asset = try XCTUnwrap(player.currentItem?.asset as? AVURLAsset)
        try await waitFor("original H.264 playback") { controller.isPlaying && player.currentTime().seconds > 0.2 }
        XCTAssertEqual(controller.formatNote, "原文件直放")
        XCTAssertEqual(player.currentItem?.presentationSize, CGSize(width: 1920, height: 1080))
        controller.seek(to: 8)
        try await waitFor("playback after seeking") { player.currentTime().seconds > 8.1 && controller.isPlaying }
        controller.pause()
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertGreaterThan(counts["original_ranges", default: 0], 0)
        XCTAssertNil(counts["plans"])

        let (download, response) = try await URLSession.shared.download(from: asset.url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: download, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let frame = try await OriginalVideoFrame.capture(asset: AVURLAsset(url: local), seconds: 8, hls: false)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
    }

    func testHEVCOriginalTicketServesNativeTrackOverHTTPRange() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let api = PeachAPI(baseURL: fixture.baseURL)
        let url = try await api.originalPlaybackURL(id: 42005)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        // AVFoundation may normalize the ISO `hev1` sample entry to `hvc1`.
        let hevcTypes: Set<UInt32> = [0x68657631, 0x68766331]
        XCTAssertTrue(formats.contains { hevcTypes.contains(CMFormatDescriptionGetMediaSubType($0)) })
        let decodable = try await track.load(.isDecodable)
        print("Cloud HEVC track reports decodable: \(decodable)")
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertGreaterThan(counts["original_ranges", default: 0], 0)
        XCTAssertNil(counts["plans"])
    }

    func testFormatFailureSwitchesOnceAndPreservesPausedPosition() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try makeController(fixture, id: 42002)
        defer { controller.stop(); PlayerMemory.shared.clear(42002) }
        await controller.activate()
        let original = try XCTUnwrap(controller.player, "\(controller.phase)")
        let item = try XCTUnwrap(original.currentItem)
        try await waitFor("initial playback") { controller.isPlaying && controller.currentTime > 0.2 }
        controller.seek(to: 8)
        try await waitFor("seek to the resume position") { original.currentTime().seconds > 8.1 }
        controller.pause()
        let resume = controller.currentTime
        for _ in 0..<2 {
            NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item,
                                            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey:
                                                NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue)])
        }
        try await waitFor("replacement stream at the same position") {
            controller.player !== original && controller.phase == .ready &&
                abs((controller.player?.currentTime().seconds ?? 0) - resume) < 0.4
        }
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.formatNote, "原始 MP4 流")
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertEqual(counts["plans"], 1)
        XCTAssertEqual(counts["play_marks"], 1)
    }

    func testUnavailableTicketUsesExistingPlanButForeignTicketIsRejected() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let missing = try makeController(fixture, id: 42004)
        defer { missing.stop(); PlayerMemory.shared.clear(42004) }
        await missing.activate()
        XCTAssertEqual(missing.formatNote, "原始 MP4 流")

        let foreign = try makeController(fixture, id: 42003)
        defer { foreign.stop() }
        await foreign.activate()
        XCTAssertNil(foreign.player)
        guard case .failed = foreign.phase else { return XCTFail("Foreign playback ticket was accepted") }
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 2)
        XCTAssertEqual(counts["plans"], 1)
    }

    func testAudioOnlyOriginalUsesCompatibilityVideoInstead() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try makeController(fixture, id: 42006)
        defer { controller.stop(); PlayerMemory.shared.clear(42006) }
        await controller.activate()
        XCTAssertEqual(controller.formatNote, "原始 MP4 流")
        try await waitFor("video from the compatibility stream") {
            controller.isPlaying && controller.player?.currentItem?.presentationSize.width == 1920
        }
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertEqual(counts["plans"], 1)
    }

    private func makeController(_ fixture: OriginalPlaybackFixture, id: Int) throws -> PlaybackController {
        PlayerMemory.shared.clear(id)
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("{\"id\":\(id),\"name\":\"fixture.mp4\",\"duration\":24}".utf8))
        let controller = PlaybackController(api: PeachAPI(baseURL: fixture.baseURL), item: item, preferOriginal: true)
        controller.setMuted(true)
        return controller
    }

    private func waitFor(_ reason: String, _ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw PeachAPIError(message: "Timed out waiting for \(reason)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct OriginalPlaybackFixture {
    let process: Process
    let baseURL: URL

    init(upstreamOrigin: String? = nil) throws {
        let script = try XCTUnwrap(Bundle.module.url(forResource: "original-playback-http", withExtension: "py", subdirectory: "Fixtures"))
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", script.path] + (upstreamOrigin.map { [$0] } ?? [])
        process.standardOutput = stdout
        try process.run()
        // Read exactly the five-digit port and newline; a larger read can wait for EOF.
        guard let data = try stdout.fileHandleForReading.read(upToCount: 6),
              let port = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            if process.isRunning { process.terminate() }
            throw PeachAPIError(message: "Original playback HTTP fixture did not start")
        }
        self.process = process
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/")!
    }

    func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("counts"))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}
#endif
