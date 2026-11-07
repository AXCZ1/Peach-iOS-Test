#if os(macOS)
import Foundation
import XCTest
@testable import PeachTestCore

private final class DelayedTicketProtocol: URLProtocol, @unchecked Sendable {
    final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [DelayedTicketProtocol] = []
        func append(_ request: DelayedTicketProtocol) { lock.lock(); requests.append(request); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
        func finish() {
            lock.lock(); let ready = requests; requests = []; lock.unlock()
            for request in ready { request.reply("{\"url\":\"/external-stream/42?ticket=fixture\"}") }
        }
    }
    static let pending = Pending()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/api/external-playback" { Self.pending.append(self) }
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
    private func delayedController() throws -> PlaybackController {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedTicketProtocol.self]
        let api = PeachAPI(baseURL: URL(string: "http://example.invalid")!, session: URLSession(configuration: configuration))
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("{\"id\":42,\"duration\":120}".utf8))
        return PlaybackController(api: api, item: item, makeLocalPlayer: { _ in
            XCTFail("An inactive page installed a decoder")
            return nil
        })
    }

    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<400 {
            if DelayedTicketProtocol.pending.count == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The original file ticket request did not start")
    }

    func testLateTicketAfterOpeningDetailsDoesNotCreatePlayer() async throws {
        let controller = try delayedController()
        let request = Task { await controller.activate() }
        try await waitForRequests(1)
        let session = controller.sessionID
        controller.setActive(false)
        XCTAssertNotEqual(controller.sessionID, session)
        DelayedTicketProtocol.pending.finish()
        await request.value
        XCTAssertFalse(controller.hasVideoSurface)
        XCTAssertFalse(controller.isPlaying)
        controller.stop()
    }

    func testOldAndNewTicketsCannotReviveAnExitedPage() async throws {
        let controller = try delayedController()
        let first = Task { await controller.activate() }
        try await waitForRequests(1)
        controller.setActive(false)
        let second = Task { await controller.activate() }
        try await waitForRequests(2)
        controller.stop()
        DelayedTicketProtocol.pending.finish()
        await first.value
        await second.value
        XCTAssertFalse(controller.hasVideoSurface)
        XCTAssertFalse(controller.isPlaying)
    }
    func testBoostReturnsToNormalOnReleaseAndLeavingPage() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try fixture.controller()
        await controller.activate()
        let player = try XCTUnwrap(controller.player, "\(controller.phase)")
        controller.beginBoost()
        XCTAssertTrue(controller.isBoosting)
        XCTAssertEqual(player.defaultRate, 2)
        controller.endBoost()
        XCTAssertFalse(controller.isBoosting)
        XCTAssertEqual(player.defaultRate, 1)
        controller.beginBoost(); controller.setActive(false)
        XCTAssertFalse(controller.isBoosting)
        XCTAssertEqual(player.defaultRate, 1)
        controller.stop()
    }

    func testPiPKeepsSessionAliveWhileAppIsInactive() async throws {
        let fixture = try OriginalPlaybackFixture()
        defer { fixture.stop() }
        let controller = try fixture.controller()
        await controller.activate()
        let player = try XCTUnwrap(controller.player, "\(controller.phase)")
        let session = controller.sessionID
        controller.setPictureInPicture(true)
        controller.setActive(false)
        XCTAssertTrue(controller.isPiPActive)
        XCTAssertEqual(controller.sessionID, session)
        XCTAssertTrue(controller.player === player)
        controller.setPictureInPicture(false)
        XCTAssertFalse(controller.isPiPActive)
        controller.stop()
    }

}
#endif
