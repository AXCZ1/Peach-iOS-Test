import Foundation

@MainActor
final class PeachSession: ObservableObject {
    enum Phase: Equatable { case restoring, signedOut, signedIn }

    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var api: PeachAPI?
    @Published private(set) var passwordSaved = false
    @Published private(set) var credentialNotice: String?
    @Published var address: String
    @Published var error: String?

    private let addressKey = "peach.test.address"
    private var working = false
    private var retryOrigin: URL?

    var canRetryRestore: Bool {
        retryOrigin != nil && (try? PeachAPI.normalizedBaseURL(address)) == retryOrigin
    }

    init() {
        address = UserDefaults.standard.string(forKey: addressKey) ?? PeachAPI.defaultAddress
    }

    func signIn(password: String) async {
        guard !working, phase == .signedOut else { return }
        working = true
        defer { working = false }
        error = nil
        do {
            let base = try PeachAPI.normalizedBaseURL(address)
            let client = PeachAPI(baseURL: base)
            try await Self.withDeadline {
                try await client.login(password: password)
                try await Self.verify(client)
            }
            var saved = false
            do {
                try SavedPeachPassword.save(password, for: base)
                saved = true
                credentialNotice = nil
            } catch {
                credentialNotice = "密码未保存：\(error.localizedDescription)"
            }
            finish(base: base, saved: saved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func restore() async {
        guard !working, phase == .restoring else { return }
        working = true
        defer { working = false }
        error = nil
        retryOrigin = nil
        guard let base = try? PeachAPI.normalizedBaseURL(address) else { phase = .signedOut; return }
        let client = PeachAPI(baseURL: base)
        let password: String?
        do { password = try SavedPeachPassword.read(for: base) }
        catch {
            password = nil
            credentialNotice = "无法读取保存的密码：\(error.localizedDescription)"
        }
        let hasCookie = client.hasSession()
        guard hasCookie || password != nil else {
            error = credentialNotice
            phase = .signedOut
            return
        }
        do {
            try await Self.withDeadline {
                if hasCookie {
                    do { try await Self.verify(client); return }
                    catch let error as PeachAPIError where error.status == 401 && password != nil { }
                }
                if let password { try await client.login(password: password) }
                try await Self.verify(client)
            }
            finish(base: base, saved: password != nil)
        } catch {
            if (error as? PeachAPIError)?.status == 401 {
                client.clearSession()
                try? SavedPeachPassword.remove(for: base)
            } else if password != nil { retryOrigin = base }
            phase = .signedOut
            self.error = error.localizedDescription
        }
    }

    func retryRestore() async {
        guard canRetryRestore, !working else { return }
        phase = .restoring
        await restore()
    }

    func signOut() {
        guard let api else { return }
        do { try SavedPeachPassword.remove(for: api.baseURL) }
        catch {
            credentialNotice = "无法清除保存的密码：\(error.localizedDescription)"
            return
        }
        api.clearSession()
        self.api = nil
        passwordSaved = false
        credentialNotice = nil
        retryOrigin = nil
        phase = .signedOut
    }

    private func finish(base: URL, saved: Bool) {
        UserDefaults.standard.set(base.absoluteString, forKey: addressKey)
        address = base.absoluteString
        passwordSaved = saved
        retryOrigin = nil
        api = PeachAPI(baseURL: base, savedPassword: { try SavedPeachPassword.read(for: base) })
        phase = .signedIn
    }

    private nonisolated static func verify(_ client: PeachAPI) async throws {
        let libraries = try await client.libraries()
        guard !libraries.isEmpty else {
            throw PeachAPIError(message: "Peach 没有返回可浏览的馆藏")
        }
    }

    private nonisolated static func withDeadline(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: LoginPolicy.deadline)
                throw PeachAPIError(message: "登录超时，请检查网络与服务地址后重试")
            }
            group.addTask(operation: operation)
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
