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
        PeachRuntimeLogger.shared.log("开始登录 Peach", level: .info, category: "auth", source: "PeachSession", fields: ["address": address])
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
            PeachRuntimeLogger.shared.log("登录失败: \(error.localizedDescription)", level: .error, category: "auth", source: "PeachSession", fields: ["address": address])
        }
    }

    func restore() async {
        guard !working, phase == .restoring else { return }
        working = true
        defer { working = false }
        error = nil
        retryOrigin = nil
        guard let base = try? PeachAPI.normalizedBaseURL(address) else {
            PeachRuntimeLogger.shared.log("恢复会话中止：服务地址无效", level: .warning, category: "auth", source: "PeachSession", fields: ["address": address])
            phase = .signedOut
            return
        }
        PeachRuntimeLogger.shared.log("尝试恢复登录会话", level: .info, category: "auth", source: "PeachSession", fields: ["origin": PeachAPI.originKey(for: base)])
        let client = PeachAPI(baseURL: base)
        let password: String?
        do { password = try SavedPeachPassword.read(for: base) }
        catch {
            password = nil
            credentialNotice = "无法读取保存的密码：\(error.localizedDescription)"
            PeachRuntimeLogger.shared.log("读取已保存密码失败: \(error.localizedDescription)", level: .warning, category: "auth", source: "PeachSession")
        }
        let hasCookie = client.hasSession()
        guard hasCookie || password != nil else {
            PeachRuntimeLogger.shared.log("无有效会话 Cookie 且无已保存凭据，需登录", level: .info, category: "auth", source: "PeachSession")
            error = credentialNotice
            phase = .signedOut
            return
        }
        do {
            try await Self.withDeadline {
                if hasCookie {
                    do { try await Self.verify(client); return }
                    catch let error as PeachAPIError where error.status == 401 && password != nil {
                        PeachRuntimeLogger.shared.log("旧会话 Cookie 返回 401，使用已保存凭据重新登录", level: .warning, category: "auth", source: "PeachSession")
                    }
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
            PeachRuntimeLogger.shared.log("恢复会话失败: \(error.localizedDescription)", level: .error, category: "auth", source: "PeachSession", fields: ["origin": PeachAPI.originKey(for: base)])
        }
    }

    func retryRestore() async {
        guard canRetryRestore, !working else { return }
        PeachRuntimeLogger.shared.log("用户触发重试恢复会话", level: .info, category: "auth", source: "PeachSession")
        phase = .restoring
        await restore()
    }

    func signOut() {
        guard let api else { return }
        PeachRuntimeLogger.shared.log("用户退出登录", level: .info, category: "auth", source: "PeachSession", fields: ["origin": PeachAPI.originKey(for: api.baseURL)])
        do { try SavedPeachPassword.remove(for: api.baseURL) }
        catch {
            credentialNotice = "无法清除保存的密码：\(error.localizedDescription)"
            PeachRuntimeLogger.shared.log("清除已保存密码失败: \(error.localizedDescription)", level: .error, category: "auth", source: "PeachSession")
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
        PeachRuntimeLogger.shared.log("会话已就绪", level: .info, category: "auth", source: "PeachSession", fields: ["origin": PeachAPI.originKey(for: base), "password_saved": saved ? "true" : "false"])
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
