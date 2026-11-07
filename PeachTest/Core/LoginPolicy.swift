import Foundation

enum LoginPolicy {
    static let deadline: Duration = .seconds(25)
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 30
    static let waitsForConnectivity = false

    static func allowsPlainHTTP(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        if host.contains(":") { return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        let octets = components.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 169 && octets[1] == 254)
    }
}

actor PeachLoginRenewal {
    private(set) var generation = 0
    private var pending: Task<Void, Error>?

    func recover(since observed: Int, _ login: @escaping @Sendable () async throws -> Void) async throws {
        guard observed == generation else { return }
        if let pending { return try await pending.value }
        let task = Task { try await login() }
        pending = task
        defer { pending = nil }
        try await task.value
        generation += 1
    }
}
