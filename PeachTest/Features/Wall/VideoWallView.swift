import SwiftUI

struct VideoWallView: View {
    let api: PeachAPI
    let filter: LibraryFilter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var preferences: Preferences
    @State private var items: [PeachItem] = []
    @State private var camera = WallCamera()
    @State private var savedCamera: WallCamera?
    @State private var dragOrigin: WallCamera?
    @State private var pinchOrigin: WallCamera?
    @State private var viewport = CGSize.zero
    @State private var placements: [WallPlacement] = []
    @State private var exploration = WallExploration()
    @State private var selectedKey: String?
    @State private var detail: PeachItem?
    @State private var playback: PlayerPresentation?
    @State private var fullPlayer: PlayerPresentation?
    @State private var busy = false
    @State private var hasMore = true
    @State private var offset = 0
    @State private var error: String?
    @State private var toast: String?
    private var finite: Bool { filter.hasActiveFilter }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(placements) { tile in
                    if items.indices.contains(tile.index) {
                        let item = items[tile.index]
                        ZStack {
                            WallArtwork(item: item, api: api, image: preferences.wallImage, ratio: tile.rect.width / tile.rect.height)
                            if selectedKey == tile.id {
                                if let playback {
                                    WallFocusView(session: playback, onClose: clearSelection,
                                                  onFullScreen: { fullPlayer = playback })
                                } else {
                                    focusActions(item)
                                }
                            } else {
                                Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                                    .font(.system(size: 11, weight: .bold).monospaced()).foregroundStyle(.white)
                                    .lineLimit(1).padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    .background(LinearGradient(colors: [.clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .frame(width: tile.rect.width * camera.scale, height: tile.rect.height * camera.scale)
                        .clipShape(RoundedRectangle(cornerRadius: selectedKey == tile.id ? 12 : 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.12)))
                        .position(x: tile.rect.midX * camera.scale + camera.x, y: tile.rect.midY * camera.scale + camera.y)
                        .zIndex(selectedKey == tile.id ? 2 : 0)
                        .onTapGesture { if selectedKey != tile.id { select(tile) } }
                    }
                }
            }
            .contentShape(Rectangle()).clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 7).onChanged { value in
                if playback != nil, let key = selectedKey, let tile = placements.first(where: { $0.id == key }) {
                    let rect = CGRect(x: tile.rect.minX * camera.scale + camera.x, y: tile.rect.minY * camera.scale + camera.y, width: tile.rect.width * camera.scale, height: tile.rect.height * camera.scale)
                    if rect.contains(value.startLocation) { return }
                }
                if dragOrigin == nil { dragOrigin = camera }
                guard let origin = dragOrigin else { return }
                camera = bounded(WallCamera(x: origin.x + value.translation.width, y: origin.y + value.translation.height, scale: origin.scale))
            }.onEnded { value in
                guard let origin = dragOrigin else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    camera = bounded(WallCamera(x: origin.x + value.predictedEndTranslation.width,
                                                 y: origin.y + value.predictedEndTranslation.height, scale: origin.scale))
                }
                dragOrigin = nil
            })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                if pinchOrigin == nil { pinchOrigin = camera }
                guard let origin = pinchOrigin else { return }
                camera = bounded(origin.zoomed(by: value.magnification,
                    anchor: CGPoint(x: value.startAnchor.x * viewport.width, y: value.startAnchor.y * viewport.height)))
            }.onEnded { _ in pinchOrigin = nil })
            .onAppear { viewport = geometry.size; refreshTiles() }
            .onChange(of: geometry.size) { _, size in viewport = size; refreshTiles() }
            .onChange(of: camera) { _, _ in refreshTiles() }
            .overlay(alignment: .top) { topBar }
            .overlay {
                if items.isEmpty {
                    if let error {
                        VStack(spacing: 12) { Text(error); Button("重试") { Task { await loadMore() } } }.foregroundStyle(.white)
                    } else if busy { ProgressView().tint(.white) }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast { Text(toast).font(.footnote).padding(12).foregroundStyle(.white).background(.black.opacity(0.8), in: Capsule()).padding(20) }
            }
        }
        .background(Color.black.ignoresSafeArea()).statusBarHidden()
        .task { await loadMore() }
        .sheet(item: $detail) { item in
            NavigationStack {
                ItemDetailView(item: item, api: api)
                    .navigationDestination(for: EntityRoute.self) { EntityDetailView(api: api, kind: $0.kind, name: $0.name) }
                    .navigationDestination(for: PeachItem.self) { ItemDetailView(item: $0, api: api) }
            }.preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $fullPlayer, onDismiss: {
            if let playback, !playback.controller.isPiPActive { Task { await playback.controller.activate() } }
        }) { session in PlayerView(session: session, preserveOnExit: true) }
        .onChange(of: detail?.id) { _, id in playback?.controller.setActive(id == nil && scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in if fullPlayer == nil { playback?.controller.setActive(phase == .active) } }
        .onDisappear { if fullPlayer == nil, playback?.controller.isPiPActive != true { playback?.close() } }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            icon("chevron.left", "退出播放墙") { playback?.close(); dismiss() }
            Spacer()
            Menu {
                ForEach(WallImage.allCases) { image in Button(image.label) { preferences.wallImage = image } }
            } label: { Text(preferences.wallImage.label).font(.caption).foregroundStyle(.white).padding(12).background(.black.opacity(0.6), in: Capsule()) }
            icon(preferences.wallMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", "播放墙声音") {
                preferences.wallMuted.toggle(); playback?.controller.setMuted(preferences.wallMuted)
            }
            icon("plus.magnifyingglass", "放大") { zoom(1.2) }
            icon("minus.magnifyingglass", "缩小") { zoom(1 / 1.2) }
        }.padding(.horizontal, 12).padding(.top, 8)
    }
    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.55), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private func focusActions(_ item: PeachItem) -> some View {
        VStack {
            HStack { Spacer(); icon("xmark", "收起") { clearSelection() } }
            Spacer()
            HStack {
                icon("play.fill", "播放") {
                    let session = PlayerPresentation(api: api, item: item)
                    session.controller.setMuted(preferences.wallMuted)
                    playback = session
                }
                icon(item.watchLater ? "bookmark.fill" : "bookmark", "稍后看") { Task { await toggleLater(item) } }
                icon("info.circle", "详情") { detail = item }
            }
        }.padding(10).background(LinearGradient(colors: [.clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
    private func bounded(_ camera: WallCamera) -> WallCamera {
        WallLayout.bounded(camera, count: items.count, viewport: viewport, finite: finite && selectedKey == nil)
    }
    private func zoom(_ factor: CGFloat) { camera = bounded(camera.zoomed(by: factor, anchor: CGPoint(x: viewport.width / 2, y: viewport.height / 2))) }
    private func select(_ tile: WallPlacement) {
        playback?.close(); playback = nil
        if selectedKey == nil { savedCamera = camera }
        selectedKey = tile.id
        let parts = tile.id.split(separator: ":").compactMap { Int($0) }
        let rect = WallLayout.frame(x: parts[0], y: parts[1], slot: parts[2], focused: parts[2])
        let scale = min(camera.scale, (viewport.width - 24) / rect.width, (viewport.height - 100) / rect.height)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            camera = WallCamera(x: viewport.width / 2 - rect.midX * scale,
                                y: (viewport.height + 50) / 2 - rect.midY * scale, scale: scale)
            refreshTiles()
        }
    }
    private func clearSelection() {
        playback?.close(); playback = nil; selectedKey = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            if let savedCamera { camera = savedCamera }
            refreshTiles()
        }
    }
    private func refreshTiles() {
        let visible = WallLayout.visible(count: items.count, finite: finite, camera: camera, viewport: viewport, focus: selectedKey)
        placements = finite ? visible : exploration.assign(visible, count: items.count, hasMore: hasMore)
        if hasMore, !busy, !items.isEmpty,
           (finite ? (placements.map(\.index).max() ?? 0) >= items.count - 12 : exploration.used.count >= items.count - 12) {
            Task { await loadMore() }
        }
    }
    private func loadMore() async {
        guard !busy, hasMore else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let page = try await api.items(filter, offset: offset, limit: 60)
            offset += page.items.count
            hasMore = !page.items.isEmpty && offset < (page.total ?? offset + (page.hasMore == true ? 1 : 0))
            items.append(contentsOf: page.items.filter { ($0.medium ?? "video") == "video" && $0.hasCover && !($0.coverKey.isEmpty && $0.displayNumber.isEmpty) })
            refreshTiles()
            if items.isEmpty && !hasMore { error = "当前筛选下没有带封面的影片" }
        } catch { self.error = error.localizedDescription; toast = error.localizedDescription }
    }
    private func toggleLater(_ item: PeachItem) async {
        do {
            let value = try await api.toggleWatchLater(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = PeachItem(copying: item, watchLater: value) }
            toast = value ? "已加入稍后看" : "已移出稍后看"
        } catch { toast = error.localizedDescription }
        try? await Task.sleep(for: .seconds(2)); toast = nil
    }
}

private struct WallArtwork: View {
    let item: PeachItem
    let api: PeachAPI
    let image: WallImage
    let ratio: CGFloat
    @State private var thumbnail: UIImage?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if image == .thumbnail, let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else if ratio < 1 { CoverPoster(item: item, api: api) }
                else { RemoteImage(url: api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey)) }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .task(id: "\(item.id):\(image.rawValue)") {
            guard image == .thumbnail else { return }
            let sheet = await PeachImageCache.shared.image(for: api.thumbURL(id: item.id))
            guard !Task.isCancelled else { return }
            thumbnail = sheet?.cropped(to: TimelineTile.nineGrid(time: 0.5, duration: 1))
        }
    }
}
