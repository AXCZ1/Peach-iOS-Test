#if os(macOS)
import AVFoundation
import XCTest
@testable import PeachTestCore

@MainActor
final class OriginalPlaybackTests: XCTestCase {
    func testHEVCOriginalPlaysAndSeeksOverHTTPRange() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try makeController(fixture, id: 42001)
        defer { controller.stop(); PlayerMemory.shared.clear(42001) }
        await controller.activate()
        let player = try XCTUnwrap(controller.player, "\(controller.phase)")
        let item = try XCTUnwrap(player.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(output)
        var frame: CVPixelBuffer?
        try await waitFor("1080p HEVC frame from the original HTTP URL") {
            guard controller.isPlaying else { return false }
            frame = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil)
            return frame != nil
        }
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(frame)), 1920)
        XCTAssertEqual(controller.formatNote, "原文件直放")
        controller.seek(to: 8)
        try await waitFor("playback after seeking") { player.currentTime().seconds > 8.1 && controller.isPlaying }
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

    init() throws {
        let script = try XCTUnwrap(Bundle.module.url(forResource: "original-playback-http", withExtension: "py", subdirectory: "Fixtures"))
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", script.path]
        process.standardOutput = stdout
        try process.run()
        guard let data = try stdout.fileHandleForReading.read(upToCount: 32),
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
