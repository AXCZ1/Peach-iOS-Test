import SwiftUI

struct LibraryRootView: View {
    let api: PeachAPI
    @ObservedObject var session: PeachSession
    @StateObject private var model = LibraryModel()
    @State private var libraries: [PeachLibrary] = []
    @State private var showFilter = false
    @State private var showAccount = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PeachTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    filterBar
                    searchBar

                    if model.items.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                model.attach(api)
                await loadLibraries()
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAccount) {
                AccountSheet(session: session, libraryCount: libraries.count)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .tint(PeachTheme.coral)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PeachMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("馆藏")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer()
            Button { showFilter = true } label: {
                Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(hasActiveFilter ? PeachTheme.coral : .white.opacity(0.75))
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("筛选")
            Button { showAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("账户")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if libraries.count > 1 {
                    ForEach(libraries) { library in
                        chip(library.name, selected: model.selectedLibraryID == library.id) {
                            Task { await model.select(libraryID: library.id) }
                        }
                    }
                } else if let library = libraries.first {
                    Text(library.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                if let performer = model.filter.performer {
                    activeChip("演员 · \(performer)") {
                        model.filter.performer = nil
                        Task { await model.reload() }
                    }
                }
                if let studio = model.filter.studio {
                    activeChip("厂牌 · \(studio)") {
                        model.filter.studio = nil
                        Task { await model.reload() }
                    }
                }
                if let tag = model.filter.tag {
                    activeChip("标签 · \(tag)") {
                        model.filter.tag = nil
                        Task { await model.reload() }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
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
        .padding(.bottom, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 20) {
                ForEach(model.items) { item in
                    NavigationLink(value: item) {
                        PeachCard(item: item, api: api)
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)

            if model.hasMore {
                ProgressView().tint(PeachTheme.coral).padding(.bottom, 40)
            }
        }
        .refreshable { await model.reload() }
        .navigationDestination(for: PeachItem.self) { item in
            ItemDetailView(item: item, api: api)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .loading, .idle:
            VStack(spacing: 16) {
                ProgressView().tint(PeachTheme.coral)
                Text("正在读取馆藏…").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var subtitle: String {
        if !model.filter.query.isEmpty { return "搜索 · \(model.filter.query)" }
        if model.total > 0 { return "\(model.total) 部作品" }
        if libraries.count == 1 { return libraries[0].name }
        return "Peach 测试版"
    }

    private var hasActiveFilter: Bool {
        model.filter.query != "" || model.filter.performer != nil || model.filter.studio != nil || model.filter.tag != nil
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 13)
                .frame(height: 32)
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
            .frame(height: 32)
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
        Task { await model.reload() }
    }
}
