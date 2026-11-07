import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import PeachTestCore

final class LoginRecoveryTests: XCTestCase {
    func testCookieExpiryRenewsConcurrentRequestsOnlyOnce() async throws {
        let counter = LoginCounter()
        let renewal = PeachLoginRenewal()
        let generation = await renewal.generation
        async let first: Void = renewal.recover(since: generation) { try await counter.login() }
        async let second: Void = renewal.recover(since: generation) { try await counter.login() }
        _ = try await (first, second)
        try await renewal.recover(since: generation) { try await counter.login() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    func testHTTPLoginAndRecoveryWithRealCookieStorage() async throws {
        guard let address = ProcessInfo.processInfo.environment["PEACH_TEST_AUTH_URL"],
              let password = ProcessInfo.processInfo.environment["PEACH_TEST_AUTH_PASSWORD"] else {
            throw XCTSkip("A local HTTP cookie fixture is required")
        }
        let base = try PeachAPI.normalizedBaseURL(address)
        guard base.host == "127.0.0.1" else { throw PeachAPIError(message: "Test fixture must use loopback") }
        let client = PeachAPI(baseURL: base, savedPassword: { password })
        defer { client.clearSession() }
        try await client.login(password: password)
        XCTAssertTrue(client.hasSession())
        for cookie in HTTPCookieStorage.shared.cookies(for: base) ?? [] where cookie.name == "peach_session" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        XCTAssertFalse(client.hasSession())
        async let first = client.libraries()
        async let second = client.libraries()
        let libraries = try await (first, second)
        XCTAssertFalse(libraries.0.isEmpty)
        XCTAssertEqual(libraries.0, libraries.1)
        XCTAssertTrue(client.hasSession())
    }
}

private actor LoginCounter {
    private(set) var calls = 0
    func login() async throws {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
    }
}
