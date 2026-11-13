import Foundation

struct MediaCacheKey: Hashable, Sendable {
    enum Kind: String, Sendable {
        case artwork, originalFrame, previewVideo

        var capacity: Int {
            switch self {
            case .artwork: 128 * 1024 * 1024
            case .originalFrame, .previewVideo: 256 * 1024 * 1024
            }
        }
    }

    let origin: String
    let kind: Kind
    let resource: String

    init(url: URL, kind: Kind = .artwork, resource: String? = nil) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        origin = components?.string ?? url.absoluteString
        self.kind = kind
        self.resource = resource ?? url.absoluteString
    }
}

actor MediaDiskCache {
    static let shared = MediaDiskCache(root: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                                            ?? FileManager.default.temporaryDirectory).appendingPathComponent("PeachMedia-v1", isDirectory: true))
    private let root: URL
    private let capacityOverride: Int?
    private var usage: [URL: Int] = [:]

    init(root: URL, capacityOverride: Int? = nil) {
        self.root = root
        self.capacityOverride = capacityOverride
    }

    func read(_ key: MediaCacheKey, maxAge: TimeInterval? = nil) -> Data? {
        let path = file(for: key)
        guard let attributes = try? path.resourceValues(forKeys: [.contentModificationDateKey]),
              let written = attributes.contentModificationDate,
              maxAge.map({ Date().timeIntervalSince(written) < $0 }) ?? true else { return nil }
        return try? Data(contentsOf: path)
    }

    func store(_ data: Data, for key: MediaCacheKey) {
        let limit = capacityOverride ?? key.kind.capacity
        guard !data.isEmpty, data.count <= limit else { return }
        let path = file(for: key)
        let directory = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let priorSize = (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let bytes = usage[directory] ?? entries(in: directory).reduce(0) { $0 + $1.1 }
            #if os(iOS)
            try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: path, options: .atomic)
            #endif
            usage[directory] = bytes + data.count - priorSize
            if usage[directory, default: 0] > limit {
                trim(directory, to: limit * 9 / 10, keeping: path)
            }
        } catch {
            PeachRuntimeLogger.shared.log(
                "磁盘缓存写入失败 \(key.kind.rawValue): \(error.localizedDescription)",
                level: .warning,
                category: "cache",
                source: "MediaDiskCache"
            )
        }
    }

    func clear(origin: URL) throws {
        let path = self.origin(MediaCacheKey(url: origin).origin)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
        usage = usage.filter { $0.key.deletingLastPathComponent() != path }
    }

    private func file(for key: MediaCacheKey) -> URL {
        origin(key.origin).appending(path: key.kind.rawValue, directoryHint: .isDirectory)
            .appending(path: Self.filename(key.resource))
    }

    private func origin(_ origin: String) -> URL {
        root.appending(path: Self.filename(origin), directoryHint: .isDirectory)
    }

    private func entries(in directory: URL) -> [(URL, Int, Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return files.compactMap { url -> (URL, Int, Date)? in
            guard let attributes = try? url.resourceValues(forKeys: keys),
                  let size = attributes.fileSize, let written = attributes.contentModificationDate else { return nil }
            return (url, size, written)
        }
    }

    private func trim(_ directory: URL, to limit: Int, keeping newest: URL) {
        let entries = entries(in: directory)
        var bytes = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) where url != newest {
            if bytes <= limit { break }
            if (try? FileManager.default.removeItem(at: url)) != nil { bytes -= size }
        }
        usage[directory] = bytes
    }

    static func filename(_ value: String) -> String {
        // Stable across launches; these names index app-owned cache files only.
        let hash = value.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}

extension PeachItem {
    var mediaCacheIdentity: String {
        "\(id):\(name):\(size ?? 0):\(duration ?? 0):\(width ?? 0)x\(height ?? 0)"
    }
}
