import Foundation
#if canImport(Network)
import Network
#endif

enum PeachLogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

struct PeachLogEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let ts: Double
    let level: String
    let category: String
    let source: String
    let message: String
    let fields: [String: String]
}

struct PeachLogUploadBatch: Encodable, Sendable {
    let batchId: String
    let deviceId: String
    let entries: [PeachLogEntry]

    enum CodingKeys: String, CodingKey {
        case batchId = "batch_id"
        case deviceId = "device_id"
        case entries
    }
}

struct PeachLogUploadResponse: Decodable, Sendable {
    let ok: Bool
    let accepted: Int
    let deduplicated: Int
    let expiredDropped: Int
    let invalidDropped: Int
    let prunedExisting: Int
    let fileBytes: Int64
    let serverTime: Double

    enum CodingKeys: String, CodingKey {
        case ok
        case accepted
        case deduplicated
        case expiredDropped = "expired_dropped"
        case invalidDropped = "invalid_dropped"
        case prunedExisting = "pruned_existing"
        case fileBytes = "file_bytes"
        case serverTime = "server_time"
    }
}

struct PeachLogSnapshot: Equatable, Sendable {
    let localFileBytes: Int64
    let pendingCount: Int
    let totalCount: Int
    let serverFileBytes: Int64?
    let serverUpdatedAt: TimeInterval?
    let lastError: String?
    let isUploading: Bool
    let recentEntries: [PeachLogEntry]
}

/// Persistent JSONL runtime log store with 1-hour retention, pre-persistence redaction,
/// retry tracking by entry ID, and offline recovery backfill for non-expired entries only.
actor PeachLogStore {
    struct RawRecord: Sendable {
        let id: String
        let ts: Double
        let level: String
        let category: String
        let source: String
        let message: String
        let fields: [String: String]
    }

    private struct ServerState: Codable, Sendable {
        var fileBytes: Int64
        var updatedAt: TimeInterval
    }

    private struct PersistedState: Codable, Sendable {
        var deviceID: String
        var acked: [String: Double]
        var servers: [String: ServerState]
    }

    typealias Uploader = @Sendable (PeachLogUploadBatch) async throws -> PeachLogUploadResponse

    private let directory: URL
    let logFileURL: URL
    private let stateFileURL: URL
    private let retentionSeconds: TimeInterval
    private let maxBatchSize: Int
    private let nowProvider: @Sendable () -> TimeInterval

    private var entries: [PeachLogEntry] = []
    private var state: PersistedState
    private var lastError: String?
    private var isUploading = false
    private var loaded = false

    init(
        directory: URL,
        retentionSeconds: TimeInterval = 3600,
        maxBatchSize: Int = 120,
        nowProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.directory = directory
        self.logFileURL = directory.appendingPathComponent("ios-runtime.jsonl", isDirectory: false)
        self.stateFileURL = directory.appendingPathComponent("upload-state.json", isDirectory: false)
        self.retentionSeconds = retentionSeconds
        self.maxBatchSize = maxBatchSize
        self.nowProvider = nowProvider
        self.state = PersistedState(deviceID: UUID().uuidString.lowercased(), acked: [:], servers: [:])
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    func append(_ records: [RawRecord], now overrideNow: TimeInterval? = nil) {
        ensureLoaded()
        let now = overrideNow ?? nowProvider()
        let cutoff = now - retentionSeconds
        let redacted = records.compactMap { record -> PeachLogEntry? in
            guard record.ts.isFinite, record.ts >= cutoff else { return nil }
            let message = PeachLogRedactor.redactText(record.message)
            let fields = PeachLogRedactor.redactFields(record.fields)
            return PeachLogEntry(
                id: record.id,
                ts: record.ts,
                level: record.level,
                category: record.category,
                source: PeachLogRedactor.redactText(record.source),
                message: message,
                fields: fields
            )
        }

        let needsPruneRewrite = entries.contains { $0.ts < cutoff } || state.acked.values.contains { $0 < cutoff }
        if !redacted.isEmpty {
            entries.append(contentsOf: redacted)
        }
        if needsPruneRewrite {
            _ = pruneInternal(now: now)
        } else if !redacted.isEmpty {
            appendLinesToDisk(redacted)
        }
    }

    @discardableResult
    func pruneExpired(now overrideNow: TimeInterval? = nil) -> Int64 {
        ensureLoaded()
        let now = overrideNow ?? nowProvider()
        _ = pruneInternal(now: now)
        return actualLocalFileBytes()
    }

    func snapshot(originKey: String?, now overrideNow: TimeInterval? = nil, recentLimit: Int = 120) -> PeachLogSnapshot {
        ensureLoaded()
        let now = overrideNow ?? nowProvider()
        _ = pruneInternal(now: now)
        let bytes = actualLocalFileBytes()
        let pendingCount = entries.reduce(into: 0) { count, entry in
            if state.acked[entry.id] == nil { count += 1 }
        }
        let serverState = originKey.flatMap { state.servers[$0] }
        let recent = Array(entries.suffix(recentLimit).reversed())
        return PeachLogSnapshot(
            localFileBytes: bytes,
            pendingCount: pendingCount,
            totalCount: entries.count,
            serverFileBytes: serverState?.fileBytes,
            serverUpdatedAt: serverState?.updatedAt,
            lastError: lastError,
            isUploading: isUploading,
            recentEntries: recent
        )
    }

    /// Uploads up to `maxBatches` of non-expired unacknowledged entries.
    /// Does nothing when there are no pending entries (no empty probe requests).
    func flushUploads(
        originKey: String,
        uploader: Uploader,
        maxBatches: Int = 8,
        now overrideNow: TimeInterval? = nil
    ) async -> PeachLogSnapshot {
        ensureLoaded()
        guard !isUploading else {
            return snapshot(originKey: originKey, now: overrideNow)
        }
        isUploading = true
        defer { isUploading = false }

        var remainingBatches = max(1, maxBatches)
        while remainingBatches > 0 {
            remainingBatches -= 1
            let now = overrideNow ?? nowProvider()
            _ = pruneInternal(now: now)
            let pending = entries.filter { entry in
                state.acked[entry.id] == nil && entry.ts >= (now - retentionSeconds)
            }
            guard !pending.isEmpty else { break }

            let slice = Array(pending.prefix(maxBatchSize)).map { Self.ensureRedacted($0) }
            let batch = PeachLogUploadBatch(
                batchId: UUID().uuidString.lowercased(),
                deviceId: state.deviceID,
                entries: slice
            )

            do {
                let response = try await uploader(batch)
                guard response.ok else {
                    lastError = "软路由日志接口返回失败"
                    break
                }
                for entry in slice {
                    state.acked[entry.id] = entry.ts
                }
                let updatedTime = overrideNow ?? nowProvider()
                state.servers[originKey] = ServerState(
                    fileBytes: max(Int64(0), response.fileBytes),
                    updatedAt: updatedTime
                )
                lastError = nil
                saveState()
            } catch {
                lastError = PeachLogRedactor.redactText(error.localizedDescription)
                break
            }
        }

        return snapshot(originKey: originKey, now: overrideNow)
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let decoder = Self.makeDecoder()
        if let data = try? Data(contentsOf: stateFileURL),
           let decoded = try? decoder.decode(PersistedState.self, from: data),
           !decoded.deviceID.isEmpty {
            state = decoded
        } else {
            saveState()
        }

        if let rawData = try? Data(contentsOf: logFileURL), !rawData.isEmpty,
           let content = String(data: rawData, encoding: .utf8) {
            var loadedEntries: [PeachLogEntry] = []
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = String(line).data(using: .utf8),
                      let entry = try? decoder.decode(PeachLogEntry.self, from: lineData) else { continue }
                loadedEntries.append(Self.ensureRedacted(entry))
            }
            entries = loadedEntries
        } else if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? Data().write(to: logFileURL, options: .atomic)
        }

        _ = pruneInternal(now: nowProvider())
    }

    private func pruneInternal(now: TimeInterval) -> Int {
        let cutoff = now - retentionSeconds
        let beforeCount = entries.count
        entries.removeAll { !$0.ts.isFinite || $0.ts < cutoff }
        let removedEntries = beforeCount - entries.count

        let ackedBefore = state.acked.count
        state.acked = state.acked.filter { $0.value >= cutoff }
        if state.acked.count != ackedBefore {
            saveState()
        }

        if removedEntries > 0 || !FileManager.default.fileExists(atPath: logFileURL.path) {
            rewriteLogFile()
        }
        return removedEntries
    }

    private func appendLinesToDisk(_ batch: [PeachLogEntry]) {
        let encoder = Self.makeEncoder()
        var buffer = Data()
        for entry in batch {
            guard var encoded = try? encoder.encode(entry) else { continue }
            encoded.append(0x0A)
            buffer.append(encoded)
        }
        guard !buffer.isEmpty else { return }
        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: buffer)
            } else {
                try buffer.write(to: logFileURL, options: .atomic)
            }
        } catch {
            rewriteLogFile()
        }
    }

    private func rewriteLogFile() {
        let encoder = Self.makeEncoder()
        var buffer = Data()
        for entry in entries {
            guard var encoded = try? encoder.encode(entry) else { continue }
            encoded.append(0x0A)
            buffer.append(encoded)
        }
        try? buffer.write(to: logFileURL, options: .atomic)
    }

    private func saveState() {
        let encoder = Self.makeEncoder()
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    private func actualLocalFileBytes() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let number = attrs[.size] as? NSNumber else {
            return 0
        }
        return max(Int64(0), number.int64Value)
    }

    private static func ensureRedacted(_ entry: PeachLogEntry) -> PeachLogEntry {
        PeachLogEntry(
            id: entry.id,
            ts: entry.ts,
            level: entry.level,
            category: entry.category,
            source: PeachLogRedactor.redactText(entry.source),
            message: PeachLogRedactor.redactText(entry.message),
            fields: PeachLogRedactor.redactFields(entry.fields)
        )
    }
}

/// Non-blocking singleton runtime logger capturing App, network, AVPlayer, and VLCKit diagnostics.
final class PeachRuntimeLogger: @unchecked Sendable {
    static let shared = PeachRuntimeLogger()

    let store: PeachLogStore
    private let bufferLock = NSLock()
    private var staging: [PeachLogStore.RawRecord] = []
    private let uploadLock = NSLock()
    private var uploader: PeachLogStore.Uploader?
    private var originKey: String?
    private var consecutiveFailures = 0
    private var nextUploadAllowedAt: TimeInterval = 0
    private var lastReportedUploadFailure: String?
    private var lastUploadFailureLoggedAt: TimeInterval = 0
    private var loopTask: Task<Void, Never>?

    #if canImport(Network)
    private let monitorQueue = DispatchQueue(label: "peach.runtime.logger.network", qos: .utility)
    private let pathMonitor = NWPathMonitor()
    private var wasNetworkSatisfied: Bool?
    #endif

    init(directory: URL? = nil, retentionSeconds: TimeInterval = 3600, startBackgroundLoop: Bool = true) {
        let targetDir: URL
        if let directory {
            targetDir = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            targetDir = base.appendingPathComponent("PeachLogs", isDirectory: true)
        }
        self.store = PeachLogStore(directory: targetDir, retentionSeconds: retentionSeconds)
        if startBackgroundLoop {
            startMaintenance()
        }
    }

    /// Appends one structured runtime log entry without blocking the calling thread or actor.
    func log(
        _ message: String,
        level: PeachLogLevel = .info,
        category: String = "app",
        source: String = "PeachTest",
        fields: [String: String] = [:],
        timestamp: TimeInterval? = nil
    ) {
        let record = PeachLogStore.RawRecord(
            id: UUID().uuidString.lowercased(),
            ts: timestamp ?? Date().timeIntervalSince1970,
            level: level.rawValue,
            category: category,
            source: source,
            message: message,
            fields: fields
        )
        bufferLock.lock()
        if staging.count >= 4000 {
            staging.removeFirst(staging.count - 3500)
        }
        staging.append(record)
        bufferLock.unlock()
    }

    func setUploader(_ uploader: PeachLogStore.Uploader?, originKey: String?) {
        uploadLock.lock()
        self.uploader = uploader
        self.originKey = originKey
        self.consecutiveFailures = 0
        self.nextUploadAllowedAt = 0
        self.lastReportedUploadFailure = nil
        uploadLock.unlock()
        if uploader != nil {
            Task.detached(priority: .utility) { [weak self] in
                await self?.flushAndUpload(forceUpload: true)
            }
        }
    }

    func triggerUpload() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.flushAndUpload(forceUpload: true)
        }
    }

    /// Flushes staged entries to disk, expires records older than 1 hour,
    /// and uploads pending records when due without performing standalone server size probes.
    func refreshSnapshot(syncPending: Bool = false) async -> PeachLogSnapshot {
        await flushStagedToStore()
        let (_, origin) = currentUploadConfig()
        if syncPending {
            await flushAndUpload(forceUpload: true)
        } else {
            _ = await store.pruneExpired()
        }
        return await store.snapshot(originKey: origin)
    }

    func flushStagedToStore() async {
        let drained = drainStaging()
        await store.append(drained)
    }

    func flushAndUpload(forceUpload: Bool = false) async {
        await flushStagedToStore()
        _ = await store.pruneExpired()

        let (activeUploader, origin) = currentUploadConfig()
        guard let activeUploader, let origin, !origin.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        if !forceUpload && shouldThrottleUpload(now: now) { return }

        let snapshot = await store.flushUploads(originKey: origin, uploader: activeUploader)
        if let err = snapshot.lastError {
            if recordUploadFailure(err, now: now) {
                log("日志后台上传失败（稍后自动补传）: \(err)", level: .warning, category: "log-sync", source: "PeachRuntimeLogger")
            }
        } else if recordUploadSuccess() {
            log("日志后台上传已恢复，服务端文件大小 \(snapshot.serverFileBytes ?? 0) bytes", level: .info, category: "log-sync", source: "PeachRuntimeLogger")
        }
    }

    private func shouldThrottleUpload(now: TimeInterval) -> Bool {
        uploadLock.lock()
        let blockedUntil = nextUploadAllowedAt
        uploadLock.unlock()
        return now < blockedUntil
    }

    private func recordUploadFailure(_ err: String, now: TimeInterval) -> Bool {
        var shouldLogFailure = false
        uploadLock.lock()
        consecutiveFailures += 1
        let backoff = min(15.0, Double(min(consecutiveFailures, 4)) * 3.0)
        nextUploadAllowedAt = Date().timeIntervalSince1970 + backoff
        if lastReportedUploadFailure != err || (now - lastUploadFailureLoggedAt) >= 60 {
            lastReportedUploadFailure = err
            lastUploadFailureLoggedAt = now
            shouldLogFailure = true
        }
        uploadLock.unlock()
        return shouldLogFailure
    }

    private func recordUploadSuccess() -> Bool {
        var recovered = false
        uploadLock.lock()
        if consecutiveFailures > 0 { recovered = true }
        consecutiveFailures = 0
        nextUploadAllowedAt = 0
        lastReportedUploadFailure = nil
        uploadLock.unlock()
        return recovered
    }

    private func startMaintenance() {
        #if canImport(Network)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            self.uploadLock.lock()
            let previous = self.wasNetworkSatisfied
            self.wasNetworkSatisfied = satisfied
            if satisfied {
                self.nextUploadAllowedAt = 0
            }
            self.uploadLock.unlock()
            self.log(
                "网络状态变化: \(satisfied ? "可用" : "不可用")",
                level: satisfied ? .info : .warning,
                category: "network",
                source: "NWPathMonitor",
                fields: ["interface_expensive": path.isExpensive ? "true" : "false", "constrained": path.isConstrained ? "true" : "false"]
            )
            if satisfied, previous == false {
                Task.detached(priority: .utility) { [weak self] in
                    await self?.flushAndUpload(forceUpload: true)
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
        #endif

        loopTask = Task.detached(priority: .utility) { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { break }
                tick += 1
                if tick >= 10 {
                    tick = 0
                    await self.flushAndUpload(forceUpload: false)
                } else {
                    await self.flushStagedToStore()
                }
            }
        }
    }

    private func drainStaging() -> [PeachLogStore.RawRecord] {
        bufferLock.lock()
        let items = staging
        staging.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        return items
    }

    private func currentUploadConfig() -> (PeachLogStore.Uploader?, String?) {
        uploadLock.lock()
        let u = uploader
        let o = originKey
        uploadLock.unlock()
        return (u, o)
    }
}
