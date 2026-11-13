import CryptoKit
import Network
import SwiftUI
import UIKit

@MainActor
final class SeekPreviewSync: ObservableObject {
    @Published private(set) var source: SeekPreviewSource?
    @Published private(set) var status: String?
    @Published private(set) var onWiFi = false
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cache = SeekPreviewCache.shared
    private var api: PeachAPI?
    private var foreground = false
    private var worker: Task<Void, Never>?
    private var backgroundTime: UIBackgroundTaskIdentifier = .invalid

    init() {
        source = UserDefaults.standard.string(forKey: SeekPreviewSource.preference)
            .flatMap(URL.init(string:)).map(SeekPreviewSource.init)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.onWiFi != connected else { return }
                self.onWiFi = connected
                if connected { self.startIfPossible() } else { self.worker?.cancel() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "peach.seek-previews.wifi"))
    }

    deinit { monitor.cancel() }

    func configure(address: String, password: String) throws {
        let url = try PeachAPI.normalizedBaseURL(address)
        guard url.scheme == "https" else { throw PeachAPIError(message: "Media Browser 地址需使用 HTTPS") }
        if password.isEmpty {
            guard try SavedPeachPassword.read(for: url, service: SavedPeachPassword.seekPreviewService) != nil else {
                throw PeachAPIError(message: "请输入 Media Browser 的访问密码")
            }
        } else {
            try SavedPeachPassword.save(password, for: url, service: SavedPeachPassword.seekPreviewService)
        }
        UserDefaults.standard.set(url.absoluteString, forKey: SeekPreviewSource.preference)
        source = SeekPreviewSource(origin: url)
        restart()
    }

    func disconnect() throws {
        if let source { try SavedPeachPassword.remove(for: source.origin, service: SavedPeachPassword.seekPreviewService) }
        UserDefaults.standard.removeObject(forKey: SeekPreviewSource.preference)
        source = nil
        status = nil
        restart()
    }

    func setAPI(_ api: PeachAPI?) {
        guard self.api !== api else { return }
        self.api = api
        restart()
    }

    func setScene(_ phase: ScenePhase) {
        if phase == .active {
            foreground = true
            startIfPossible()
        } else if phase == .background {
            foreground = false
            if backgroundTime == .invalid { worker?.cancel() }
        }
    }

    private func restart() {
        if let worker { worker.cancel() } else { startIfPossible() }
    }

    private func startIfPossible() {
        guard foreground, onWiFi, worker == nil, let source, let api else { return }
        worker = Task {
            await sync(api, source: source)
            worker = nil
            if Task.isCancelled { startIfPossible() }
        }
    }

    private func sync(_ api: PeachAPI, source: SeekPreviewSource) async {
        do {
            while foreground && !Task.isCancelled {
                do {
                    try await runWithBackgroundTime(api, source: source)
                    PeachRuntimeLogger.shared.log("Seek 预览图库同步轮次完成 origin=\(source.origin.absoluteString)", level: .info, category: "seek-sync", source: "SeekPreviewSync")
                } catch {
                    try Task.checkCancellation()
                    status = error.localizedDescription
                    PeachRuntimeLogger.shared.log("Seek 预览图库同步失败: \(error.localizedDescription)", level: .error, category: "seek-sync", source: "SeekPreviewSync")
                    if let error = error as? PeachAPIError, error.status == 401 || error.status == 403 { return }
                }
                guard foreground else { return }
                try await Task.sleep(for: .seconds(1800))
            }
        } catch {
            if !foreground, source == self.source { status = "已保留同步进度 · 回到 Peach 后继续" }
        }
    }

    private func runWithBackgroundTime(_ api: PeachAPI, source: SeekPreviewSource) async throws {
        backgroundTime = UIApplication.shared.beginBackgroundTask(withName: "Sync seek thumbnails") { [weak self] in
            self?.worker?.cancel()
            self?.endBackgroundTime()
        }
        defer { endBackgroundTime() }
        try await run(api, source: source)
    }

    private func endBackgroundTime() {
        guard backgroundTime != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTime)
        backgroundTime = .invalid
    }

    private func run(_ api: PeachAPI, source: SeekPreviewSource) async throws {
        status = "正在读取馆藏…"
        let items = try await OfflineCatalog.snapshot { offset, limit in
            try await api.items(OfflineCatalog.filter, offset: offset, limit: limit)
        }.filter { $0.medium == nil || $0.medium == "video" }
        guard let password = try SavedPeachPassword.read(for: source.origin, service: SavedPeachPassword.seekPreviewService) else {
            throw PeachAPIError(message: "请重新填写 Media Browser 的访问密码", status: 401)
        }
        let client = MediaBrowserSeekClient(source: source, hash: Self.sha256)
        defer { client.session.invalidateAndCancel() }
        try await client.login(password)
        let origin = api.baseURL
        var ready = 0
        for (offset, item) in items.enumerated() {
            try Task.checkCancellation()
            let progress = "已缓存 \(ready) / \(items.count) 部 · 正在检查第 \(offset + 1) 部\n\(item.name)"
            status = progress
            guard let entry = try await client.find(item), let fingerprint = entry.fingerprint else { continue }
            let work: SeekPreviewCache.Work
            if let existing = try await cache.existing(origin: origin, source: source, item: item, fingerprint: fingerprint) {
                work = existing
            } else if let index = try await client.index(for: item, entry: entry, fingerprint: fingerprint) {
                work = try await cache.prepare(index, origin: origin, source: source, item: item)
            } else { continue }
            let cache = self.cache
            let total = work.index.times.count
            let alreadySaved = total - work.missing.count
            let complete = try await SeekFrameDownloads.run(work.missing) { second in
                do {
                    let bytes = try await client.frame(second, index: work.index)
                    try await cache.save(bytes, second: second, work: work)
                    return true
                } catch let error as PeachAPIError where error.status == 404 { return false }
            } progress: { completed in
                await self.updateFrameProgress(progress, saved: alreadySaved + completed, total: total)
            }
            if complete { ready += 1 }
        }
        try await cache.prune(origin: origin, source: source, keeping: Set(items.map(\.id)))
        try Task.checkCancellation()
        status = "已缓存 \(ready) / \(items.count) 部" + (ready == items.count ? "" : " · 未就绪的作品将在下次同步时再检查")
    }

    private func updateFrameProgress(_ title: String, saved: Int, total: Int) {
        guard !Task.isCancelled else { return }
        status = title + "\n已缓存 \(saved) / \(total) 张"
    }

    nonisolated private static func sha256(_ value: String) -> String {
        let digits = Array("0123456789abcdef".utf8)
        let bytes = SHA256.hash(data: Data(value.utf8)).flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct SeekPreviewSettings: View {
    @EnvironmentObject private var sync: SeekPreviewSync
    @State private var address = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        Section {
            TextField("Media Browser HTTPS 地址", text: $address)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL)
            SecureField("Media Browser 访问密码", text: $password)
            Button("保存并同步") {
                do {
                    try sync.configure(address: address, password: password)
                    address = sync.source?.origin.absoluteString ?? ""
                    password = ""
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            if sync.source != nil {
                Text(sync.onWiFi ? (sync.status ?? "等待同步") : "连接 Wi‑Fi 后继续")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("断开缩略图来源", role: .destructive) {
                    do { try sync.disconnect(); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("进度条缩略图")
        } footer: {
            Text("连接 Wi‑Fi 即可同步，可以离开此页面。系统暂停后，回到 Peach 会继续补齐。")
        }
        .onAppear { address = sync.source?.origin.absoluteString ?? "" }
    }
}
