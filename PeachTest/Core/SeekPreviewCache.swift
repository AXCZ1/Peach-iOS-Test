import Foundation

struct SeekPreviewSource: Equatable, Sendable {
    static let preference = "peach.seekPreviews.source"
    static let root = "NAS"
    static let folder = "/hdd2/videos/2"
    static let width = 240
    let origin: URL

    var scope: String { "\(origin.absoluteString)|\(Self.root)|\(Self.folder)" }
}

struct SeekSourceEntry: Decodable, Sendable {
    let root: String
    let path: String
    let name: String
    let type: String
    let sizeBytes: Int64
    let modifiedAt: String
    let thumbnailUrl: String?

    var fingerprint: String? {
        guard let thumbnailUrl, let url = URLComponents(string: thumbnailUrl), url.path == "/api/thumb",
              let id = url.queryItems?.first(where: { $0.name == "id" })?.value,
              id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { return nil }
        return id
    }

    static func match(_ entries: [Self], name: String, size: Int64) -> Self? {
        let normalized = name.precomposedStringWithCanonicalMapping.lowercased()
        let candidates = entries.filter {
            $0.root == SeekPreviewSource.root && $0.type == "video" && $0.sizeBytes == size
                && $0.path.hasPrefix(SeekPreviewSource.folder + "/")
                && !$0.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
                && $0.name.precomposedStringWithCanonicalMapping.lowercased() == normalized
                && $0.path.split(separator: "/").last.map(String.init) == $0.name
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    var relativePath: String { String(path.dropFirst("/hdd2/".count)) }

    func modifiedTimeNs(hash: (String) -> String) -> Int64? {
        guard let fingerprint else { return nil }
        let end = modifiedAt.index(modifiedAt.startIndex, offsetBy: 19, limitedBy: modifiedAt.endIndex)
        guard let end else { return nil }
        let rest = modifiedAt[end...]
        let fraction = rest.first == "." ? String(rest.dropFirst().prefix { $0.isASCII && $0.isNumber }) : ""
        let zone = rest.dropFirst(fraction.isEmpty ? 0 : fraction.count + 1)
        guard fraction.count <= 9,
              let whole = ISO8601DateFormatter().date(from: String(modifiedAt[..<end]) + zone),
              whole.timeIntervalSince1970 >= 0, whole.timeIntervalSince1970 < 9_000_000_000,
              let nanos = Int64(fraction.padding(toLength: 9, withPad: "0", startingAt: 0))
        else { return nil }
        let estimate = Int64(whole.timeIntervalSince1970) * 1_000_000_000 + nanos
        // Search index timestamps round to microseconds. The cover key verifies the exact mtime.
        for delta in 0...2_000 {
            let offset = (delta + 1) / 2 * (delta.isMultiple(of: 2) ? 1 : -1)
            let candidate = estimate + Int64(offset)
            if hash("natural-aspect-v1|/mnt\(path)|\(sizeBytes)|\(candidate)") == fingerprint { return candidate }
        }
        return nil
    }

    func previewDirectory(mtime: Int64, interval: Int, hash: (String) -> String) -> String {
        let key = hash("relative_v1|\(relativePath)|\(sizeBytes)|\(mtime)|\(interval)|\(SeekPreviewSource.width)")
        return "/hdd2/.media-thumbs/video-preview/\(key)"
    }
}

struct SeekSourceManifest: Decodable, Sendable {
    let keyMode: String
    let complete: Bool
    let relativePath: String
    let sizeBytes: Int64
    let modifiedTimeNs: Int64
    let durationSeconds: Int
    let interval: Int
    let width: Int
    let frames: [Int]

    func matches(_ entry: SeekSourceEntry, mtime: Int64, interval: Int) -> Bool {
        guard let first = frames.first, let last = frames.last else { return false }
        return keyMode == "relative_v1" && complete && relativePath == entry.relativePath
            && sizeBytes == entry.sizeBytes && modifiedTimeNs == mtime
            && self.interval == interval && width == SeekPreviewSource.width
            && first >= 0 && last <= durationSeconds
            && zip(frames, frames.dropFirst()).allSatisfy { $0 < $1 }
    }
}

actor SeekPreviewCache {
    static let shared = SeekPreviewCache(root: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("PeachSeekPreviews", isDirectory: true))

    struct Index: Codable, Equatable, Sendable {
        let identity: String
        let fingerprint: String
        let remoteDirectory: String
        let interval: Int
        let times: [Int]
    }

    struct Work: Sendable {
        let index: Index
        let directory: URL
        let missing: [Int]
    }

    struct Frames: Sendable {
        let directory: URL
        let interval: Int
        let times: [Int]

        func nearest(to seconds: Double) -> URL? {
            guard seconds.isFinite, let first = times.first else { return nil }
            var lower = 0
            var upper = times.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if Double(times[middle]) < seconds { lower = middle + 1 } else { upper = middle }
            }
            let before = lower > 0 ? times[lower - 1] : first
            let after = lower < times.count ? times[lower] : before
            let best = seconds - Double(before) <= Double(after) - seconds ? before : after
            guard abs(Double(best) - seconds) <= Double(interval) else { return nil }
            return directory.appendingPathComponent(SeekPreviewCache.frameName(best))
        }
    }

    private let root: URL
    init(root: URL) { self.root = root }

    static func frameName(_ time: Int) -> String { String(format: "%06d.webp", time) }

    func existing(origin: URL, source: SeekPreviewSource, item: PeachItem, fingerprint: String) throws -> Work? {
        try Task.checkCancellation()
        let dir = directory(origin, source, item.id)
        guard let index = readIndex(dir) else { return nil }
        guard index.identity == item.mediaCacheIdentity, index.fingerprint == fingerprint else {
            try FileManager.default.removeItem(at: dir)
            return nil
        }
        let files = try fileNames(dir)
        return Work(index: index, directory: dir, missing: index.times.filter { !files.contains(Self.frameName($0)) })
    }

    func prepare(_ index: Index, origin: URL, source: SeekPreviewSource, item: PeachItem) throws -> Work {
        try Task.checkCancellation()
        let dir = directory(origin, source, item.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if os(iOS)
        var root = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        #endif
        try JSONEncoder().encode(index).write(to: dir.appendingPathComponent("index.json"), options: .atomic)
        return Work(index: index, directory: dir, missing: index.times)
    }

    func save(_ bytes: Data, second: Int, work: Work) throws {
        try Task.checkCancellation()
        try bytes.write(to: work.directory.appendingPathComponent(Self.frameName(second)), options: .atomic)
    }

    func frames(origin: URL, source: SeekPreviewSource, item: PeachItem) -> Frames? {
        let dir = directory(origin, source, item.id)
        guard let index = readIndex(dir), index.identity == item.mediaCacheIdentity,
              let files = try? fileNames(dir) else { return nil }
        return Frames(directory: dir, interval: index.interval,
                      times: index.times.filter { files.contains(Self.frameName($0)) })
    }

    func prune(origin: URL, source: SeekPreviewSource, keeping ids: Set<Int>) throws {
        try Task.checkCancellation()
        let dir = scope(origin, source)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            if let id = Int(item.lastPathComponent), !ids.contains(id) { try FileManager.default.removeItem(at: item) }
        }
    }

    private func scope(_ origin: URL, _ source: SeekPreviewSource) -> URL {
        root.appendingPathComponent(MediaDiskCache.filename(origin.absoluteString + "|" + source.scope), isDirectory: true)
    }

    private func directory(_ origin: URL, _ source: SeekPreviewSource, _ id: Int) -> URL {
        scope(origin, source).appendingPathComponent(String(id), isDirectory: true)
    }

    private func readIndex(_ directory: URL) -> Index? {
        guard let bytes = try? Data(contentsOf: directory.appendingPathComponent("index.json")) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: bytes)
    }

    private func fileNames(_ directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }
}
