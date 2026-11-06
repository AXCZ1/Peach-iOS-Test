import SwiftUI

/// Full-screen random playback, matching Peach's `/immerse` route: a shuffled
/// sample of up to 60 playable items under the current filters, vertical paging,
/// horizontal drag to seek, double-tap either half to skip, and the three
/// feedback actions with the live climax count.
struct ImmersiveView: View {
    let api: PeachAPI
    let filter: LibraryFilter
    var startID: Int?
    /// A saved playlist keeps its own order and may include non-JAV items;
    /// when present it replaces the random filter sample.
    var queue: [PeachItem]?

    init(api: PeachAPI, filter: LibraryFilter, startID: Int? = nil, queue: [PeachItem]? = nil) {
        self.api = api
        self.filter = filter
        self.startID = startID
        self.queue = queue
    }

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PeachItem] = []
    @State private var currentID: Int?
    @State private var state: LoadState = .loading
    @State private var toast: String?
    @State private var detailItem: PeachItem?
    @State private var detailOpen = false

    private enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().tint(PeachTheme.coral)
                    Text("加载内容").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(PeachTheme.coral)
                    Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    Button("关闭") { dismiss() }.buttonStyle(.borderedProminent).tint(PeachTheme.coral)
                }
                .padding(30)
            case .ready:
                pager
            }

            closeButton
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(.top, 70)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .task { await load() }
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
        .onChange(of: detailItem?.id) { _, value in
            detailOpen = value != nil
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        ImmersivePage(api: api, item: item, isActive: currentID == item.id && !detailOpen,
                                      onEnded: { advance(1) },
                                      onOpenDetail: { detailItem = item },
                                      onFeedback: { kind, count in
                                          if let index = items.firstIndex(where: { $0.id == item.id }) {
                                              items[index] = items[index].replacing(oCount: count)
                                          }
                                          showToast(kind)
                                      },
                                      onAdvance: { advance($0) })
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onAppear {
                if currentID == nil { currentID = items.first?.id }
            }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("关闭")
                Spacer()
                Text("\(indexLabel) / \(items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            Spacer()
        }
    }

    private var indexLabel: Int {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return 1 }
        return index + 1
    }

    private func advance(_ delta: Int) {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return }
        let next = min(max(0, index + delta), items.count - 1)
        guard next != index else { return }
        preloadMoreIfNeeded(next)
        withAnimation(.easeInOut(duration: 0.2)) { self.currentID = items[next].id }
    }

    private func preloadMoreIfNeeded(_ index: Int) {
        guard queue == nil else { return }
        guard index >= items.count - 3 else { return }
        Task {
            var sample = filter
            sample.sort = .seed
            sample.seed = Int.random(in: 1...99990)
            guard let page = try? await api.items(sample, offset: 0, limit: 60) else { return }
            let known = Set(items.map(\.id))
            let extra = page.items.filter {
                ($0.medium ?? "video") == "video" && $0.location != "online"
                    && ($0.duration ?? 0) > 0 && ($0.cost ?? "free") != "metered"
                    && !known.contains($0.id)
            }
            guard !extra.isEmpty else { return }
            items.append(contentsOf: extra)
        }
    }

    private func load() async {
        state = .loading
        if let queue, !queue.isEmpty {
            items = queue
            currentID = startID ?? queue.first?.id
            state = .ready
            return
        }
        var sample = filter
        sample.sort = .seed
        sample.seed = Int.random(in: 1...99990)
        do {
            let page = try await api.items(sample, offset: 0, limit: 60)
            var pool = page.items.filter {
                ($0.medium ?? "video") == "video" && $0.location != "online"
                    && ($0.duration ?? 0) > 0 && ($0.cost ?? "free") != "metered"
            }
            if let startID, !pool.contains(where: { $0.id == startID }),
               let start = try? await api.item(id: startID) {
                pool.insert(start, at: 0)
            }
            if startID == nil { pool.shuffle() }
            guard !pool.isEmpty else {
                state = .failed("当前筛选下没有可直接播放的内容")
                return
            }
            items = pool
            currentID = startID ?? items.first?.id
            state = .ready
        } catch let failure {
            state = .failed(failure.localizedDescription)
        }
    }

    private func showToast(_ kind: String) {
        let label: String
        switch kind {
        case "o": label = "已记一次高潮"
        case "seen": label = "已标记看过"
        case "dislike": label = "已标记不喜欢"
        case "error": label = "写入失败"
        default: label = "已更新"
        }
        withAnimation(.easeOut(duration: 0.15)) { toast = label }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }
}

private struct ImmersivePage: View {
    let api: PeachAPI
    let item: PeachItem
    let isActive: Bool
    let onEnded: () -> Void
    let onOpenDetail: () -> Void
    let onFeedback: (String, Int) -> Void
    let onAdvance: (Int) -> Void

    @StateObject private var controller: PlaybackController
    @State private var detail: PeachItem?
    @State private var busy = false
    @State private var scrubbing = false
    @State private var scrubValue = 0.0
    @State private var localCount: Int?

    init(api: PeachAPI, item: PeachItem, isActive: Bool, onEnded: @escaping () -> Void,
         onOpenDetail: @escaping () -> Void, onFeedback: @escaping (String, Int) -> Void,
         onAdvance: @escaping (Int) -> Void) {
        self.api = api
        self.item = item
        self.isActive = isActive
        self.onEnded = onEnded
        self.onOpenDetail = onOpenDetail
        self.onFeedback = onFeedback
        self.onAdvance = onAdvance
        _controller = StateObject(wrappedValue: PlaybackController(api: api, item: item))
    }

    private var current: PeachItem { detail ?? item }

    var body: some View {
        ZStack {
            Color.black
            if isActive, let player = controller.player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
            } else if !isActive {
                RemoteImage(url: api.coverURL(code: current.coverKey.isEmpty ? current.displayNumber : current.coverKey))
                    .ignoresSafeArea()
                    .blur(radius: 12)
                    .overlay(Color.black.opacity(0.55))
            }

            if isActive, case .preparing = controller.phase {
                VStack(spacing: 10) {
                    ProgressView().tint(PeachTheme.coral)
                    Text("加载中").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            if isActive, case .failed(let message) = controller.phase {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(PeachTheme.coral)
                    Text(message).font(.footnote).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("跳过") { onAdvance(1) }
                        .buttonStyle(.borderedProminent).tint(PeachTheme.coral)
                }
            }

            if isActive, !controller.isPlaying, controller.phase == .ready {
                Image(systemName: "pause.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 76, height: 76)
                    .background(.black.opacity(0.32), in: Circle())
                    .allowsHitTesting(false)
            }

            if isActive {
                MediaGestureOverlay(
                    onTap: { controller.togglePlayback() },
                    onDoubleTap: { x in
                        let side: Double = x < UIScreen.main.bounds.width / 2 ? -1 : 1
                        controller.skip(by: side * 10)
                    },
                    onSeekChanged: { dx in
                        let ratio = dx / UIScreen.main.bounds.width
                        controller.previewSeek(controller.currentTime + ratio * controller.duration)
                    },
                    onSeekEnded: { dx in
                        let ratio = dx / UIScreen.main.bounds.width
                        controller.seek(to: controller.currentTime + ratio * controller.duration)
                        controller.clearPreview()
                    }
                )
                .allowsHitTesting(true)
            }

            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { onOpenDetail() } label: {
                            Text(current.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                        Text(authorLine)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(spacing: 14) {
                        feedbackButton(kind: "dislike", icon: "hand.thumbsdown", active: current.feedback == "dislike", count: nil)
                        feedbackButton(kind: "seen", icon: "eye", active: current.feedback == "seen", count: nil)
                        feedbackButton(kind: "o", icon: "heart", active: false, count: localCount ?? current.oCount)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))

                if isActive {
                    seekBar
                    if let preview = controller.seekPreview {
                        Text(clock(preview))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.bottom, 6)
                    }
                }
            }
        }
        .onAppear {
            if isActive {
                controller.onEnded = onEnded
                Task { await controller.activate() }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                controller.onEnded = onEnded
                Task { await controller.activate() }
            } else {
                controller.pause()
            }
        }
        .onDisappear { controller.stop() }
        .task(id: item.id) {
            if let fresh = try? await api.item(id: item.id) { detail = fresh }
        }
        .onChange(of: controller.seekPreview) { _, preview in
            if preview == nil, scrubbing {
                scrubbing = false
            }
        }
    }

    private var authorLine: String {
        let who = current.performers.prefix(3).joined(separator: "、")
        if !who.isEmpty { return who + (current.performers.count > 3 ? " 等 \(current.performers.count) 人" : "") }
        return current.creator ?? current.studio ?? "未归属"
    }

    private var seekBar: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(PeachTheme.coral)
                        .frame(width: proxy.size.width * progress)
                }
                .frame(height: 3)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = true
                            scrubValue = max(0, min(controller.duration, controller.duration * value.location.x / max(proxy.size.width, 1)))
                        }
                        .onEnded { _ in
                            controller.seek(to: scrubValue)
                            scrubbing = false
                        }
                )
            }
            .frame(height: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var progress: Double {
        guard controller.duration > 0 else { return 0 }
        let time = controller.seekPreview ?? (scrubbing ? scrubValue : controller.currentTime)
        return max(0, min(1, time / controller.duration))
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func feedbackButton(kind: String, icon: String, active: Bool, count: Int?) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    let result = try await api.feedback(id: current.id, kind: kind)
                    if let fresh = try? await api.item(id: current.id) { detail = fresh }
                    if kind == "o", let count = result.oCount {
                        localCount = count
                    }
                    onFeedback(kind, result.oCount ?? current.oCount)
                } catch {
                    onFeedback("error", current.oCount)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? PeachTheme.coral : .white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.42), in: Circle())
                if let count {
                    Text("高潮 \(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(kind == "o" ? "记一次高潮" : kind == "seen" ? "标为看过" : "标为不喜欢")
    }
}

extension PeachItem {
    func replacing(oCount: Int) -> PeachItem {
        PeachItem(copying: self, oCount: oCount)
    }
}
