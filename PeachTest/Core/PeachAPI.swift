import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct PeachAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One client for the running Peach instance. Reads use the authenticated
/// session; writes mirror the web contract at 0.52.0 and always send
/// `Origin` so Peach's same-origin guard accepts them.
final class PeachAPI: @unchecked Sendable {
    nonisolated static let defaultAddress = "http://192.168.5.5:8900/"

    nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        // A pending local-network prompt used to leave `waitsForConnectivity`
        // waiting indefinitely. The login flow owns its overall deadline, so
        // every individual request must fail instead of hanging forever.
        configuration.timeoutIntervalForRequest = LoginPolicy.requestTimeout
        configuration.timeoutIntervalForResource = LoginPolicy.resourceTimeout
        #if !canImport(FoundationNetworking)
        configuration.waitsForConnectivity = LoginPolicy.waitsForConnectivity
        #endif
        session = URLSession(configuration: configuration)
    }

    nonisolated static func normalizedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw PeachAPIError(message: "请输入完整的服务地址，例如 http://192.168.5.5:8900/")
        }
        components.path = "/"
        guard let url = components.url else {
            throw PeachAPIError(message: "服务地址无效")
        }
        return url
    }

    func url(path: String, query: [URLQueryItem] = []) -> URL {
        Self.makeURL(baseURL: baseURL, path: path, query: query)
    }

    nonisolated static func makeURL(baseURL: URL, path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty {
            var encoded = URLComponents()
            encoded.queryItems = query
            components.percentEncodedQuery = encoded.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    func resolve(_ raw: String) -> URL {
        guard var components = URLComponents(string: raw) else { return baseURL }
        if components.scheme == nil {
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.port = baseURL.port
        }
        return components.url ?? baseURL
    }

    func mediaURL(_ raw: String) -> URL {
        guard let components = URLComponents(string: raw) else { return resolve(raw) }
        guard components.scheme != nil, components.host != nil else { return resolve(raw) }
        return components.url ?? resolve(raw)
    }

    /// `/cover?code=…` is the official full sleeve. `thumb=2` asks Peach for
    /// the grid-sized derivative; `version` busts only that code's cache.
    func coverURL(code: String, thumb: Int = 2) -> URL? {
        guard !code.isEmpty else { return nil }
        var components = URLComponents(url: url(path: "/cover"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "thumb", value: String(thumb))
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Nine-grid frame or thumbnail still used by the wall's "缩略图" mode.
    func thumbURL(id: Int) -> URL {
        url(path: "/thumb", query: [URLQueryItem(name: "id", value: String(id))])
    }

    func posterURL(id: Int) -> URL {
        url(path: "/poster", query: [URLQueryItem(name: "id", value: String(id))])
    }

    func entityImageURL(kind: String, id: Int, thumb: Int = 1) -> URL {
        url(path: "/entity-image", query: [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "thumb", value: String(thumb))
        ])
    }

    func logoURL(studio: String) -> URL? {
        guard !studio.isEmpty else { return nil }
        var components = URLComponents(url: url(path: "/logo"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "studio", value: studio)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    func login(password: String) async throws {
        var request = URLRequest(url: url(path: "/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncoded([
            ("token", password),
            ("next", "/"),
            ("days", "30")
        ])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw PeachAPIError(message: Self.loginNetworkMessage(error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw PeachAPIError(message: "Peach 返回了无效响应")
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 303 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("访问密码不正确") || http.statusCode == 401 {
                throw PeachAPIError(message: "访问密码不正确")
            }
            if http.statusCode == 429 {
                throw PeachAPIError(message: "尝试次数较多，请一分钟后重试")
            }
            throw PeachAPIError(message: "登录失败（\(http.statusCode)）")
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        guard cookies.contains(where: { $0.name == "peach_session" }) else {
            throw PeachAPIError(message: "登录未取得会话，请检查服务地址")
        }
    }

    func hasSession() -> Bool {
        (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).contains { $0.name == "peach_session" }
    }

    func clearSession() {
        for cookie in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    func libraries() async throws -> [PeachLibrary] {
        let response: LibraryResponse = try await get("/api/libraries")
        return response.libraries
    }

    func items(_ filter: LibraryFilter, offset: Int, limit: Int) async throws -> PeachPage {
        try await get("/api/items", query: itemQuery(filter, offset: offset, limit: limit))
    }

    func facets(_ filter: LibraryFilter) async throws -> PeachFacets {
        var query: [URLQueryItem] = [URLQueryItem(name: "jav", value: filter.javOnly ? "1" : "0")]
        if !filter.libraryID.isEmpty { query.append(URLQueryItem(name: "library", value: filter.libraryID)) }
        return try await get("/api/facets", query: query)
    }

    func index(kind: String, query: String = "", limit: Int = 180, offset: Int = 0) async throws -> [PeachFacet] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { queryItems.append(URLQueryItem(name: "q", value: trimmed)) }
        let response: PeachIndexResponse = try await get("/api/index", query: queryItems)
        return response.items
    }

    func item(id: Int) async throws -> PeachItem {
        try await get("/api/item", query: [URLQueryItem(name: "id", value: String(id))])
    }

    func entity(kind: String, name: String) async throws -> PeachEntity {
        try await get("/api/entity", query: [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "name", value: name)
        ])
    }

    func related(id: Int, limit: Int = 28) async throws -> [PeachItem] {
        let response: PeachRelatedResponse = try await get("/api/related", query: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        return response.items
    }

    func stats() async throws -> PeachStats {
        try await get("/api/stats")
    }

    func tasks() async throws -> PeachTasks {
        try await get("/api/tasks")
    }

    func configuration() async throws -> PeachConfiguration {
        try await get("/api/configuration")
    }

    func downloads() async throws -> PeachDownloads {
        try await get("/api/downloads")
    }

    func searchHistory(limit: Int = 10) async throws -> [String] {
        let response: PeachSearchHistoryResponse = try await get("/api/search-history", query: [
            URLQueryItem(name: "limit", value: String(limit))
        ])
        return response.items
    }

    func rememberSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let _: PeachPlayResponse = try await post("/api/search-history", body: [
                "operation": "remember", "query": trimmed
            ])
        } catch {
            // Search results remain usable when history storage is unavailable.
        }
    }

    func follow() async throws -> PeachFollow {
        try await get("/api/follow")
    }

    func libraryShortcuts() async throws -> PeachLibraryShortcuts {
        try await get("/api/library-shortcuts")
    }

    /// Entity favourites are keyed by Peach's canonical entity id. Tags and
    /// performers with the same spelling are separate identities in 0.52.0.
    @discardableResult
    func setFavorite(entityID: Int, on: Bool) async throws -> PeachLibraryShortcuts {
        try await post("/api/library-shortcuts", body: [
            "action": "favorite", "entity_id": entityID, "on": on
        ])
    }

    func libraryProcessing() async throws -> PeachLibraryProcessing {
        try await get("/api/library-processing")
    }

    func playlists() async throws -> [PeachPlaylist] {
        let response: PeachPlaylistsResponse = try await get("/api/playlists")
        return response.items
    }

    func playlist(id: Int) async throws -> PeachPlaylist {
        try await get("/api/playlist", query: [URLQueryItem(name: "id", value: String(id))])
    }

    // MARK: - Writes

    func streamPlan(id: Int, sessionID: String) async throws -> StreamPlan {
        try await get("/api/stream-plan", query: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "session", value: sessionID)
        ])
    }

    func cancelStream(sessionID: String) {
        guard !sessionID.isEmpty else { return }
        var request = URLRequest(url: url(path: "/api/stream-cancel", query: [
            URLQueryItem(name: "session", value: sessionID)
        ]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        session.dataTask(with: request).resume()
    }

    func streamURL(id: Int, sessionID: String) -> URL {
        url(path: "/stream", query: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "session", value: sessionID)
        ])
    }

    /// Mirrors the web client's first-play counter. The server only increments
    /// `play_count`; the caller records progress separately through `activity`.
    func markPlayed(id: Int) async throws {
        let _: PeachPlayResponse = try await post("/api/play", body: ["id": id])
    }

    /// Accumulates real watch seconds and leave position. The web client sends
    /// this every ten seconds and again on pause/end/pagehide.
    func activity(id: Int, position: Double, duration: Double, delta: Double, ended: Bool, seeks: Int) async throws {
        let _: PeachActivityResponse = try await post("/api/activity", body: [
            "id": id,
            "position": position,
            "duration": duration,
            "delta": max(0, delta),
            "ended": ended,
            "seeks": seeks
        ])
    }

    /// `kind` is `o`, `o-undo`, `dislike`, `seen`, `dispose` or `rate`.
    @discardableResult
    func feedback(id: Int, kind: String, value: Int? = nil) async throws -> PeachFeedbackResponse {
        var body: [String: Any] = ["id": id, "kind": kind]
        if let value { body["value"] = value }
        return try await post("/api/feedback", body: body)
    }

    @discardableResult
    func toggleWatchLater(id: Int) async throws -> Bool {
        let response: PeachWatchLaterResponse = try await post("/api/watch-later", body: ["id": id])
        return response.watchLater
    }

    @discardableResult
    func setLiked(id: Int, liked: Bool, reason: String = "") async throws -> PeachFeedbackResponse {
        try await post("/api/preference", body: ["id": id, "liked": liked, "reason": reason])
    }

    @discardableResult
    func addPlaylist(name: String, ids: [Int]) async throws -> PeachPlaylist? {
        let response: PeachPlaylistResponse = try await post("/api/playlist", body: [
            "action": "create", "name": name, "asset_ids": ids
        ])
        return response.playlist
    }

    private func itemQuery(_ filter: LibraryFilter, offset: Int, limit: Int) -> [URLQueryItem] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "count", value: offset == 0 ? "1" : "0")
        ]
        if filter.javOnly { query.append(URLQueryItem(name: "jav", value: "1")) }
        if !filter.libraryID.isEmpty { query.append(URLQueryItem(name: "library", value: filter.libraryID)) }
        if let performer = filter.performer { query.append(URLQueryItem(name: "performer", value: performer)) }
        if let studio = filter.studio { query.append(URLQueryItem(name: "studio", value: studio)) }
        if let tag = filter.tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if let series = filter.series { query.append(URLQueryItem(name: "series", value: series)) }
        if let creator = filter.creator { query.append(URLQueryItem(name: "creator", value: creator)) }
        if !filter.state.rawValue.isEmpty { query.append(URLQueryItem(name: "state", value: filter.state.rawValue)) }
        if !filter.sort.rawValue.isEmpty {
            query.append(URLQueryItem(name: "sort", value: filter.sort.rawValue))
            if filter.sort.supportsDirection {
                query.append(URLQueryItem(name: "dir", value: filter.ascending ? "asc" : "desc"))
            }
        }
        if filter.sort == .seed { query.append(URLQueryItem(name: "seed", value: String(filter.seed))) }
        let queryText = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !queryText.isEmpty { query.append(URLQueryItem(name: "q", value: queryText)) }
        return query
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: url(path: path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PeachAPIError(message: "Peach 返回了无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(for: http.statusCode, data: data, decoder: decoder)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PeachAPIError(message: "Peach 返回了无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(for: http.statusCode, data: data, decoder: decoder)
        }
        return try decoder.decode(T.self, from: data)
    }

    private static func error(for status: Int, data: Data, decoder: JSONDecoder) -> PeachAPIError {
        if status == 401 { return PeachAPIError(message: "登录已过期，请重新登录") }
        let payload = try? decoder.decode(PeachErrorResponse.self, from: data)
        return PeachAPIError(message: payload?.error ?? "请求失败（\(status)）")
    }

    private func formEncoded(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func loginNetworkMessage(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost:
            return "无法连接 Peach。请确认手机与 Peach 在同一 Wi-Fi；如果刚才弹出了“本地网络”权限，请允许后重试。"
        case .timedOut:
            return "登录超时：没有收到 Peach 的响应。请检查服务地址与本地网络权限后重试。"
        case .cannotFindHost, .dnsLookupFailed:
            return "找不到 Peach 服务地址，请检查地址。"
        default:
            return "登录失败：\(error.localizedDescription)"
        }
    }
}
