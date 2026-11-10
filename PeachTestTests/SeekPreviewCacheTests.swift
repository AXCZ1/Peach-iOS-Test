import Foundation
import XCTest
@testable import PeachTestCore

@MainActor
final class SeekPreviewCacheTests: XCTestCase {
    func testDownloadQueueOverlapsSlowFramesAndReportsOnlySavedFrames() async throws {
        let transfers = SeekTransferProbe()
        let complete = try await SeekFrameDownloads.run(Array(0..<12)) { second in
            await transfers.start(second)
            try await Task.sleep(for: second == 0 ? .milliseconds(350) : .milliseconds(65))
            await transfers.finish(second)
            return second != 2
        } progress: { saved in
            await transfers.progress(saved)
        }
        let result = await transfers.result()
        XCTAssertFalse(complete)
        XCTAssertEqual(Set(result.started), Set(0..<12))
        XCTAssertLessThanOrEqual(result.peak, 4)
        XCTAssertGreaterThan(result.peak, 2)
        XCTAssertTrue(result.replenishedBeforeSlowFrame)
        XCTAssertEqual(result.saved, [11])
    }

    func testOnlyMatchingVideoAndExactSourceVersionProduceManifestPath() async throws {
        let json = """
        {"root":"NAS","path":"/hdd2/videos/2/sub/Film.mp4","name":"Film.mp4","type":"video","sizeBytes":12345,
         "modifiedAt":"2026-03-01T15:33:20.123457+00:00",
         "thumbnailUrl":"/api/thumb?id=23880644a2454fca5b7c391f2676b6da6ebe0834cb4ac61283b90815fd105727"}
        """
        let entry = try JSONDecoder().decode(SeekSourceEntry.self, from: Data(json.utf8))
        XCTAssertNotNil(SeekSourceEntry.match([entry], name: "film.MP4", size: 12345))
        XCTAssertNil(SeekSourceEntry.match([entry], name: "Film.mp4", size: 54321))
        XCTAssertNil(SeekSourceEntry.match([entry, entry], name: "Film.mp4", size: 12345))
        let mtime = try XCTUnwrap(entry.modifiedTimeNs { key in
            key == "natural-aspect-v1|/mnt/hdd2/videos/2/sub/Film.mp4|12345|1772379200123456671"
                ? "23880644a2454fca5b7c391f2676b6da6ebe0834cb4ac61283b90815fd105727" : ""
        })
        XCTAssertEqual(mtime, 1_772_379_200_123_456_671)
        let directory = entry.previewDirectory(mtime: mtime, interval: 5) { key in
            XCTAssertEqual(key, "relative_v1|videos/2/sub/Film.mp4|12345|1772379200123456671|5|240")
            return "688c2e86beeaa7e5145d31b74461c19c14d74d842d37fe6fa1e0425349307adb"
        }
        XCTAssertEqual(directory, "/hdd2/.media-thumbs/video-preview/688c2e86beeaa7e5145d31b74461c19c14d74d842d37fe6fa1e0425349307adb")
        let manifest = SeekSourceManifest(keyMode: "relative_v1", complete: true, relativePath: "videos/2/sub/Film.mp4",
            sizeBytes: 12345, modifiedTimeNs: mtime, durationSeconds: 1210, interval: 5, width: 240, frames: [0, 5, 10])
        XCTAssertTrue(manifest.matches(entry, mtime: mtime, interval: 5))
        XCTAssertFalse(manifest.matches(entry, mtime: mtime - 1, interval: 5))
    }

    func testCachedFramesResumeAndOldOrUnrelatedFramesNeverResolve() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SeekPreviewCache(root: root)
        let origin = URL(string: "https://peach.example/")!
        let source = SeekPreviewSource(origin: URL(string: "https://media.example/")!)
        let other = SeekPreviewSource(origin: URL(string: "https://another.example/")!)
        let item = try JSONDecoder().decode(PeachItem.self, from: Data(#"{"id":9,"name":"Film.mp4","medium":"video","size":12345}"#.utf8))
        let index = SeekPreviewCache.Index(identity: item.mediaCacheIdentity, fingerprint: "first",
            remoteDirectory: "/source", interval: 5, times: [5, 10, 15, 20, 25])
        let work = try await cache.prepare(index, origin: origin, source: source, item: item)
        try await cache.save(Data("first".utf8), second: 5, work: work)
        try await cache.save(Data("second".utf8), second: 10, work: work)
        let restarted = SeekPreviewCache(root: root)
        let partial = try await restarted.existing(origin: origin, source: source, item: item, fingerprint: "first")
        XCTAssertEqual(partial?.missing, [15, 20, 25])
        let available = await restarted.frames(origin: origin, source: source, item: item)
        let nearest = try XCTUnwrap(available?.nearest(to: 8))
        XCTAssertEqual(nearest.lastPathComponent, "000010.webp")
        XCTAssertEqual(try Data(contentsOf: nearest), Data("second".utf8))
        XCTAssertNil(available?.nearest(to: 20))
        let otherFrames = await restarted.frames(origin: origin, source: other, item: item)
        XCTAssertNil(otherFrames)
        let newVersion = try await restarted.existing(origin: origin, source: source, item: item, fingerprint: "replacement")
        XCTAssertNil(newVersion)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nearest.path))
    }
}

private actor SeekTransferProbe {
    private var active = Set<Int>()
    private var started: [Int] = []
    private var saved: [Int] = []
    private var peak = 0
    private var replenishedBeforeSlowFrame = false

    func start(_ second: Int) {
        if second >= 4 && active.contains(0) { replenishedBeforeSlowFrame = true }
        started.append(second)
        active.insert(second)
        peak = max(peak, active.count)
    }

    func finish(_ second: Int) { active.remove(second) }
    func progress(_ count: Int) { saved.append(count) }

    func result() -> (started: [Int], peak: Int, replenishedBeforeSlowFrame: Bool, saved: [Int]) {
        (started, peak, replenishedBeforeSlowFrame, saved)
    }
}
