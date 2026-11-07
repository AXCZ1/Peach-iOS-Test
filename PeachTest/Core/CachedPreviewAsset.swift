import Foundation

struct HTTPByteRange: Equatable, Sendable {
    let bounds: ClosedRange<Int64>
    let length: Int64

    init?(_ header: String) {
        let parts = header.split(separator: " ")
        guard parts.count == 2, parts[0] == "bytes" else { return nil }
        let interval = parts[1].split(separator: "/", omittingEmptySubsequences: false)
        guard interval.count == 2, let length = Int64(interval[1]) else { return nil }
        let offsets = interval[0].split(separator: "-", omittingEmptySubsequences: false)
        guard offsets.count == 2, let first = Int64(offsets[0]), let last = Int64(offsets[1]),
              first >= 0, first <= last, last < length else { return nil }
        self.bounds = first...last
        self.length = length
    }
}

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import UniformTypeIdentifiers

struct PreviewRangeReply: Sendable {
    let range: HTTPByteRange
    let validator: String?
    let data: Data
}

struct PreviewRangeSource: Sendable {
    static let blockSize: Int64 = 512 * 1024
    typealias Fetch = @Sendable (ClosedRange<Int64>, String?) async throws -> PreviewRangeReply

    let length: Int64
    private let validator: String
    private let origin: URL
    private let identity: String
    private let cache: MediaDiskCache
    private let fetch: Fetch

    static func open(origin: URL, identity: String, cache: MediaDiskCache = .shared, fetch: @escaping Fetch) async throws -> Self {
        let probe = try await fetch(0...0, nil)
        guard probe.range.bounds == 0...0, let validator = probe.validator, !validator.isEmpty else {
            throw PeachAPIError(message: "播放源不支持稳定的分段缓存")
        }
        return Self(length: probe.range.length, validator: validator, origin: origin, identity: identity, cache: cache, fetch: fetch)
    }

    func block(containing offset: Int64) async throws -> (start: Int64, data: Data) {
        let start = offset / Self.blockSize * Self.blockSize
        let end = min(start + Self.blockSize, length) - 1
        let key = MediaCacheKey(url: origin, kind: .previewVideo, resource: "\(identity):\(validator):\(length):\(start)")
        let expected = Int(end - start + 1)
        if let data = await cache.read(key), data.count == expected { return (start, data) }
        let reply = try await fetch(start...end, validator)
        guard reply.range.length == length, reply.range.bounds == start...end, reply.data.count == expected,
              reply.validator == nil || reply.validator == validator else {
            throw PeachAPIError(message: "播放源的分段范围已变化")
        }
        try Task.checkCancellation()
        await cache.store(reply.data, for: key)
        return (start, reply.data)
    }
}

@MainActor
final class CachedPreviewAsset: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    let asset: AVURLAsset
    private let source: PreviewRangeSource
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(source: PreviewRangeSource) {
        self.source = source
        asset = AVURLAsset(url: URL(string: "peach-preview://media/\(UUID().uuidString).mp4")!)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: .main)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        let id = ObjectIdentifier(request)
        tasks[id] = Task {
            defer { tasks[id] = nil }
            do {
                if let info = request.contentInformationRequest {
                    info.contentType = UTType.mpeg4Movie.identifier
                    info.contentLength = source.length
                    info.isByteRangeAccessSupported = true
                }
                if let bytes = request.dataRequest {
                    let end = bytes.requestsAllDataToEndOfResource ? source.length
                        : min(source.length, bytes.requestedOffset + Int64(bytes.requestedLength))
                    var offset = max(bytes.currentOffset, bytes.requestedOffset)
                    while offset < end {
                        try Task.checkCancellation()
                        let block = try await source.block(containing: offset)
                        try Task.checkCancellation()
                        let start = Int(offset - block.start)
                        let count = min(block.data.count - start, Int(end - offset))
                        bytes.respond(with: block.data.subdata(in: start..<(start + count)))
                        offset += Int64(count)
                    }
                }
                request.finishLoading()
            } catch {
                if !Task.isCancelled { request.finishLoading(with: error) }
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    func cancel() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
}
#endif
