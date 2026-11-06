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
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 18) {
                        ForEach(items) { facet in
                            NavigationLink(value: EntityRoute(kind: kind.apiKind, name: facet.key)) {
                                VStack(spacing: 8) {
                                    EntityAvatar(api: api, kind: kind.apiKind, facet: facet)
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
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            items = try await api.index(kind: kind.apiKind, query: query)
        } catch let failure {
            error = failure.localizedDescription
        }
        loading = false
    }
}

enum EntityKind: String, CaseIterable, Identifiable {
    case performer
    case studio
    case tag
    case series
    case creator

    var id: String { rawValue }

    var label: String {
        switch self {
        case .performer: return "演员"
        case .studio: return "厂牌"
        case .tag: return "标签"
        case .series: return "系列"
        case .creator: return "创作者"
        }
    }

    var apiKind: String {
        switch self {
        case .performer: return "performers"
        case .studio: return "studios"
        case .tag: return "tags"
        case .series: return "series"
        case .creator: return "creators"
        }
    }
}

struct EntityAvatar: View {
    let api: PeachAPI
    let kind: String
    let facet: PeachFacet

    var body: some View {
        ZStack {
            Circle().fill(PeachTheme.surface)
            if let id = facet.entityID, facet.hasImage == true {
                RemoteImage(url: api.entityImageURL(kind: kind, id: id))
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
    @State private var entity: PeachEntity?
    @State private var items: [PeachItem] = []
    @State private var error: String?
    @State private var loading = true
    @State private var favorite = false
    @State private var favoriteBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if loading {
                    ProgressView().tint(PeachTheme.coral).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(PeachTheme.coral)
                } else {
                    if let entity, !entity.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(entity.tags) { tag in
                                    NavigationLink(value: EntityRoute(kind: "tag", name: tag.key)) {
                                        Text("\(tag.key) \(tag.count)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .padding(.horizontal, 10).frame(height: 28)
                                            .background(PeachTheme.surface, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
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
        .navigationTitle(name)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(PeachTheme.surface)
                if let entity, entity.hasImage {
                    RemoteImage(url: api.entityImageURL(kind: kind, id: entity.id))
                        .clipShape(Circle())
                } else {
                    Text(String(name.prefix(1))).font(.largeTitle.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("\(entity?.assetCount ?? items.count) 部作品")
                    .font(.caption).foregroundStyle(.white.opacity(0.42))
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
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            var filter = LibraryFilter()
            switch kind {
            case "performer": filter.performer = name
            case "studio": filter.studio = name
            case "tag": filter.tag = name
            case "series": filter.series = name
            case "creator": filter.creator = name
            default: break
            }
            let loaded = try await api.entity(kind: kind, name: name)
            entity = loaded
            items = try await api.items(filter, offset: 0, limit: 60).items
            let shortcuts = try? await api.libraryShortcuts()
            favorite = shortcuts?.favorites.contains { $0.entityID == loaded.id } ?? false
        } catch let failure {
            error = failure.localizedDescription
        }
        loading = false
    }
}
