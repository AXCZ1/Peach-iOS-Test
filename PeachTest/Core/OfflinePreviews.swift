import Foundation

enum PreviewSamplePlan {
    static func times(_ timeline: TimelineMetadata?, duration: Double?) -> [Double] {
        if let timeline, let count = timeline.frames, count > 0 {
            let n = min(count, 30)
            let end = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Double.infinity
            let step = n > 1 ? Double(count - 1) / Double(n - 1) : 0
            let values = (0..<n).map { i in timeline.sampleTime(at: Int((Double(i) * step).rounded())) }
                .filter { $0.isFinite && $0 >= 0 && $0 < end }
            let unique = Array(Set(values)).sorted()
            if unique.count == n { return unique }
        }
        guard let duration, duration.isFinite, duration > 0 else { return [] }
        return (0..<30).map { (Double($0) + 0.5) * duration / 30 }
    }

    static func transientKey(origin: URL, item: PeachItem, time: Double) -> MediaCacheKey {
        MediaCacheKey(url: origin, kind: .originalFrame, resource: "direct:\(item.mediaCacheIdentity):\(time)")
    }
}

enum OfflineCatalog {
    // Fixed seed plus asset ID gives deterministic order across offset pages.
    static let filter = LibraryFilter(javOnly: false, sort: .seed, seed: 7)

    static func snapshot(page: @Sendable (Int, Int) async throws -> PeachPage) async throws -> [PeachItem] {
        let limit = 60
        var items: [PeachItem] = []
        var seen = Set<Int>()
        var expected: Int?
        while true {
            try Task.checkCancellation()
            let result = try await page(items.count, limit)
            try Task.checkCancellation()
            if expected == nil { expected = result.total }
            guard let expected, expected >= 0 else { throw incomplete }
            for item in result.items {
                guard seen.insert(item.id).inserted else { throw incomplete }
                items.append(item)
            }
            guard items.count <= expected else { throw incomplete }
            if items.count == expected {
                guard result.hasMore != true else { throw incomplete }
                return items
            }
            guard !result.items.isEmpty, result.hasMore != false else { throw incomplete }
        }
    }

    private static var incomplete: PeachAPIError {
        PeachAPIError(message: "馆藏未读完整，请重新扫描")
    }
}

struct OfflinePreviewWorkProgress {
    private(set) var saved: Int
    private(set) var consecutiveFailures = 0
    private(set) var hadFailures = false

    init(saved: Int) { self.saved = saved }

    mutating func recordSaved() {
        saved += 1
        consecutiveFailures = 0
    }

    mutating func recordFailure() -> Bool {
        hadFailures = true
        consecutiveFailures += 1
        return consecutiveFailures >= 2
    }
}

actor OfflinePreviewStore {
    static let shared = OfflinePreviewStore(root: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("PeachOfflinePreviews", isDirectory: true))

    struct Index: Codable, Equatable, Sendable {
        let identity: String
        let times: [Double]
        var resumeAfter: Double? = nil

        func pendingTimes(saved: Set<Double>) -> [Double] {
            guard let resumeAfter, let previous = times.firstIndex(of: resumeAfter) else {
                return times.filter { !saved.contains($0) }
            }
            let next = times.index(after: previous)
            return (Array(times[next...]) + Array(times[..<next])).filter { !saved.contains($0) }
        }
    }

    struct Entry: Equatable, Sendable {
        let time: Double
        let url: URL
    }

    private let root: URL
    init(root: URL) { self.root = root }

    func index(origin: URL, item: PeachItem) -> Index? {
        let path = work(origin, item.id).appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: path),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              index.identity == item.mediaCacheIdentity else { return nil }
        return index
    }

    func prepare(origin: URL, item: PeachItem, times: [Double]) throws {
        try Task.checkCancellation()
        let dir = work(origin, item.id)
        let files = version(origin, item)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        #if os(iOS)
        var root = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        #endif
        let resumeAfter = index(origin: origin, item: item)?.resumeAfter
        try writeIndex(Index(identity: item.mediaCacheIdentity, times: times, resumeAfter: resumeAfter), to: dir)
        // New-version files have their own directory so a replaced video never reads its old frames.
        for old in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
            where old.lastPathComponent != files.lastPathComponent &&
                  (try? old.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            try FileManager.default.removeItem(at: old)
        }
    }

    func deferRemaining(after time: Double, origin: URL, item: PeachItem) throws {
        try Task.checkCancellation()
        guard var index = index(origin: origin, item: item) else { return }
        index.resumeAfter = time
        try writeIndex(index, to: work(origin, item.id))
    }

    private func writeIndex(_ index: Index, to directory: URL) throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }

    func entries(origin: URL, item: PeachItem) -> [Entry] {
        guard let index = index(origin: origin, item: item) else { return [] }
        return index.times.compactMap { time in
            let url = frameURL(origin, item, time)
            return FileManager.default.fileExists(atPath: url.path) ? Entry(time: time, url: url) : nil
        }
    }

    func frame(origin: URL, item: PeachItem, time: Double) -> Data? {
        try? Data(contentsOf: frameURL(origin, item, time), options: .mappedIfSafe)
    }

    func save(_ data: Data, origin: URL, item: PeachItem, time: Double) throws {
        try Task.checkCancellation()
        let options: Data.WritingOptions
        #if os(iOS)
        options = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        options = .atomic
        #endif
        try data.write(to: frameURL(origin, item, time), options: options)
    }

    func prune(origin: URL, retaining: Set<Int>) throws {
        let path = originDirectory(origin)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        for child in try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            if let id = Int(child.lastPathComponent), !retaining.contains(id) {
                try FileManager.default.removeItem(at: child)
            }
        }
    }

    func size(origin: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: originDirectory(origin), includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        var bytes: Int64 = 0
        while let path = files?.nextObject() as? URL {
            if let info = try? path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), info.isRegularFile == true {
                bytes += Int64(info.fileSize ?? 0)
            }
        }
        return bytes
    }

    func clear(origin: URL) throws {
        let path = originDirectory(origin)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    private func originDirectory(_ origin: URL) -> URL {
        root.appendingPathComponent(MediaDiskCache.filename(MediaCacheKey(url: origin).origin), isDirectory: true)
    }

    private func work(_ origin: URL, _ id: Int) -> URL {
        originDirectory(origin).appendingPathComponent(String(id), isDirectory: true)
    }

    private func version(_ origin: URL, _ item: PeachItem) -> URL {
        work(origin, item.id).appendingPathComponent(MediaDiskCache.filename(item.mediaCacheIdentity), isDirectory: true)
    }

    private func frameURL(_ origin: URL, _ item: PeachItem, _ time: Double) -> URL {
        version(origin, item).appendingPathComponent(String(time.bitPattern, radix: 16) + ".png")
    }
}
