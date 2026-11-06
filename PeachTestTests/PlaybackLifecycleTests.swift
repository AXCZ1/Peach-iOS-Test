#if canImport(AVFoundation)
import Foundation
import XCTest
@testable import PeachTestCore

private final class DelayedPlanProtocol: URLProtocol, @unchecked Sendable {
    final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [DelayedPlanProtocol] = []
        func append(_ request: DelayedPlanProtocol) { lock.lock(); requests.append(request); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
        func finish() {
            lock.lock(); let ready = requests; requests = []; lock.unlock()
            for request in ready { request.reply("{\"protocol\":\"range\",\"src\":\"http://example.invalid/test.mp4\"}") }
        }
    }
    static let pending = Pending()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/api/stream-plan" { Self.pending.append(self) }
        else { reply("{}") }
    }
    override func stopLoading() {}
    private func reply(_ json: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class PlaybackLifecycleTests: XCTestCase {
    private func controller() throws -> PlaybackController {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedPlanProtocol.self]
        let api = PeachAPI(baseURL: URL(string: "http://example.invalid")!, session: URLSession(configuration: configuration))
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("{\"id\":42,\"duration\":120}".utf8))
        return PlaybackController(api: api, item: item)
    }

    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<400 {
            if DelayedPlanProtocol.pending.count == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The playback plan request did not start")
    }

    func testLatePlanAfterOpeningDetailsDoesNotCreatePlayer() async throws {
        let controller = try controller()
        let request = Task { await controller.activate() }
        try await waitForRequests(1)
        let session = controller.sessionID
        controller.setActive(false)
        XCTAssertNotEqual(controller.sessionID, session)
        DelayedPlanProtocol.pending.finish()
        await request.value
        XCTAssertNil(controller.player)
        XCTAssertFalse(controller.isPlaying)
        controller.stop()
    }

    func testOldAndNewPlansCannotReviveAnExitedPage() async throws {
        let controller = try controller()
        let first = Task { await controller.activate() }
        try await waitForRequests(1)
        controller.setActive(false)
        let second = Task { await controller.activate() }
        try await waitForRequests(2)
        controller.stop()
        DelayedPlanProtocol.pending.finish()
        await first.value
        await second.value
        XCTAssertNil(controller.player)
        XCTAssertFalse(controller.isPlaying)
    }
}
#endif
