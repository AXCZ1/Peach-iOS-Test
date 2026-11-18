import SwiftUI

struct EntityBrowseView: View {
    let api: PeachAPI
    @State private var kind: EntityKind = .performer
    @State private var items: [PeachFacet] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            Picker("分类", selection: $kind) {
                ForEach(EntityKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .onChange(of: kind) { _, _ in Task { await load() } }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.35))
                TextField("搜索\(kind.label)", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                    .onSubmit { Task { await load() } }
                if !query.isEmpty {
                    Button { query = ""; Task { await load() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(PeachTheme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 20)

            if loading {
                Spacer()
                ProgressView().tint(PeachTheme.coral)
                Spacer()
            } else if let error {
                Spacer()
                ContentUnavailableView("无法读取索引", systemImage: "wifi.exclamationmark", description: Text(error))
                    .foregroundStyle(.white)
                Spacer()
            } else if items.isEmpty {
                ContentUnavailableView("暂无\(kind.label)", systemImage: "square.grid.2x2", description: Text(query.isEmpty ? "当前媒体库没有这一类索引。" : "没有匹配的结果。"))
                    .foregroundStyle(.white)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 18) {
                        ForEach(items) { facet in
                            NavigationLink(value: EntityRoute(kind: EntityKind.canonical(facet.entityKind ?? kind.rawValue), name: facet.key)) {
                                VStack(spacing: 8) {
                                    EntityAvatar(api: api, kind: facet.entityKind ?? kind.rawValue, facet: facet)
                                    Text(facet.key)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .lineLimit(1)
                                    Text("\(facet.count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .refreshable { await load() }
            }
        }
        .task {
            if loading || error != nil { await load() }
        }
    }

    private func load() async {
        let requestedKind = kind
        let requestedQuery = query
        loading = true
        error = nil
        do {
            let result = try await api.index(kind: requestedKind.apiKind, query: requestedQuery)
            guard !Task.isCancelled, kind == requestedKind, query == requestedQuery else { return }
            items = result
        } catch let failure {
            guard !Task.isCancelled, kind == requestedKind, query == requestedQuery else { return }
            error = failure.localizedDescription
            PeachRuntimeLogger.shared.log(
                "索引加载失败 kind=\(requestedKind.apiKind): \(failure.localizedDescription)",
                level: .error,
                category: "browse",
                source: "EntityBrowseView"
            )
        }
        loading = false
    }

}

struct EntityAvatar: View {
    let api: PeachAPI
    let kind: String
    let facet: PeachFacet

    var body: some View {
        ZStack {
            Circle().fill(PeachTheme.surface)
            if EntityKind.canonical(kind) == "studio", facet.hasLogo == true {
                RemoteImage(url: api.logoURL(studio: facet.key, version: facet.logoVersion), contentMode: .fit)
                    .clipShape(Circle())
            } else if let id = facet.entityID, facet.hasImage == true {
                RemoteImage(url: api.entityImageURL(kind: kind, id: id, version: facet.imageVersion))
                    .clipShape(Circle())
            } else {
                Text(String(facet.key.prefix(1)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 68, height: 68)
        .overlay(Circle().stroke(PeachTheme.line))
    }
}

struct EntityDetailView: View {
    let api: PeachAPI
    let kind: String
    let name: String
    @State private var selectedTag: String?
    @State private var entity: PeachEntity?
    @State private var items: [PeachItem] = []
    @State private var error: String?
    @State private var loading = true
    @State private var favorite = false
    @State private var favoriteBusy = false
    @State private var filteredCount = 0

    init(api: PeachAPI, kind: String, name: String, selectedTag: String? = nil) {
        self.api = api
        self.kind = kind
        self.name = name
        _selectedTag = State(initialValue: selectedTag)
    }

    private var filtersInPlace: Bool { EntityKind.canonical(kind) == "performer" }
    private var route: EntityRoute { EntityRoute(kind: kind, name: name, tag: selectedTag) }
    private var title: String {
        guard !filtersInPlace, let selectedTag else { return name }
        return "\(name) · \(selectedTag)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let entity, !entity.tags.isEmpty, filtersInPlace || (!loading && error == nil) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(entity.tags) { tag in
                                tagChip(tag)
                            }
                        }
                    }
                }
                if loading {
                    ProgressView().tint(PeachTheme.coral).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(PeachTheme.coral)
                } else if filtersInPlace, selectedTag != nil, items.isEmpty {
                    Text("没有符合此标签的作品")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
                        ForEach(items) { item in
                            NavigationLink {
                                ItemDetailView(item: item, api: api, tagScope: route)
                            } label: {
                                PeachCard(item: item, api: api)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(PeachTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(title)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: selectedTag) {
            if loading || error != nil { await load() }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: PeachFacet) -> some View {
        let selected = selectedTag == tag.key
        if filtersInPlace {
            Button {
                loading = true
                error = nil
                selectedTag = selectedTag == tag.key ? nil : tag.key
            } label: {
                Text("\(tag.key) \(tag.count)")
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 13).frame(height: 30)
                    .background(selected ? PeachTheme.coral : PeachTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(selected ? Color.clear : PeachTheme.line))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: route.selectingTag(tag.key)) {
                Text("\(tag.key) \(tag.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? PeachTheme.coral : .white.opacity(0.7))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(PeachTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(PeachTheme.surface)
                if let entity, entity.hasImage {
                    RemoteImage(url: api.entityImageURL(kind: kind, id: entity.id, version: entity.imageVersion))
                        .clipShape(Circle())
                } else {
                    Text(String(name.prefix(1))).font(.largeTitle.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                if !filtersInPlace || selectedTag == nil || (!loading && error == nil) {
                    Text("\(selectedTag == nil ? (entity?.assetCount ?? items.count) : filteredCount) 部作品")
                        .font(.caption).foregroundStyle(.white.opacity(0.42))
                }
                if let aliases = entity?.aliases, !aliases.isEmpty {
                    Text(aliases.prefix(2).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.white.opacity(0.3)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(favorite ? PeachTheme.amber : .white.opacity(0.55))
                    .frame(width: 40, height: 40)
                    .background(PeachTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(favoriteBusy || entity == nil)
            .accessibilityLabel(favorite ? "取消关注" : "关注")
        }
        .padding(.top, 8)
    }

    private func toggleFavorite() async {
        guard let entity else { return }
        favoriteBusy = true
        defer { favoriteBusy = false }
        do {
            let shortcuts = try await api.setFavorite(entityID: entity.id, on: !favorite)
            favorite = shortcuts.favorites.contains { $0.entityID == entity.id }
        } catch let failure {
            self.error = failure.localizedDescription
            PeachRuntimeLogger.shared.log(
                "实体收藏切换失败: \(failure.localizedDescription)",
                level: .error,
                category: "browse",
                source: "EntityDetailView"
            )
        }
    }

    private func load() async {
        let requestedRoute = route
        loading = true
        error = nil
        do {
            let page: PeachPage
            if !filtersInPlace || entity == nil {
                let loaded = try await api.entity(kind: kind, name: name)
                page = try await api.items(requestedRoute.filter, offset: 0, limit: 60)
                let shortcuts = try? await api.libraryShortcuts()
                guard !Task.isCancelled, route == requestedRoute else { return }
                entity = loaded
                favorite = shortcuts?.favorites.contains { $0.entityID == loaded.id } ?? false
            } else {
                page = try await api.items(requestedRoute.filter, offset: 0, limit: 60)
                guard !Task.isCancelled, route == requestedRoute else { return }
            }
            items = page.items
            filteredCount = page.total ?? page.items.count
        } catch let failure {
            guard !Task.isCancelled, route == requestedRoute else { return }
            error = failure.localizedDescription
            PeachRuntimeLogger.shared.log(
                "实体详情加载失败 kind=\(kind) name=\(name): \(failure.localizedDescription)",
                level: .error,
                category: "browse",
                source: "EntityDetailView"
            )
        }
        loading = false
    }
}
