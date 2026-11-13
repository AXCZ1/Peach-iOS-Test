import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MediaBrowserSeekClient: Sendable {
    private struct Search: Decodable { let entries: [SeekSourceEntry] }
    let source: SeekPreviewSource
    let session: URLSession
    let hash: @Sendable (String) -> String

    init(source: SeekPreviewSource, hash: @escaping @Sendable (String) -> String) {
        self.source = source
        self.hash = hash
        let config = URLSessionConfiguration.ephemeral
        #if os(iOS)
        config.allowsCellularAccess = false
        config.networkServiceType = .background
        #endif
        config.httpMaximumConnectionsPerHost = SeekFrameDownloads.parallelism
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: PeachOriginRedirects(source.origin), delegateQueue: nil)
    }

    func login(_ password: String) async throws {
        var request = URLRequest(url: url("/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(source.origin.absoluteString.dropLast()), forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(["password": password])
        _ = try await read(request)
    }

    func find(_ item: PeachItem) async throws -> SeekSourceEntry? {
        guard let size = item.size, size > 0, !item.name.isEmpty else { return nil }
        let query = [
            URLQueryItem(name: "root", value: SeekPreviewSource.root),
            URLQueryItem(name: "path", value: SeekPreviewSource.folder),
            URLQueryItem(name: "q", value: String(item.name.prefix(120))),
            URLQueryItem(name: "limit", value: "20")
        ]
        let data = try await read(URLRequest(url: url("/api/search", query: query)))
        let entries = try JSONDecoder().decode(Search.self, from: data).entries
        return SeekSourceEntry.match(entries, name: item.name, size: size)
    }

    func index(for item: PeachItem, entry: SeekSourceEntry, fingerprint: String) async throws -> SeekPreviewCache.Index? {
        guard let mtime = entry.modifiedTimeNs(hash: hash) else { return nil }
        let longFirst = (item.duration ?? 0).rounded(.up) > 1200
        for interval in longFirst ? [5, 2] : [2, 5] {
            let directory = entry.previewDirectory(mtime: mtime, interval: interval, hash: hash)
            do {
                let data = try await file(directory + "/manifest.json")
                let manifest = try JSONDecoder().decode(SeekSourceManifest.self, from: data)
                guard manifest.matches(entry, mtime: mtime, interval: interval) else { continue }
                return SeekPreviewCache.Index(identity: item.mediaCacheIdentity, fingerprint: fingerprint,
                    remoteDirectory: directory, interval: interval, times: manifest.frames)
            } catch let error as PeachAPIError where error.status == 404 { continue }
        }
        return nil
    }

    func frame(_ second: Int, index: SeekPreviewCache.Index) async throws -> Data {
        let data = try await file(index.remoteDirectory + "/" + SeekPreviewCache.frameName(second))
        guard data.count >= 12, data.count <= 256 * 1024,
              data.prefix(4).elementsEqual("RIFF".utf8), data.dropFirst(8).prefix(4).elementsEqual("WEBP".utf8)
        else { throw PeachAPIError(message: "Media Browser 返回的文件不是有效的缩略图") }
        return data
    }

    private func file(_ path: String) async throws -> Data {
        try await read(URLRequest(url: url("/api/file", query: [
            URLQueryItem(name: "root", value: SeekPreviewSource.root),
            URLQueryItem(name: "path", value: path)
        ])))
    }

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        PeachAPI.makeURL(baseURL: source.origin, path: path, query: query)
    }

    private func read(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = status == 401 || status == 403
                ? "Media Browser 登录被拒绝，请检查地址和密码"
                : "Media Browser 请求失败（\(status)）"
            PeachRuntimeLogger.shared.log(
                "MediaBrowser HTTP \(status) url=\(request.url?.absoluteString ?? "")",
                level: status >= 500 || status == 0 ? .error : .warning,
                category: "seek-sync",
                source: "MediaBrowserSeekClient"
            )
            throw PeachAPIError(message: message, status: status)
        }
        return data
    }
}

enum SeekFrameDownloads {
    static let parallelism = 4
    private static let startSpacing: Duration = .milliseconds(25)

    static func run(_ times: [Int], transfer: @escaping @Sendable (Int) async throws -> Bool,
                    progress: @Sendable (Int) async -> Void) async throws -> Bool {
        guard !times.isEmpty else { return true }
        let clock = ContinuousClock()
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            var next = times.startIndex
            var nextStart = clock.now
            var completed = 0
            var unavailable = 0
            while next < times.endIndex || !group.isEmpty {
                if next < times.endIndex && next - completed < parallelism {
                    if clock.now < nextStart { try await clock.sleep(until: nextStart) }
                    let second = times[next]
                    guard group.addTaskUnlessCancelled(operation: { try await transfer(second) }) else {
                        throw CancellationError()
                    }
                    next += 1
                    nextStart = clock.now + startSpacing
                } else if let saved = try await group.next() {
                    completed += 1
                    if !saved { unavailable += 1 }
                    if completed.isMultiple(of: 24) || completed == times.count {
                        await progress(completed - unavailable)
                    }
                    if unavailable >= 4 {
                        group.cancelAll()
                        return false
                    }
                }
            }
            return unavailable == 0
        }
    }
}
