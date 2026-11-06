import SwiftUI

struct AccountHubView: View {
    let api: PeachAPI
    @ObservedObject var session: PeachSession
    let libraryCount: Int

    var body: some View {
        List {
            Section("个人记录") {
                NavigationLink(value: AccountRoute.stats) {
                    Label("统计与观看历史", systemImage: "chart.bar.xaxis")
                }
                NavigationLink(value: AccountRoute.playlists) {
                    Label("播放列表", systemImage: "playlist")
                }
            }
            Section("管理") {
                NavigationLink(value: AccountRoute.tasks) {
                    Label("任务中心", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: AccountRoute.management) {
                    Label("数据管理与配置", systemImage: "wrench.and.screwdriver")
                }
            }
            Section("连接") {
                LabeledContent("服务", value: session.address)
                LabeledContent("馆藏", value: "\(libraryCount) 个")
                LabeledContent("Peach", value: "0.52.0")
            }
            Section {
                Button("退出登录", role: .destructive) { session.signOut() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachTheme.background)
        .foregroundStyle(.white)
        .padding(.bottom, 70)
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct StatsView: View {
    let api: PeachAPI
    @State private var stats: PeachStats?
    @State private var error: String?
    @State private var opened: PeachItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let stats {
                    HStack(spacing: 10) {
                        metric("看过", "\(stats.consumption?.played ?? 0)")
                        metric("高潮", "\(stats.consumption?.oTotal ?? 0)")
                        metric("喜欢", "\(stats.consumption?.liked ?? 0)")
                    }
                    if !stats.recent.isEmpty {
                        Text("最近观看").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.4))
                        ForEach(stats.recent) { item in
                            Button {
                                Task { opened = try? await api.item(id: item.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: api.posterURL(id: item.id))
                                        .frame(width: 72, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.footnote).foregroundStyle(.white).lineLimit(1)
                                        ProgressView(value: item.progress).tint(PeachTheme.coral)
                                        Text("\(Int(item.progress * 100))%").font(.caption2).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let error {
                    Text(error).foregroundStyle(PeachTheme.coral)
                } else {
                    ProgressView().tint(PeachTheme.coral)
                }
            }
            .padding(20)
        }
        .background(PeachTheme.background.ignoresSafeArea())
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            do { stats = try await api.stats() }
            catch let failure { self.error = failure.localizedDescription }
        }
        .sheet(item: $opened) { item in
            NavigationStack {
                ItemDetailView(item: item, api: api)
                    .navigationDestination(for: EntityRoute.self) { route in
                        EntityDetailView(api: api, kind: route.kind, name: route.name)
                    }
                    .navigationDestination(for: PeachItem.self) { next in
                        ItemDetailView(item: next, api: api)
                    }
            }
                .preferredColorScheme(.dark)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(PeachTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TaskCenterView: View {
    let api: PeachAPI
    @State private var tasks: PeachTasks?
    @State private var error: String?

    var body: some View {
        List {
            if let tasks {
                Section("进行中") {
                    if tasks.running.isEmpty { Text("没有进行中的任务").foregroundStyle(.secondary) }
                    ForEach(tasks.running) { task in row(task) }
                }
                Section("已结束") {
                    ForEach(tasks.finished.prefix(20)) { task in row(task) }
                }
            } else if let error {
                Text(error).foregroundStyle(PeachTheme.coral)
            } else {
                ProgressView().tint(PeachTheme.coral)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachTheme.background)
        .foregroundStyle(.white)
        .navigationTitle("任务中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ task: PeachTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.taskLabel).font(.footnote.weight(.medium))
                Spacer()
                Text(task.status).font(.caption2).foregroundStyle(.secondary)
            }
            if let total = task.progressTotal, total > 0 {
                ProgressView(value: Double(task.progressCurrent ?? 0), total: Double(total))
                    .tint(PeachTheme.coral)
            }
            if let label = task.progressLabel, !label.isEmpty {
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func load() async {
        do { tasks = try await api.tasks() }
        catch let failure { self.error = failure.localizedDescription }
    }
}

struct ManagementView: View {
    let api: PeachAPI
    @State private var configuration: PeachConfiguration?
    @State private var processing: PeachLibraryProcessing?
    @State private var follow: PeachFollow?
    @State private var downloads: PeachDownloads?
    @State private var error: String?

    var body: some View {
        List {
            Section("Peach 配置") {
                if let configuration {
                    LabeledContent("版本", value: configuration.facts.first(where: { $0.term == "版本" })?.value ?? "—")
                    LabeledContent("端口", value: "\(configuration.port ?? 0)")
                    LabeledContent("馆藏目录", value: "\(configuration.libraryCount ?? 0) 个")
                    LabeledContent("访问模式", value: configuration.accessMode ?? "—")
                    Text("配置修改属于服务端操作，本测试版只展示当前值。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("扫描与资料") {
                if let processing {
                    LabeledContent("状态", value: processing.status ?? "—")
                    LabeledContent("阶段", value: processing.stage ?? "—")
                    LabeledContent("已检查", value: "\(processing.checked ?? 0) / \(processing.total ?? 0)")
                    LabeledContent("待复核", value: "\(processing.issueCount ?? 0)")
                }
                Text("启动全库扫描会写入生产馆藏，本测试版不触发。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("关注") {
                if let follow {
                    LabeledContent("新", value: "\(follow.counts?.new ?? 0)")
                    LabeledContent("已保存", value: "\(follow.counts?.saved ?? 0)")
                    LabeledContent("来源", value: "\(follow.sources.count)")
                    if follow.sources.isEmpty {
                        Text("当前没有关注来源；添加来源属于 Peach 网页管理操作。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("下载") {
                if let downloads {
                    LabeledContent("可用", value: downloads.available == true ? "是" : "否")
                    LabeledContent("任务", value: "\(downloads.tasks.count)")
                }
            }
            if let error { Section { Text(error).foregroundStyle(PeachTheme.coral) } }
        }
        .scrollContentBackground(.hidden)
        .background(PeachTheme.background)
        .foregroundStyle(.white)
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        error = nil
        configuration = try? await api.configuration()
        processing = try? await api.libraryProcessing()
        follow = try? await api.follow()
        downloads = try? await api.downloads()
        if configuration == nil { error = "无法读取 Peach 配置" }
    }
}

struct PlaylistsView: View {
    let api: PeachAPI
    @State private var playlists: [PeachPlaylist] = []
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        List {
            Section("新建") {
                HStack {
                    TextField("播放列表名称", text: $name)
                    Button("创建") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("播放列表") {
                if playlists.isEmpty { Text("还没有播放列表").foregroundStyle(.secondary) }
                ForEach(playlists) { playlist in
                    Button {
                        Task { await open(playlist) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.footnote.weight(.medium))
                            Text("\(playlist.itemCount) 个视频").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error { Section { Text(error).foregroundStyle(PeachTheme.coral) } }
        }
        .scrollContentBackground(.hidden)
        .background(PeachTheme.background)
        .foregroundStyle(.white)
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .fullScreenCover(item: $queue) { queue in
            ImmersiveView(api: api, filter: LibraryFilter(), startID: queue.first.id, queue: queue.items)
        }
    }

    @State private var queue: PlaylistQueue?

    private func open(_ playlist: PeachPlaylist) async {
        do {
            let full = try await api.playlist(id: playlist.id)
            let items = full.items ?? []
            guard !items.isEmpty else {
                error = "这个播放列表还没有视频"
                return
            }
            let first = full.currentAssetID.flatMap { id in
                items.first(where: { $0.id == id })
            } ?? items[0]
            queue = PlaylistQueue(first: first, items: items)
        } catch let failure {
            self.error = failure.localizedDescription
        }
    }

    private func load() async {
        do { playlists = try await api.playlists() }
        catch let failure { self.error = failure.localizedDescription }
    }

    private func create() async {
        do {
            _ = try await api.addPlaylist(name: name.trimmingCharacters(in: .whitespaces), ids: [])
            name = ""
            await load()
        } catch let failure {
            self.error = failure.localizedDescription
        }
    }
}

struct PlaylistQueue: Identifiable {
    let first: PeachItem
    let items: [PeachItem]
    var id: Int { first.id }
}

