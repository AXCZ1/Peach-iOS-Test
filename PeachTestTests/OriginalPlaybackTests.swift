#if os(macOS)
import AVFoundation
import XCTest
@testable import PeachTestCore

@MainActor
final class OriginalPlaybackTests: XCTestCase {
    func testH264OriginalPlaysAndSeeksThroughReverseProxy() async throws {
        let fixture = try OriginalPlaybackFixture(upstreamOrigin: "http://peach-upstream.invalid:8900")
        defer { fixture.stop() }
        let controller = try fixture.controller()
        defer { controller.stop(); PlayerMemory.shared.clear(42001) }
        await controller.activate()
        let player = try XCTUnwrap(controller.player, "\(controller.phase)")
        let asset = try XCTUnwrap(player.currentItem?.asset as? AVURLAsset)
        try await waitFor("original H.264 playback") { controller.isPlaying && player.currentTime().seconds > 0.2 }
        XCTAssertEqual(controller.formatNote, "原文件直放")
        XCTAssertNil(controller.localPlayer)
        XCTAssertEqual(player.currentItem?.presentationSize, CGSize(width: 1920, height: 1080))
        controller.beginScrubbing()
        let beforeScrubbing = player.currentTime().seconds
        controller.previewSeek(8)
        XCTAssertEqual(controller.seekPreview, 8)
        XCTAssertEqual(player.currentTime().seconds, beforeScrubbing, accuracy: 0.2)
        controller.endScrubbing(at: 8)
        try await waitFor("playback after seeking") { player.currentTime().seconds > 8.1 && controller.isPlaying }

        controller.beginScrubbing(pausesPlayback: false)
        let beforeLiveScrub = player.currentTime().seconds
        controller.previewSeek(16)
        try await waitFor("original playback advances while dragging") {
            player.currentTime().seconds > beforeLiveScrub + 0.25
        }
        XCTAssertLessThan(player.currentTime().seconds, 16)
        XCTAssertEqual(controller.seekPreview, 16)
        controller.endScrubbing(at: 16)
        try await waitFor("original jumps only after releasing") { player.currentTime().seconds > 16.1 && controller.isPlaying }
        controller.pause()
        controller.beginScrubbing(pausesPlayback: false)
        controller.previewSeek(8)
        XCTAssertEqual(player.rate, 0)
        controller.endScrubbing(at: 8)
        try await waitFor("seek while manually paused") { abs(player.currentTime().seconds - 8) < 0.2 }
        XCTAssertEqual(player.rate, 0)
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertGreaterThan(counts["original_ranges", default: 0], 0)
        XCTAssertNil(counts["plans"])

        let (download, response) = try await URLSession.shared.download(from: asset.url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: download, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let frame = try await OriginalVideoFrame.capture(asset: AVURLAsset(url: local), seconds: 8)
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

    func testFormatFailureUsesSameOriginalAndPreservesPausedPosition() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        var openedURLs: [URL] = []
        let controller = try fixture.controller(id: 42002, makeLocalPlayer: { url, _ in
            openedURLs.append(url)
            return local
        })
        defer { controller.stop(); PlayerMemory.shared.clear(42002) }
        await controller.activate()
        let original = try XCTUnwrap(controller.player, "\(controller.phase)")
        let item = try XCTUnwrap(original.currentItem)
        let originalURL = try XCTUnwrap((item.asset as? AVURLAsset)?.url)
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
        try await waitFor("replacement decoder") { controller.localPlayer === local }
        XCTAssertNil(controller.player)
        XCTAssertEqual(openedURLs, [originalURL])
        XCTAssertEqual(local.seekTarget ?? 0, resume, accuracy: 0.4)
        XCTAssertFalse(local.playing)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.formatNote, "原文件直放 · VLC")
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["plans"])
        XCTAssertEqual(counts["play_marks"], 1)
    }

    func testUnavailableOrForeignTicketFailsWithoutAPlanRequest() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let missing = try fixture.controller(id: 42004)
        defer { missing.stop(); PlayerMemory.shared.clear(42004) }
        await missing.activate()
        XCTAssertFalse(missing.hasVideoSurface)
        guard case .failed = missing.phase else { return XCTFail("A missing original ticket should fail") }

        let foreign = try fixture.controller(id: 42003)
        defer { foreign.stop() }
        await foreign.activate()
        XCTAssertFalse(foreign.hasVideoSurface)
        guard case .failed = foreign.phase else { return XCTFail("Foreign playback ticket was accepted") }
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 2)
        XCTAssertNil(counts["plans"])
    }

    func testNoAVVideoTrackUsesLocalDecoderAndPreservesPlaybackControls() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        var source: URL?
        let controller = try fixture.controller(id: 42006, makeLocalPlayer: { url, _ in source = url; return local })
        defer { controller.stop(); PlayerMemory.shared.clear(42006) }
        await controller.activate()
        XCTAssertEqual(source?.path, "/external-stream/42006")
        XCTAssertNil(controller.player)
        XCTAssertTrue(controller.localPlayer === local)
        XCTAssertTrue(local.muted)
        XCTAssertTrue(local.playing)
        local.showFrame(at: 2)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isPlaying)
        controller.beginBoost()
        XCTAssertEqual(local.rate, 2)
        controller.endBoost()
        XCTAssertEqual(local.rate, 1)
        controller.beginScrubbing()
        XCTAssertFalse(local.playing)
        controller.endScrubbing(at: 12)
        XCTAssertTrue(local.playing)
        XCTAssertEqual(local.seekTarget, 12)
        local.completeSeek(at: 12.25)
        XCTAssertEqual(controller.currentTime, 12.25)
        controller.beginScrubbing(pausesPlayback: false)
        controller.previewSeek(18)
        local.showFrame(at: 13)
        XCTAssertTrue(local.playing)
        XCTAssertEqual(local.seekTarget, 12)
        XCTAssertEqual(controller.currentTime, 13)
        XCTAssertEqual(controller.seekPreview, 18)
        controller.endScrubbing(at: 18)
        XCTAssertTrue(local.playing)
        XCTAssertEqual(local.seekTarget, 18)
        local.completeSeek(at: 18)
        controller.setMuted(false)
        XCTAssertFalse(local.muted)
        controller.setActive(false)
        XCTAssertFalse(local.playing)
        controller.stop()
        XCTAssertTrue(local.stopped)
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["plans"])
    }

    func testOrdinaryPlaybackBoostChangesRateWithoutTransportOrSeek() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        let controller = try fixture.controller(id: 42006, usesDirectRateControl: true, makeLocalPlayer: { _, _ in local })
        defer { controller.stop(); PlayerMemory.shared.clear(42006) }
        await controller.activate()
        local.showFrame(at: 2)
        let transportCalls = local.transportCalls

        controller.beginBoost()
        XCTAssertEqual(local.rate, 2)
        controller.endBoost()
        XCTAssertEqual(local.rate, 1)
        XCTAssertEqual(local.transportCalls, transportCalls)
        XCTAssertTrue(local.playing)
        XCTAssertNil(local.seekTarget)
        XCTAssertTrue(controller.localPlayer === local)

        controller.beginBoost()
        controller.pause()
        XCTAssertEqual(local.rate, 1)
        XCTAssertFalse(local.playing)
        controller.beginBoost()
        XCTAssertFalse(controller.isBoosting)
        controller.resume()
        XCTAssertEqual(local.rate, 1)
        XCTAssertTrue(local.playing)
    }

    func testMKVUsesSignedOriginalWithoutAVProbeOrStreamPlan() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        var source: URL?
        let controller = try fixture.controller(name: "fixture.mkv", makeLocalPlayer: { url, _ in source = url; return local })
        defer { controller.stop() }
        await controller.activate()
        XCTAssertEqual(source?.path, "/external-stream/42001")
        XCTAssertTrue(controller.localPlayer === local)
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["original_ranges"])
        XCTAssertNil(counts["plans"])
        local.onEvent?(.failed("原文件不可达"))
        XCTAssertEqual(controller.phase, .failed("原文件不可达"))
        XCTAssertNil(controller.localPlayer)
    }

    func testMissingFirstFrameRetriesSameOriginalOnceWithoutRecordingAPlay() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let automatic = RecordingLocalPlayer()
        let software = RecordingLocalPlayer()
        var sources: [URL] = []
        var decoders: [LocalOriginalDecoder] = []
        let controller = try fixture.controller(id: 42007, name: "fixture.mkv", makeLocalPlayer: { url, decoder in
            sources.append(url)
            decoders.append(decoder)
            return decoder == .automatic ? automatic : software
        })
        defer { controller.stop(); PlayerMemory.shared.clear(42007) }
        PlayerMemory.shared.save(7, for: 42007)
        await controller.activate()
        let session = controller.sessionID
        XCTAssertTrue(automatic.playing)
        XCTAssertEqual(automatic.seekTarget, 7)

        automatic.onEvent?(.failed("没有首帧", canRetryInSoftware: true))
        XCTAssertTrue(automatic.stopped)
        XCTAssertTrue(controller.localPlayer === software)
        XCTAssertEqual(decoders, [.automatic, .software])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first, sources.last)
        XCTAssertEqual(sources.first?.path, "/external-stream/42007")
        XCTAssertEqual(controller.sessionID, session)
        XCTAssertEqual(controller.phase, .preparing)
        XCTAssertEqual(software.seekTarget, 7)
        XCTAssertTrue(software.playing)
        XCTAssertTrue(software.muted)

        software.onEvent?(.failed("软件解码也没有首帧", canRetryInSoftware: true))
        XCTAssertEqual(controller.phase, .failed("软件解码也没有首帧"))
        XCTAssertNil(controller.localPlayer)
        XCTAssertTrue(software.stopped)
        XCTAssertEqual(sources.count, 2)
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["plans"])
        XCTAssertNil(counts["play_marks"])
        XCTAssertNil(counts["activities"])
    }

    func testLocalPictureInPictureKeepsTheOriginalSessionAndCompletesItsSeek() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        let controller = try fixture.controller(id: 42006, name: "fixture.mkv", makeLocalPlayer: { _, _ in local })
        defer { controller.stop(); PlayerMemory.shared.clear(42006) }
        await controller.activate()
        local.showFrame(at: 2)
        let session = controller.sessionID

        controller.setPictureInPicture(true)
        controller.setActive(false)
        XCTAssertTrue(local.playing)
        controller.pause()
        XCTAssertFalse(local.playing)
        var seekCompletions = 0
        controller.seek(to: 12) { seekCompletions += 1 }
        XCTAssertEqual(seekCompletions, 0)
        local.completeSeek(at: 12.25)
        XCTAssertEqual(seekCompletions, 1)
        XCTAssertEqual(controller.currentTime, 12.25)
        controller.resume()
        XCTAssertTrue(local.playing)

        controller.setActive(true)
        controller.setPictureInPicture(false)
        XCTAssertTrue(local.playing)
        XCTAssertTrue(controller.localPlayer === local)
        XCTAssertEqual(controller.sessionID, session)
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["plans"])
    }

    func testCardPreviewPlaysOriginalSamplesWithoutMarkingPlayed() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try fixture.controller(previewOnly: true)
        defer { controller.stop() }
        await controller.activate()
        let player = try XCTUnwrap(controller.player)
        try await waitFor("original card preview") {
            controller.isPlaying && player.currentTime().seconds >= controller.duration * 0.08
        }
        XCTAssertNil(controller.localPlayer)
        XCTAssertTrue(player.isMuted)
        controller.stop()
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertGreaterThan(counts["original_ranges", default: 0], 0)
        XCTAssertNil(counts["plans"])
        XCTAssertNil(counts["play_marks"])
        XCTAssertNil(counts["activities"])
        XCTAssertNil(PlayerMemory.shared.position(for: controller.item.id))
    }

    func testMKVCardPreviewSeeksThroughLocalDecoderWithoutWatchRecords() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let local = RecordingLocalPlayer()
        var url: URL?
        let controller = try fixture.controller(name: "fixture.mkv", previewOnly: true, makeLocalPlayer: { source, _ in
            url = source
            return local
        })
        defer { controller.stop() }
        await controller.activate()
        try await waitFor("first local preview seek") { local.seekTarget != nil }
        XCTAssertEqual(url?.path, "/external-stream/42001")
        let first = try XCTUnwrap(local.seekTarget)
        XCTAssertEqual(first, 24 * 0.08, accuracy: 0.01)
        XCTAssertTrue(local.muted)
        XCTAssertTrue(local.playing)
        local.completeSeek(at: first)
        local.showFrame(at: first + 1.5)
        try await waitFor("second local preview seek") { local.seekTarget != first }
        XCTAssertEqual(local.seekTarget ?? 0, 24 * 0.22, accuracy: 0.01)
        controller.stop()
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertNil(counts["plans"])
        XCTAssertNil(counts["play_marks"])
        XCTAssertNil(counts["activities"])
        XCTAssertNil(PlayerMemory.shared.position(for: controller.item.id))
    }

    func testDetailFramesShareSignedOriginalAndRetainSourceResolution() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let api = PeachAPI(baseURL: fixture.baseURL)
        let item = try JSONDecoder().decode(PeachItem.self, from: Data(#"{"id":42001,"name":"fixture.mp4"}"#.utf8))
        let reader = try await OriginalFrameReader(api: api, item: item)
        for seconds in [2.0, 8.0] {
            let frame = try await reader.capture(at: seconds)
            XCTAssertEqual(frame.width, 1920)
            XCTAssertEqual(frame.height, 1080)
        }
        let counts = try await fixture.counts()
        XCTAssertEqual(counts["tickets"], 1)
        XCTAssertGreaterThan(counts["original_ranges", default: 0], 0)
        XCTAssertNil(counts["plans"])
        XCTAssertNil(counts["play_marks"])
    }

    private func waitFor(_ reason: String, _ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw PeachAPIError(message: "Timed out waiting for \(reason)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

struct OriginalPlaybackFixture {
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

    @MainActor
    func controller(id: Int = 42001, name: String = "fixture.mp4", previewOnly: Bool = false,
                    usesDirectRateControl: Bool = false,
                    makeLocalPlayer: (@MainActor (URL, LocalOriginalDecoder) -> (any LocalOriginalPlayer)?)? = nil) throws -> PlaybackController {
        PlayerMemory.shared.clear(id)
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("{\"id\":\(id),\"name\":\"\(name)\",\"duration\":24}".utf8))
        let controller = PlaybackController(api: PeachAPI(baseURL: baseURL), item: item, previewOnly: previewOnly,
                                            usesDirectRateControl: usesDirectRateControl,
                                            makeLocalPlayer: makeLocalPlayer)
        controller.setMuted(true)
        return controller
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}

@MainActor
private final class RecordingLocalPlayer: LocalOriginalPlayer {
    var onEvent: ((LocalPlaybackEvent) -> Void)?
    var reportingPosition: Double?
    var playing = false
    private(set) var transportCalls = 0
    var rate: Float = 1
    var muted = false
    var stopped = false
    var seekTarget: Double?
    var seekCompletion: ((Double?) -> Void)?

    func setPlayback(_ shouldPlay: Bool, rate: Float) {
        transportCalls += 1
        playing = shouldPlay
        self.rate = rate
    }
    func setRate(_ rate: Float) { self.rate = rate }
    func setMuted(_ muted: Bool) { self.muted = muted }
    func seek(to time: Double, completion: @escaping (Double?) -> Void) {
        seekTarget = time
        seekCompletion = completion
    }
    func stop() { stopped = true; playing = false }
    func showFrame(at time: Double) {
        reportingPosition = time
        onEvent?(.sample(position: time, duration: 24, playing: playing, hasFrame: true))
    }
    func completeSeek(at time: Double) {
        reportingPosition = time
        seekCompletion?(time)
        seekCompletion = nil
    }
}
#endif
