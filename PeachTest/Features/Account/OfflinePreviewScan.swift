import SwiftUI
import UIKit

@MainActor
final class OfflinePreviewScan: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var running = false
    @Published private(set) var status: String?
    @Published private(set) var bytes: Int64 = 0

    private let store = OfflinePreviewStore.shared
    private var api: PeachAPI?
    private var task: Task<Void, Never>?
    private var foreground = true

    func refreshSize(for api: PeachAPI) async {
        bytes = await store.size(origin: api.baseURL)
    }

    func setEnabled(_ value: Bool, api: PeachAPI) {
        if value {
            self.api = api
            enabled = true
            launchIfNeeded()
        } else {
            stop()
        }
    }

    func stop() {
        enabled = false
        api = nil
        if task != nil { status = "已停止；下次扫描继续补缺" }
        task?.cancel()
    }

    func setScene(_ phase: ScenePhase) {
        foreground = phase == .active
        if foreground {
            launchIfNeeded()
        } else if let task, enabled {
            status = "已暂停；返回 App 后继续"
            task.cancel()
        }
    }

    private func launchIfNeeded() {
        guard task == nil, enabled, foreground, let api else { return }
        status = "正在读取全部馆藏…"
        running = true
        task = Task {
            do {
                try await scan(api)
                try Task.checkCancellation()
                enabled = false
            } catch {
                if !Task.isCancelled {
                    if (error as? CocoaError)?.code == .fileWriteOutOfSpace {
                        status = "手机存储空间不足；清理空间后可继续扫描"
                    } else {
                        status = "扫描未完成：\(error.localizedDescription)"
                    }
                    enabled = false
                }
            }
            bytes = await store.size(origin: api.baseURL)
            task = nil
            running = false
            if !enabled { self.api = nil }
            launchIfNeeded()
        }
    }

    private func scan(_ api: PeachAPI) async throws {
        let origin = api.baseURL
        let items = try await OfflineCatalog.snapshot { offset, limit in
            try await api.items(OfflineCatalog.filter, offset: offset, limit: limit)
        }
        bytes = await store.size(origin: origin)
        var failures = 0
        for (offset, item) in items.enumerated() {
            try Task.checkCancellation()
            let progress = "已处理 \(offset) / \(items.count) 部 · 未完成 \(failures) 部"
            let title = item.displayNumber.isEmpty ? item.name : item.displayNumber
            status = "\(progress)\n\(title) · 正在读取预览索引"
            let cached = await store.entries(origin: origin, item: item)
            let index = await store.index(origin: origin, item: item)
            if let index, !index.times.isEmpty, cached.count == index.times.count { continue }
            let times: [Double]
            if let index {
                times = index.times
            } else {
                do {
                    let timeline = try await api.timeline(id: item.id)
                    times = PreviewSamplePlan.times(timeline, duration: item.duration)
                } catch let error as PeachAPIError where error.status == 404 {
                    times = PreviewSamplePlan.times(nil, duration: item.duration)
                }
            }
            guard !times.isEmpty else { failures += 1; continue }
            try await store.prepare(origin: origin, item: item, times: times)
            var reader: OriginalFrameReader?
            var work = OfflinePreviewWorkProgress(saved: cached.count)
            let saved = Set(cached.map(\.time))
            let pending = index?.pendingTimes(saved: saved) ?? times.filter { !saved.contains($0) }
            for (offset, time) in pending.enumerated() {
                try Task.checkCancellation()
                status = "\(progress)\n\(title) · 已缓存 \(work.saved) / \(times.count) 张 · 正在取第 \(offset + 1) / \(pending.count) 张缺图"
                let key = PreviewSamplePlan.transientKey(origin: origin, item: item, time: time)
                let data: Data
                if let existing = await MediaDiskCache.shared.read(key), UIImage(data: existing) != nil {
                    data = existing
                } else {
                    if reader == nil {
                        do { reader = try await OriginalFrameReader(api: api, item: item) }
                        catch let error as PeachAPIError where [404, 409, 503].contains(error.status ?? 0) {
                            _ = work.recordFailure()
                            break
                        }
                    }
                    guard let reader else { break }
                    do {
                        let frame = try await reader.capture(at: time)
                        try Task.checkCancellation()
                        data = try await Task.detached(priority: .utility) { try OriginalVideoFrame.png(frame) }.value
                    } catch {
                        try Task.checkCancellation()
                        if (error as NSError).domain == NSURLErrorDomain { throw error }
                        if work.recordFailure() {
                            try await store.deferRemaining(after: time, origin: origin, item: item)
                            break
                        }
                        continue
                    }
                }
                try await store.save(data, origin: origin, item: item, time: time)
                bytes += Int64(data.count)
                work.recordSaved()
            }
            if work.hadFailures { failures += 1 }
        }
        try Task.checkCancellation()
        try await store.prune(origin: origin, retaining: Set(items.map(\.id)))
        status = "已扫描 \(items.count) 部 · 未完成 \(failures) 部"
        if failures > 0 { status?.append("\n再次开启扫描可补缺") }
    }
}
