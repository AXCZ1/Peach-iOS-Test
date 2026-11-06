import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case library = "馆藏"
    case browse = "索引"
    case account = "我的"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .library: return "rectangle.stack.fill"
        case .browse: return "square.grid.2x2.fill"
        case .account: return "person.crop.circle.fill"
        }
    }
}

struct LibraryRootView: View {
    let api: PeachAPI
    @ObservedObject var session: PeachSession
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var model = LibraryModel()
    @State private var libraries: [PeachLibrary] = []
    @State private var showFilter = false
    @State private var searchText = ""
    @State private var tab: RootTab = .library
    @State private var showImmersive = false
    @State private var showWall = false
    @State private var path = NavigationPath()
    @State private var history: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                PeachTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if tab == .library {
                        filterBar
                        searchBar
                        content
                    } else if tab == .browse {
                        EntityBrowseView(api: api)
                    } else {
                        AccountHubView(api: api, session: session, libraryCount: libraries.count)
                    }
                }
                .padding(.bottom, 68)
                bottomBar
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                model.attach(api)
                await loadLibraries()
                history = (try? await api.searchHistory()) ?? []
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityDetailView(api: api, kind: route.kind, name: route.name)
            }
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .stats: StatsView(api: api)
                case .tasks: TaskCenterView(api: api)
                case .management: ManagementView(api: api)
                case .playlists: PlaylistsView(api: api)
                }
            }
            .navigationDestination(for: PeachItem.self) { item in
                ItemDetailView(item: item, api: api)
            }
            .fullScreenCover(isPresented: $showImmersive) {
                ImmersiveView(api: api, filter: model.filter, startID: nil)
            }
            .fullScreenCover(isPresented: $showWall) {
                VideoWallView(api: api, filter: model.filter)
            }
        }
        .tint(PeachTheme.coral)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PeachMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab == .library ? "馆藏" : tab.rawValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer()
            if tab == .library {
                Button { showImmersive = true } label: {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 38)
                }
                .accessibilityLabel("进入沉浸模式")
                Button { showWall = true } label: {
                    Image(systemName: "square.grid.3x2")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 38)
                }
                .accessibilityLabel("进入播放墙")
                Button {
                    preferences.density = preferences.density == .big ? .dense : .big
                } label: {
                    Image(systemName: preferences.density == .big ? "rectangle.grid.2x2" : "square.grid.2x2")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 38)
                }
                .accessibilityLabel(preferences.density == .big ? "切换为小图" : "切换为大图")
                Button { showFilter = true } label: {
                    Image(systemName: model.filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(model.filter.hasActiveFilter ? PeachTheme.coral : .white.opacity(0.75))
                        .frame(width: 32, height: 38)
                }
                .accessibilityLabel("筛选")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CatalogState.allCases) { state in
                        chip(state.label, selected: model.filter.state == state) {
                            Task { await model.setState(state) }
                        }
                    }
                    if libraries.count > 1 {
                        Rectangle().fill(PeachTheme.line).frame(width: 1, height: 20)
                        ForEach(libraries) { library in
                            chip(library.name, selected: model.selectedLibraryID == library.id) {
                                Task { await model.select(libraryID: library.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    activeFilters
                    Menu {
                        ForEach(CatalogSort.allCases) { sort in
                            Button {
                                Task { await model.setSort(sort) }
                            } label: {
                                HStack {
                                    Text(sort.label)
                                    if model.filter.sort == sort { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortLabel)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(PeachTheme.surface, in: Capsule())
                    }
                    Button { Task { await model.shuffle() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "shuffle")
                            Text("换一批")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PeachTheme.coral)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(PeachTheme.coral.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var activeFilters: some View {
        if let performer = model.filter.performer {
            activeChip("演员 · \(performer)") { Task { await model.apply { $0.performer = nil } } }
        }
        if let studio = model.filter.studio {
            activeChip("厂牌 · \(studio)") { Task { await model.apply { $0.studio = nil } } }
        }
        if let tag = model.filter.tag {
            activeChip("标签 · \(tag)") { Task { await model.apply { $0.tag = nil } } }
        }
        if let series = model.filter.series {
            activeChip("系列 · \(series)") { Task { await model.apply { $0.series = nil } } }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            TextField("搜索片名、番号、演员、标签", text: $searchText)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)
                .onSubmit { applySearch() }
                .accessibilityIdentifier("library.search")
            if !searchText.isEmpty {
                Button { searchText = ""; applySearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(PeachTheme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PeachTheme.line))
            .padding(.horizontal, 20)
            if !history.isEmpty, model.filter.query.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(history.prefix(8), id: \.self) { item in
                            Button {
                                searchText = item
                                applySearch()
                            } label: {
                                Text(item)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 9)
                                    .frame(height: 24)
                                    .background(PeachTheme.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var columns: [GridItem] {
        if preferences.density == .big {
            return [GridItem(.flexible(), spacing: 12)]
        }
        // Peach's two density steps are 336px and 168px tiles. On a phone that
        // is one column versus two, not three.
        return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var content: some View {
        ScrollView {
            if model.items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 380)
            } else {
                LazyVGrid(columns: columns, spacing: preferences.density == .big ? 22 : 14) {
                    ForEach(model.items) { item in
                        NavigationLink(value: item) {
                            PeachCard(item: item, api: api, density: preferences.density, portrait: true)
                        }
                        .buttonStyle(.plain)
                        .task { await model.loadMoreIfNeeded(current: item) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)

                if model.hasMore {
                    ProgressView().tint(PeachTheme.coral).padding(.bottom, 96)
                }
            }
        }
        .refreshable { await model.reload() }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .loading, .idle:
            VStack(spacing: 16) {
                ProgressView().tint(PeachTheme.coral)
                Text("正在读取馆藏…").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        case .failed(let message):
            ContentUnavailableView {
                Label("无法读取馆藏", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.reload() } }.buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        case .loaded:
            ContentUnavailableView {
                Label("没有匹配的作品", systemImage: "rectangle.stack")
            } description: {
                Text(model.filter.query.isEmpty ? "这个筛选下没有作品。" : "试试其它关键词或清除筛选。")
            } actions: {
                Button("清除筛选") { Task { await model.clearFilter() } }
            }
            .foregroundStyle(.white)
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                ForEach(RootTab.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { tab = item }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 19, weight: .semibold))
                            Text(item.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(tab == item ? PeachTheme.coral : .white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .background(.ultraThinMaterial)
            .background(PeachTheme.background.opacity(0.82))
            .overlay(alignment: .top) { Rectangle().fill(PeachTheme.line).frame(height: 1) }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var subtitle: String {
        if !model.filter.query.isEmpty { return "搜索 · \(model.filter.query)" }
        if tab == .library, model.total > 0 { return "\(model.total) 部作品" }
        if libraries.count == 1, tab == .library { return libraries[0].name }
        return "Peach 0.52.0"
    }

    private var sortLabel: String {
        if model.filter.sort == .seed { return "随机" }
        return model.filter.sort.label + (model.filter.ascending ? " ↑" : " ↓")
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(selected ? PeachTheme.coral : PeachTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : PeachTheme.line))
        }
        .buttonStyle(.plain)
    }

    private func activeChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).lineLimit(1)
                Image(systemName: "xmark").font(.caption2)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(PeachTheme.coral)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(PeachTheme.coral.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadLibraries() async {
        do {
            libraries = try await api.libraries()
            if let library = libraries.first(where: { $0.id == model.selectedLibraryID }) ?? libraries.first {
                model.selectedLibraryID = library.id
                await model.reload()
            }
        } catch {
            model.selectedLibraryID = ""
            model.filter.libraryID = ""
            await model.reload()
        }
    }

    private func applySearch() {
        model.filter.query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await model.reload()
            await api.rememberSearch(model.filter.query)
            history = (try? await api.searchHistory()) ?? history
        }
    }
}

struct EntityRoute: Hashable {
    let kind: String
    let name: String
}

enum AccountRoute: Hashable {
    case stats
    case tasks
    case management
    case playlists
}
