import Foundation

@MainActor
final class PeachSession: ObservableObject {
    enum Phase: Equatable {
        case signedOut
        case signedIn
        case failed(String)
    }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var api: PeachAPI?
    @Published var address: String
    @Published var error: String?

    private let addressKey = "peach.test.address"

    init() {
        address = UserDefaults.standard.string(forKey: addressKey) ?? PeachAPI.defaultAddress
    }

    func signIn(password: String) async {
        error = nil
        do {
            let base = try PeachAPI.normalizedBaseURL(address)
            let client = PeachAPI(baseURL: base)
            try await client.login(password: password)
            let libraries = try await client.libraries()
            guard !libraries.isEmpty else {
                throw PeachAPIError(message: "Peach 没有返回可浏览的馆藏")
            }
            UserDefaults.standard.set(base.absoluteString, forKey: addressKey)
            address = base.absoluteString
            api = client
            phase = .signedIn
        } catch {
            phase = .failed(error.localizedDescription)
            error = error.localizedDescription
        }
    }

    func restore() async {
        do {
            let base = try PeachAPI.normalizedBaseURL(address)
            let client = PeachAPI(baseURL: base)
            guard client.hasSession() else { return }
            _ = try await client.libraries()
            api = client
            phase = .signedIn
        } catch {
            phase = .signedOut
        }
    }

    func signOut() {
        api?.clearSession()
        api = nil
        phase = .signedOut
    }
}
