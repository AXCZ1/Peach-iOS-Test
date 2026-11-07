import Foundation
import XCTest
@testable import PeachTestCore

final class MediaCacheTests: XCTestCase {
    func testDiskEntriesSurviveReopenAndClearingDoesNotTouchAnotherServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = URL(string: "https://peach.example.com/")!
        let other = URL(string: "http://192.168.5.5:8900/")!
        let a = MediaCacheKey(url: primary, kind: .originalFrame, resource: "frame-1")
        let b = MediaCacheKey(url: other, kind: .originalFrame, resource: "frame-1")
        let cache = MediaDiskCache(root: root)
        await cache.store(Data([1, 2, 3]), for: a)
        await cache.store(Data([4]), for: b)

        let reopened = MediaDiskCache(root: root)
        let prior = await reopened.read(a)
        XCTAssertEqual(prior, Data([1, 2, 3]))
        try await reopened.clear(origin: primary)
        let cleared = await reopened.read(a)
        let untouched = await reopened.read(b)
        XCTAssertNil(cleared)
        XCTAssertEqual(untouched, Data([4]))
    }

    func testVideoQuotaKeepsNewestEntryAndRejectsOversizedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://peach.example.com/")!
        let cache = MediaDiskCache(root: root, capacityOverride: 10)
        let old = MediaCacheKey(url: url, kind: .previewVideo, resource: "first")
        let new = MediaCacheKey(url: url, kind: .previewVideo, resource: "second")
        let huge = MediaCacheKey(url: url, kind: .previewVideo, resource: "oversized")
        let sixBytes = Data(repeating: 7, count: 6)
        await cache.store(sixBytes, for: old)
        await cache.store(sixBytes, for: new)
        await cache.store(Data(repeating: 0, count: 11), for: huge)
        let prior = await cache.read(old)
        let latest = await cache.read(new)
        let oversized = await cache.read(huge)
        XCTAssertNil(prior)
        XCTAssertEqual(latest, sixBytes)
        XCTAssertNil(oversized)
    }

    func testRejectsInvalidOrUnknownContentRanges() {
        let valid = HTTPByteRange("bytes 512-1023/2048")
        XCTAssertEqual(valid?.bounds, 512...1023)
        XCTAssertEqual(valid?.length, 2048)
        XCTAssertNil(HTTPByteRange("bytes -1-511/2048"))
        XCTAssertNil(HTTPByteRange("bytes 0-2048/2048"))
        XCTAssertNil(HTTPByteRange("bytes 0-1023/*"))
    }
}
