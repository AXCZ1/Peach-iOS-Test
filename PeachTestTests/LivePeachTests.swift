import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import PeachTestCore

final class LivePeachTests: XCTestCase {
    private func sandbox() throws -> (PeachAPI, URLSession) {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["PEACH_TEST_URL"], let token = environment["PEACH_TEST_TOKEN"] else {
            throw XCTSkip("An explicitly configured isolated Peach instance is required")
        }
        let base = try PeachAPI.normalizedBaseURL(address)
        guard base.host == "192.168.5.5", base.port == 18900 else {
            throw PeachAPIError(message: "Live tests are restricted to the isolated port 18900")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Token": token]
        let session = URLSession(configuration: configuration)
        return (PeachAPI(baseURL: base, session: session), session)
    }

    func testIsolatedIndexAndExistingArtwork() async throws {
        let (api, session) = try sandbox()
        for kind in EntityKind.allCases {
            let index = try await api.index(kind: kind.apiKind)
            guard let first = index.first else { continue }
            let entity = try await api.entity(kind: kind.rawValue, name: first.key)
            XCTAssertGreaterThan(entity.assetCount, 0)
            if first.hasImage == true, let id = first.entityID {
                let (_, response) = try await session.data(from: api.entityImageURL(kind: kind.rawValue, id: id))
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            }
        }
        var filter = LibraryFilter()
        filter.query = "MIKR-051"
        let page = try await api.items(filter, offset: 0, limit: 5)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.durationText, "2:29:08")
        XCTAssertNotNil(item.posterBox?.normalized)
        XCTAssertFalse(item.performerRefs.isEmpty)
        XCTAssertTrue(item.hasThumb)
        let (data, response) = try await session.data(from: api.thumbURL(id: item.id))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
        _ = try await api.timeline(id: item.id)
    }

    @MainActor
    func testIsolatedSingleUndoPreservesHistoricCount() async throws {
        let (api, _) = try sandbox()
        var filter = LibraryFilter()
        filter.query = "JUQ-575"
        let page = try await api.items(filter, offset: 0, limit: 5)
        let item = try XCTUnwrap(page.items.first)
        let originalCount = item.oCount
        let baseline = max(5, originalCount)
        do {
            for _ in originalCount..<baseline { _ = try await api.feedback(id: item.id, kind: "o") }
            let increment = try await api.feedback(id: item.id, kind: "o")
            XCTAssertEqual(increment.oCount, baseline + 1)
            var pending: Task<Void, Error>?
            let undo = SingleUseAction {
                pending = Task { _ = try await api.feedback(id: item.id, kind: "o-undo") }
            }
            undo.take()?()
            undo.take()?()
            try await pending?.value
            let after = try await api.item(id: item.id)
            XCTAssertEqual(after.oCount, baseline)
            try await restore(api: api, id: item.id, count: originalCount)
        } catch {
            try await restore(api: api, id: item.id, count: originalCount)
            throw error
        }
    }

    @MainActor
    func testNativeClimaxMarksThroughIsolatedProxy() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["PEACH_TEST_ORIGIN_PROXY_URL"],
              let token = environment["PEACH_TEST_TOKEN"] else {
            throw XCTSkip("An explicit loopback proxy to the isolated instance is required")
        }
        let base = try PeachAPI.normalizedBaseURL(address)
        guard base.host == "127.0.0.1", base.port != nil else {
            throw PeachAPIError(message: "The isolated proxy must use a loopback port")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Token": token]
        let session = URLSession(configuration: configuration)
        let api = PeachAPI(baseURL: base, session: session)
        var filter = LibraryFilter()
        filter.query = "JUQ-575"
        let page = try await api.items(filter, offset: 0, limit: 5)
        let item = try XCTUnwrap(page.items.first)
        let suite = "PeachMarksTest-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let marks = ClimaxMarks(defaults: defaults)

        var browser = URLRequest(url: base.appendingPathComponent("api/feedback"))
        browser.httpMethod = "POST"
        browser.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        browser.setValue("application/json", forHTTPHeaderField: "Content-Type")
        browser.httpBody = Data(#"{"id":\#(item.id),"kind":"o"}"#.utf8)
        let (_, rejection) = try await session.data(for: browser)
        guard (rejection as? HTTPURLResponse)?.statusCode == 403 else {
            try await restore(api: api, id: item.id, count: item.oCount)
            return XCTFail("The proxy did not exercise Peach's Origin rejection")
        }

        let anonymous = PeachAPI(baseURL: base, session: URLSession(configuration: .ephemeral))
        do {
            _ = try await marks.record(api: anonymous, item: item, at: 17)
            try await restore(api: api, id: item.id, count: item.oCount)
            return XCTFail("Anonymous writes must be rejected")
        } catch let error as PeachAPIError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertTrue(marks.list(origin: base, item: item).isEmpty)
        do {
            let (count, mark) = try await marks.record(api: api, item: item, at: 42.25)
            XCTAssertEqual(count, item.oCount + 1)
            XCTAssertEqual(ClimaxMarks(defaults: defaults).list(origin: base, item: item).map(\.seconds), [42.25])
            let undone = try await marks.undo(api: api, item: item, mark: mark)
            XCTAssertEqual(undone, item.oCount)
            XCTAssertTrue(marks.list(origin: base, item: item).isEmpty)
            let fresh = try await api.item(id: item.id)
            XCTAssertEqual(fresh.oCount, item.oCount)
        } catch {
            try await restore(api: api, id: item.id, count: item.oCount)
            throw error
        }
    }

    @MainActor
    private func restore(api: PeachAPI, id: Int, count: Int) async throws {
        let current = try await api.item(id: id).oCount
        if current > count {
            for _ in count..<current { _ = try await api.feedback(id: id, kind: "o-undo") }
        }
        let restored = try await api.item(id: id)
        XCTAssertEqual(restored.oCount, count)
    }
}
