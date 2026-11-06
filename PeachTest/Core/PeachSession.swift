import Foundation

@MainActor
final class PeachSession: ObservableObject {
    enum Phase: Equatable {
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var api: PeachAPI?
    @Published var address: String
    @Published var error: String?

    /// One deadline covers address validation, `POST /login` and the
    /// authenticated library read. Without it a pending local-network prompt
    /// could leave the login button spinning indefinitely.
    private let loginDeadline = LoginPolicy.deadline

    private let addressKey = "peach.test.address"
    private var activeAttempt: UUID?
    private var restoring: Task<Void, Never>?

    init() {
        address = UserDefaults.standard.string(forKey: addressKey) ?? PeachAPI.defaultAddress
    }

    func signIn(password: String) async {
        restoring?.cancel()
        restoring = nil
        error = nil
        phase = .signedOut
        let attempt = UUID()
        activeAttempt = attempt
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(for: loginDeadline)
                    throw PeachAPIError(message: "登录超时：25 秒内没有完成登录。请检查本地网络权限与服务地址后重试。")
                }
                group.addTask { [address] in
                    let base = try PeachAPI.normalizedBaseURL(address)
                    let client = PeachAPI(baseURL: base)
                    try await client.login(password: password)
                    let libraries = try await client.libraries()
                    guard !libraries.isEmpty else {
                        throw PeachAPIError(message: "Peach 没有返回可浏览的馆藏")
                    }
                    await self.finishSignIn(base: base, client: client, attempt: attempt)
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            // Keep the login form usable after a timeout or network failure.
            if activeAttempt == attempt {
                activeAttempt = nil
                phase = .signedOut
                self.error = error.localizedDescription
            }
        }
    }

    private func finishSignIn(base: URL, client: PeachAPI, attempt: UUID) {
        guard activeAttempt == attempt else { return }
        activeAttempt = nil
        UserDefaults.standard.set(base.absoluteString, forKey: addressKey)
        address = base.absoluteString
        api = client
        phase = .signedIn
    }

    private func finishRestoreSync(client: PeachAPI) {
        api = client
        phase = .signedIn
    }

    private func failRestoreSync() {
        phase = .signedOut
    }

    func restore() async {
        guard activeAttempt == nil else { return }
        guard restoring == nil else { return }
        let client: PeachAPI
        do {
            let base = try PeachAPI.normalizedBaseURL(address)
            client = PeachAPI(baseURL: base)
        } catch {
            return
        }
        guard client.hasSession() else { return }
        let deadline = loginDeadline
        let task = Task { @MainActor [weak self] in
            defer { self?.restoring = nil }
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await Task.sleep(for: deadline)
                        throw PeachAPIError(message: "恢复登录超时")
                    }
                    group.addTask {
                        _ = try await client.libraries()
                    }
                    try await group.next()
                    group.cancelAll()
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.finishRestoreSync(client: client)
            } catch {
                self?.failRestoreSync()
            }
        }
        restoring = task
        await task.value
    }

    func signOut() {
        restoring?.cancel()
        restoring = nil
        activeAttempt = nil
        api?.clearSession()
        api = nil
        phase = .signedOut
    }
}
