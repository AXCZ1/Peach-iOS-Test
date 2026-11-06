import Foundation

struct PeachAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

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
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
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

    func coverURL(code: String, thumb: Int = 2) -> URL? {
        guard !code.isEmpty else { return nil }
        var components = URLComponents(url: url(path: "/cover"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "thumb", value: String(thumb)),
            URLQueryItem(name: "v", value: UUID().uuidString.prefix(8).description)
        ]
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
        let (data, response) = try await session.data(for: request)
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
        let queryText = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !queryText.isEmpty { query.append(URLQueryItem(name: "q", value: queryText)) }
        let page: PeachPage = try await get("/api/items", query: query)
        return page
    }

    func facets(_ filter: LibraryFilter) async throws -> PeachFacets {
        var query: [URLQueryItem] = [URLQueryItem(name: "jav", value: "1")]
        if !filter.libraryID.isEmpty { query.append(URLQueryItem(name: "library", value: filter.libraryID)) }
        return try await get("/api/facets", query: query)
    }

    func index(_ kind: String, query: String = "", limit: Int = 60) async throws -> [PeachFacet] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { queryItems.append(URLQueryItem(name: "q", value: trimmed)) }
        let response: PeachIndexResponse = try await get("/api/index", query: queryItems)
        return response.items
    }

    func item(id: Int) async throws -> PeachItem {
        try await get("/api/item", query: [URLQueryItem(name: "id", value: String(id))])
    }

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
        session.dataTask(with: request).resume()
    }

    func streamURL(id: Int, sessionID: String) -> URL {
        url(path: "/stream", query: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "session", value: sessionID)
        ])
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
            if http.statusCode == 401 {
                throw PeachAPIError(message: "登录已过期，请重新登录")
            }
            let payload = try? decoder.decode(PeachErrorResponse.self, from: data)
            throw PeachAPIError(message: payload?.error ?? "请求失败（\(http.statusCode)）")
        }
        return try decoder.decode(T.self, from: data)
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
}
