import Foundation
import XCTest
@testable import PeachTestCore

@MainActor
final class OfflinePreviewTests: XCTestCase {
    func testSamplesCoverTheEntireTimelineAndFallbackAvoidsEndOfFile() throws {
        let metadata = try JSONDecoder().decode(TimelineMetadata.self, from: Data(#"{"frames":100,"interval":10}"#.utf8))
        let times = PreviewSamplePlan.times(metadata, duration: 1000)
        XCTAssertEqual(times.count, 30)
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last, 990)
        let fallback = PreviewSamplePlan.times(nil, duration: 60)
        XCTAssertEqual(fallback, (0..<30).map { Double($0 * 2 + 1) })
        XCTAssertTrue(PreviewSamplePlan.times(nil, duration: 0).isEmpty)
    }

    func testValidatedPaginationAndOrphanCleanup() async throws {
        let items = try (1...63).map { try item($0) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflinePreviewStore(root: root)
        let origin = URL(string: "https://peach.example")!
        let other = URL(string: "http://peach.local")!
        let retained = items[62]
        let orphan = try item(99)

        for (server, item) in [(origin, retained), (origin, orphan), (other, orphan)] {
            try await store.prepare(origin: server, item: item, times: [1])
            try await store.save(Data([9]), origin: server, item: item, time: 1)
        }

        do {
            let snapshot = try await OfflineCatalog.snapshot { offset, limit in
                if offset == 0 { return PeachPage(total: 63, items: Array(items.prefix(limit)), hasMore: nil) }
                return PeachPage(total: nil, items: [items[59], items[61], items[62]], hasMore: false)
            }
            try await store.prune(origin: origin, retaining: Set(snapshot.map(\.id)))
            XCTFail("Overlapping pages must not produce a catalog snapshot")
        } catch is PeachAPIError { }
        let stillPresent = await store.entries(origin: origin, item: orphan)
        XCTAssertEqual(stillPresent.count, 1)

        let snapshot = try await OfflineCatalog.snapshot { offset, limit in
            PeachPage(total: offset == 0 ? items.count : nil,
                      items: Array(items.dropFirst(offset).prefix(limit)),
                      hasMore: offset == 0 ? nil : false)
        }
        XCTAssertEqual(snapshot.map(\.id), items.map(\.id))
        try await store.prune(origin: origin, retaining: Set(snapshot.map(\.id)))
        let remaining = await store.entries(origin: origin, item: retained)
        let removed = await store.entries(origin: origin, item: orphan)
        let untouched = await store.entries(origin: other, item: orphan)
        XCTAssertEqual(remaining.map(\.time), [1])
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(untouched.count, 1)
    }

    func testPartialFramesResumeAndFileReplacementInvalidatesOldFrames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = URL(string: "https://peach.example")!
        let movie = try item(1)
        let updated = try item(1, size: 88)
        let store = OfflinePreviewStore(root: root)
        try await store.prepare(origin: origin, item: movie, times: [1, 2])
        try await store.save(Data([1]), origin: origin, item: movie, time: 1)

        let reopened = OfflinePreviewStore(root: root)
        let plan = await reopened.index(origin: origin, item: movie)
        let available = await reopened.entries(origin: origin, item: movie)
        let stale = await reopened.index(origin: origin, item: updated)
        XCTAssertEqual(plan?.times, [1, 2])
        XCTAssertEqual(available.map(\.time), [1])
        XCTAssertNil(stale)

        try await reopened.prepare(origin: origin, item: movie, times: [1, 2])
        try await reopened.save(Data([2]), origin: origin, item: movie, time: 2)
        let complete = await reopened.entries(origin: origin, item: movie)
        XCTAssertEqual(complete.map(\.time), [1, 2])
        try await reopened.prepare(origin: origin, item: updated, times: [1, 2])
        let oldFrame = await reopened.frame(origin: origin, item: movie, time: 1)
        XCTAssertNil(oldFrame)
    }

    private func item(_ id: Int, size: Int = 1) throws -> PeachItem {
        try JSONDecoder().decode(PeachItem.self,
            from: Data(#"{"id":\#(id),"name":"fixture.mp4","size":\#(size)}"#.utf8))
    }
}
