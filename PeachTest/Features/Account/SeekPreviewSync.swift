import CryptoKit
import Network
import SwiftUI

@MainActor
final class SeekPreviewSync: ObservableObject {
    @Published private(set) var source: SeekPreviewSource?
    @Published private(set) var status: String?
    @Published private(set) var onWiFi = false
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cache = SeekPreviewCache.shared

    init() {
        source = UserDefaults.standard.string(forKey: SeekPreviewSource.preference)
            .flatMap(URL.init(string:)).map(SeekPreviewSource.init)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.onWiFi = connected }
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
        configurationRevision += 1
    }

    func disconnect() throws {
        if let source { try SavedPeachPassword.remove(for: source.origin, service: SavedPeachPassword.seekPreviewService) }
        UserDefaults.standard.removeObject(forKey: SeekPreviewSource.preference)
        source = nil
        status = nil
        configurationRevision += 1
    }

    @Published private(set) var configurationRevision = 0

    struct Trigger: Equatable {
        let active: Bool
        let peach: URL?
        let configuration: Int
    }

    func sync(_ api: PeachAPI?) async {
        guard let source, let api, onWiFi else { return }
        do {
            while !Task.isCancelled {
                do {
                    try await run(api, source: source)
                } catch {
                    try Task.checkCancellation()
                    status = error.localizedDescription
                    if let error = error as? PeachAPIError, error.status == 401 || error.status == 403 { return }
                }
                try await Task.sleep(for: .seconds(1800))
            }
        } catch { }
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
            let progress = "已检查 \(offset + 1) / \(items.count) 部 · \(item.name)"
            status = progress
            guard let entry = try await client.find(item), let fingerprint = entry.fingerprint else { continue }
            let work: SeekPreviewCache.Work
            if let existing = try await cache.existing(origin: origin, source: source, item: item, fingerprint: fingerprint) {
                work = existing
            } else if let index = try await client.index(for: item, entry: entry, fingerprint: fingerprint) {
                work = try await cache.prepare(index, origin: origin, source: source, item: item)
            } else { continue }
            var missing = 0
            for start in stride(from: 0, to: work.missing.count, by: 2) {
                if start.isMultiple(of: 24) {
                    status = progress + "\n本次待补 \(start) / \(work.missing.count) 张"
                }
                let batch = work.missing[start..<min(start + 2, work.missing.count)]
                missing += try await withThrowingTaskGroup(of: Bool.self) { group in
                    let cache = self.cache
                    for second in batch {
                        group.addTask {
                            do {
                                let bytes = try await client.frame(second, index: work.index)
                                try await cache.save(bytes, second: second, work: work)
                                return true
                            } catch let error as PeachAPIError where error.status == 404 { return false }
                        }
                    }
                    var unavailable = 0
                    for try await saved in group where !saved { unavailable += 1 }
                    return unavailable
                }
                // Yield between pairs so bulk fetching leaves room for regular video playback.
                try await Task.sleep(for: .milliseconds(150))
                if missing >= 4 { break }
            }
            if missing == 0 { ready += 1 }
        }
        try await cache.prune(origin: origin, source: source, keeping: Set(items.map(\.id)))
        try Task.checkCancellation()
        status = "已缓存 \(ready) / \(items.count) 部" + (ready == items.count ? "" : " · 未就绪的作品将在下次同步时再检查")
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
            Text("App 在前台连接 Wi‑Fi 时提前缓存 Media Browser 已生成的小图。")
        }
        .onAppear { address = sync.source?.origin.absoluteString ?? "" }
    }
}
