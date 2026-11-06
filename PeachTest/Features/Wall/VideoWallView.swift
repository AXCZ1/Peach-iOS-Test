import SwiftUI

/// Two-dimensional cover wall. Peach's desktop layout is a zoomable Folia
/// collage; on a phone the useful part is the same browsing unit — one block of
/// twelve covers in a varied mosaic — laid out in a fixed three-column field,
/// with cover/thumbnail switching, focus expansion, sound control and the same
/// watch-later / play / detail actions as the web wall.
struct VideoWallView: View {
    let api: PeachAPI
    let filter: LibraryFilter

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: Preferences
    @State private var items: [PeachItem] = []
    @State private var selected: PeachItem?
    @State private var state: LoadState = .loading
    @State private var zoom: CGFloat = 1
    @State private var toast: String?
    @State private var detailItem: PeachItem?
    @State private var playing: PeachItem?
    @State private var muted = false
    @State private var preview: PeachItem?

    private enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let templates: [[CGRect]] = [
        [CGRect(x: 0, y: 0, width: 3, height: 2), CGRect(x: 3, y: 0, width: 6, height: 4),
         CGRect(x: 9, y: 0, width: 3, height: 2), CGRect(x: 0, y: 2, width: 3, height: 2),
         CGRect(x: 9, y: 2, width: 3, height: 4), CGRect(x: 0, y: 4, width: 4, height: 4),
         CGRect(x: 4, y: 4, width: 2, height: 2), CGRect(x: 6, y: 4, width: 3, height: 2),
         CGRect(x: 4, y: 6, width: 2, height: 2), CGRect(x: 6, y: 6, width: 2, height: 2),
         CGRect(x: 8, y: 6, width: 2, height: 2), CGRect(x: 10, y: 6, width: 2, height: 2)],
        [CGRect(x: 0, y: 0, width: 2, height: 3), CGRect(x: 2, y: 0, width: 2, height: 3),
         CGRect(x: 4, y: 0, width: 2, height: 3), CGRect(x: 6, y: 0, width: 6, height: 4),
         CGRect(x: 0, y: 3, width: 6, height: 2), CGRect(x: 6, y: 4, width: 2, height: 4),
         CGRect(x: 8, y: 4, width: 2, height: 4), CGRect(x: 10, y: 4, width: 2, height: 2),
         CGRect(x: 0, y: 5, width: 2, height: 3), CGRect(x: 2, y: 5, width: 2, height: 3),
         CGRect(x: 4, y: 5, width: 2, height: 3), CGRect(x: 10, y: 6, width: 2, height: 2)],
        [CGRect(x: 0, y: 0, width: 6, height: 4), CGRect(x: 6, y: 0, width: 6, height: 3),
         CGRect(x: 6, y: 3, width: 4, height: 3), CGRect(x: 10, y: 3, width: 2, height: 2),
         CGRect(x: 0, y: 4, width: 4, height: 2), CGRect(x: 4, y: 4, width: 2, height: 2),
         CGRect(x: 10, y: 5, width: 2, height: 3), CGRect(x: 0, y: 6, width: 2, height: 2),
         CGRect(x: 2, y: 6, width: 2, height: 2), CGRect(x: 4, y: 6, width: 2, height: 2),
         CGRect(x: 6, y: 6, width: 2, height: 2), CGRect(x: 8, y: 6, width: 2, height: 2)]
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .loading:
                ProgressView().tint(PeachTheme.coral)
            case .failed(let message):
                VStack(spacing: 14) {
                    Text("播放墙无法打开").font(.headline).foregroundStyle(.white)
                    Text(message).font(.footnote).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                    Button("关闭") { dismiss() }.buttonStyle(.borderedProminent).tint(PeachTheme.coral)
                }
                .padding(30)
            case .ready:
                wall
            }
            topBar
            if let toast {
                Text(toast).font(.footnote).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 68)
            }
        }
        .statusBarHidden()
        .onAppear { muted = preferences.wallMuted }
        .task {
            muted = preferences.wallMuted
            await load()
        }
        .sheet(item: $detailItem) { item in
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
        .fullScreenCover(item: $playing) { item in
            PlayerView(item: item, api: api, startsMuted: muted)
        }
        .overlay {
            if let preview {
                WallFocusView(api: api, item: preview, muted: muted, onClose: { self.preview = nil },
                              onPlay: { playing = preview; self.preview = nil },
                              onLater: { Task { await toggleLater(preview) } },
                              onMute: {
                                  preferences.wallMuted.toggle()
                                  muted = preferences.wallMuted
                              },
                              onDetail: { detailItem = preview; self.preview = nil })
                    .transition(.opacity)
            }
        }
        .onChange(of: preview?.id) { _, value in
            if value == nil { selected = nil }
        }
    }

    private var wall: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { blockIndex, block in
                    WallBlockView(
                        api: api,
                        items: block,
                        template: templates[blockIndex % templates.count],
                        image: preferences.wallImage,
                        selected: selected,
                        onSelect: { item in
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selected = item }
                            preview = item
                        },
                        onOpenDetail: { detailItem = $0 },
                        onToggleLater: { item in await toggleLater(item) },
                        onPlay: { playing = $0 }
                    )
                    .frame(width: 360 * zoom, height: 240 * zoom)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
    }

    private var blocks: [[PeachItem]] {
        stride(from: 0, to: items.count, by: 12).map {
            Array(items[$0..<min($0 + 12, items.count)])
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 38, height: 38)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel("退出播放墙")
                Spacer()
                Menu {
                    ForEach(WallImage.allCases) { image in
                        Button(image.label) { preferences.wallImage = image }
                    }
                } label: {
                    Text(preferences.wallImage.label)
                        .font(.caption.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                Button {
                    preferences.wallMuted.toggle()
                    muted = preferences.wallMuted
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel(muted ? "打开播放墙声音" : "静音播放墙")
                Button { zoom = min(1.6, zoom + 0.2) } label: { zoomButton("plus.magnifyingglass") }
                Button { zoom = max(0.6, zoom - 0.2) } label: { zoomButton("minus.magnifyingglass") }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            Spacer()
        }
    }

    private func zoomButton(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 38, height: 38).background(.black.opacity(0.5), in: Circle())
    }

    private func load() async {
        state = .loading
        var sample = filter
        sample.sort = .seed
        sample.seed = Int.random(in: 1...99990)
        do {
            let page = try await api.items(sample, offset: 0, limit: 60)
            items = page.items.filter {
                ($0.medium ?? "video") == "video" && $0.hasCover
                    && !($0.coverKey.isEmpty && $0.displayNumber.isEmpty)
                    && $0.location != "online" && ($0.cost ?? "free") != "metered"
            }
            if let focused = selected, let fresh = items.first(where: { $0.id == focused.id }) {
                selected = fresh
            }
            guard !items.isEmpty else {
                state = .failed("当前筛选下没有带封面的可播放作品")
                return
            }
            state = .ready
        } catch let failure {
            state = .failed(failure.localizedDescription)
        }
    }

    private func toggleLater(_ item: PeachItem) async {
        do {
            let on = try await api.toggleWatchLater(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = PeachItem(copying: item, watchLater: on)
            }
            toast = on ? "已加入稍后看" : "已移出稍后看"
            try? await Task.sleep(for: .seconds(1.4))
            toast = nil
        } catch let failure {
            toast = failure.localizedDescription
        }
    }
}

private struct WallBlockView: View {
    let api: PeachAPI
    let items: [PeachItem]
    let template: [CGRect]
    let image: WallImage
    let selected: PeachItem?
    let onSelect: (PeachItem) -> Void
    let onOpenDetail: (PeachItem) -> Void
    let onToggleLater: (PeachItem) async -> Void
    let onPlay: (PeachItem) -> Void

    private let pitch: CGFloat = 28.8
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / (12 * pitch)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let rect = template[index % template.count]
                    WallTile(
                        api: api,
                        item: item,
                        image: image,
                        isSelected: selected?.id == item.id,
                        onSelect: { onSelect(item) },
                        onOpenDetail: { onOpenDetail(item) },
                        onToggleLater: { await onToggleLater(item) },
                        onPlay: { onPlay(item) }
                    )
                    .frame(width: rect.width * pitch * scale - gap,
                           height: rect.height * pitch * scale - gap)
                    .offset(x: rect.minX * pitch * scale, y: rect.minY * pitch * scale)
                    .zIndex(selected?.id == item.id ? 10 : 0)
                }
            }
        }
    }
}

private struct WallTile: View {
    let api: PeachAPI
    let item: PeachItem
    let image: WallImage
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onToggleLater: () async -> Void
    let onPlay: () -> Void

    private var source: URL? {
        image == .cover
            ? api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey)
            : api.thumbURL(id: item.id)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: source)
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                    .font(.system(size: 10, weight: .bold).monospaced())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if isSelected {
                    Text(item.performers.prefix(2).joined(separator: " · "))
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
            }
            .padding(6)
            if item.progress > 0 {
                VStack { Spacer(); Rectangle().fill(PeachTheme.coral).frame(height: 2) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: CGFloat(item.progress), anchor: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isSelected ? 10 : 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isSelected ? 10 : 3, style: .continuous)
            .stroke(isSelected ? PeachTheme.coral : .white.opacity(0.06), lineWidth: isSelected ? 2 : 1))
        .onTapGesture { isSelected ? onPlay() : onSelect() }
        .contextMenu {
            Button { onPlay() } label: { Label("播放", systemImage: "play.fill") }
            Button { onOpenDetail() } label: { Label("打开详情", systemImage: "info.circle") }
            Button { Task { await onToggleLater() } } label: {
                Label(item.watchLater ? "移出稍后看" : "稍后看", systemImage: item.watchLater ? "bookmark.fill" : "bookmark")
            }
        }
    }
}
