import SwiftUI

struct ImmersiveView: View {
    let api: PeachAPI
    let filter: LibraryFilter
    var startID: Int?
    var queue: [PeachItem]?

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PeachItem] = []
    @State private var currentID: Int?
    @State private var loading = true
    @State private var error: String?
    @State private var loadMoreError: String?
    @State private var pagination = ImmersivePagination()
    @State private var refillTask: Task<Void, Never>?
    @State private var pendingAdvanceFrom: Int?
    @State private var toast: String?
    @State private var undoAction: SingleUseAction?
    @State private var toastID = UUID()
    @State private var detailItem: PeachItem?
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if loading {
                ProgressView("加载内容").tint(PeachTheme.coral).foregroundStyle(.white)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error).foregroundStyle(.white.opacity(0.7))
                    Button("关闭") { dismiss() }.buttonStyle(.borderedProminent).tint(PeachTheme.coral)
                }.padding(30)
            } else {
                pager
            }
            if controlsVisible { closeButton }
            if let toast {
                ToastBar(message: toast, undo: undoAction)
                    .padding(.horizontal, 20).padding(.top, 68)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if let loadMoreError {
                VStack {
                    Spacer()
                    Button {
                        requestRefill()
                    } label: {
                        Label("继续加载失败，点此重试", systemImage: "arrow.clockwise")
                            .font(.caption).padding(12).background(.black.opacity(0.8), in: Capsule())
                    }
                    .foregroundStyle(.white).padding(.bottom, 160)
                    .accessibilityHint(loadMoreError)
                }
            }
        }
        .statusBarHidden()
        .task { await load() }
        .onChange(of: currentID) { _, _ in requestRefill() }
        .onDisappear { refillTask?.cancel() }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                ItemDetailView(item: item, api: api)
                    .navigationDestination(for: EntityRoute.self) { route in
                        EntityDetailView(api: api, kind: route.kind, name: route.name)
                    }
                    .navigationDestination(for: PeachItem.self) { next in
                        ItemDetailView(item: next, api: api)
                    }
            }.preferredColorScheme(.dark)
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        ImmersivePage(api: api, item: item,
                                      isActive: currentID == item.id && detailItem == nil,
                                      controlsVisible: $controlsVisible,
                                      onEnded: { if currentID == item.id { advance(1) } },
                                      onOpenDetail: { detailItem = item },
                                      onFeedback: { kind, count in feedback(kind, id: item.id, count: count) },
                                      onAdvance: { advance($0) })
                            .frame(width: proxy.size.width, height: proxy.size.height).id(item.id)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }.accessibilityLabel("关闭")
                Spacer()
                Text("\(indexLabel) / \(items.count)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
            }.padding(.horizontal, 18).padding(.top, 12)
            Spacer()
        }
    }

    private var indexLabel: Int { (items.firstIndex { $0.id == currentID } ?? 0) + 1 }

    private func advance(_ delta: Int) {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return }
        let next = min(max(0, index + delta), items.count - 1)
        if next == index {
            if delta > 0, queue == nil, !pagination.exhausted {
                pendingAdvanceFrom = currentID
                requestRefill()
            }
            return
        }
        pendingAdvanceFrom = nil
        withAnimation(.easeInOut(duration: 0.2)) { self.currentID = items[next].id }
    }

    private func appendPage() async throws {
        guard pagination.begin() else { return }
        var sample = filter
        sample.sort = .seed
        sample.seed = pagination.seed
        do {
            let page = try await api.items(sample, offset: pagination.offset, limit: 60)
            try Task.checkCancellation()
            let total = page.total ?? (pagination.offset + page.items.count + (page.items.count == 60 ? 1 : 0))
            pagination.finish(received: page.items.count, total: total)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter {
                Self.playable($0) && !known.contains($0.id)
            })
        } catch {
            pagination.fail()
            throw error
        }
    }

    private static func playable(_ item: PeachItem) -> Bool {
        (item.medium ?? "video") == "video" && item.location != "online"
            && (item.duration ?? 0) > 0 && (item.cost ?? "free") != "metered"
    }

    private func requestRefill() {
        guard !pagination.loading else { return }
        refillTask = Task { await refillIfNeeded() }
    }

    private func refillIfNeeded() async {
        guard !loading, queue == nil, !pagination.loading,
              let currentID, let index = items.firstIndex(where: { $0.id == currentID }),
              index >= items.count - 3 else { return }
        loadMoreError = nil
        do {
            while index >= items.count - 3, !pagination.exhausted {
                try await appendPage()
            }
            if pendingAdvanceFrom == self.currentID, let nextIndex = items.firstIndex(where: { $0.id == pendingAdvanceFrom }),
               nextIndex + 1 < items.count {
                pendingAdvanceFrom = nil
                withAnimation(.easeInOut(duration: 0.2)) { self.currentID = items[nextIndex + 1].id }
            }
        } catch is CancellationError {
            return
        } catch let failure {
            loadMoreError = failure.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false; requestRefill() }
        if let queue, !queue.isEmpty {
            items = queue
            currentID = queue.contains(where: { $0.id == startID }) ? startID : queue.first?.id
            return
        }
        do {
            repeat { try await appendPage() } while items.isEmpty && !pagination.exhausted
            if let startID, !items.contains(where: { $0.id == startID }) {
                let start = try await api.item(id: startID)
                if Self.playable(start) { items.insert(start, at: 0) }
            }
            guard !items.isEmpty else { error = "当前筛选下没有可直接播放的内容"; return }
            currentID = items.contains(where: { $0.id == startID }) ? startID : items.first?.id
        } catch is CancellationError {
            return
        } catch let failure {
            error = failure.localizedDescription
        }
    }

    private func feedback(_ kind: String, id: Int, count: Int) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = items[index].replacing(oCount: count)
        }
        switch kind {
        case "o":
            showToast("已记一次高潮 · \(count)", undo: {
                Task {
                    do {
                        let result = try await api.feedback(id: id, kind: "o-undo")
                        let fresh = try await api.item(id: id)
                        if let index = items.firstIndex(where: { $0.id == id }) {
                            items[index] = fresh.replacing(oCount: result.oCount ?? fresh.oCount)
                        }
                        showToast("已撤销")
                    } catch let failure {
                        if let fresh = try? await api.item(id: id), let index = items.firstIndex(where: { $0.id == id }) {
                            items[index] = fresh
                        }
                        showToast("撤销结果未确认：\(failure.localizedDescription)")
                    }
                }
            })
        case "seen": showToast("已更新看过状态")
        case "dislike": showToast("已更新不合口味状态")
        default: showToast(kind)
        }
    }

    private func showToast(_ message: String, undo: (() -> Void)? = nil) {
        let identifier = UUID()
        toastID = identifier
        toast = message
        undoAction = undo.map { SingleUseAction($0) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastID == identifier { toast = nil; undoAction = nil }
        }
    }
}

private struct ImmersivePage: View {
    let api: PeachAPI
    let item: PeachItem
    let isActive: Bool
    @Binding var controlsVisible: Bool
    let onEnded: () -> Void
    let onOpenDetail: () -> Void
    let onFeedback: (String, Int) -> Void
    let onAdvance: (Int) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: PlaybackController
    @StateObject private var presentation: PlayerPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false
    @State private var expandedMode = PlayerDisplayMode.fullscreen
    @State private var detail: PeachItem?
    @State private var busy = false
    @State private var localCount: Int?
    @State private var seekOrigin = 0.0
    @State private var gestureFeedback: String?
    @State private var feedbackID = UUID()

    init(api: PeachAPI, item: PeachItem, isActive: Bool, controlsVisible: Binding<Bool>,
         onEnded: @escaping () -> Void, onOpenDetail: @escaping () -> Void,
         onFeedback: @escaping (String, Int) -> Void, onAdvance: @escaping (Int) -> Void) {
        self.api = api; self.item = item; self.isActive = isActive
        _controlsVisible = controlsVisible
        self.onEnded = onEnded; self.onOpenDetail = onOpenDetail
        self.onFeedback = onFeedback; self.onAdvance = onAdvance
        let controller = PlaybackController(api: api, item: item)
        _controller = StateObject(wrappedValue: controller)
        _presentation = StateObject(wrappedValue: PlayerPresentation(api: api, item: item, controller: controller))
    }

    private var current: PeachItem { detail ?? item }
    private var authorLine: String {
        let names = current.performers.prefix(3).joined(separator: "、")
        if !names.isEmpty { return names + (current.performers.count > 3 ? " 等 \(current.performers.count) 人" : "") }
        return current.creator ?? current.studio ?? "未归属"
    }
    private var playbackActive: Bool { isActive && scenePhase == .active && !expanded }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if controller.player != nil, !expanded {
                    SessionVideoSurface(session: presentation).ignoresSafeArea()
                } else if !isActive {
                    RemoteImage(url: api.coverURL(code: current.coverKey.isEmpty ? current.displayNumber : current.coverKey))
                        .blur(radius: 12).overlay(Color.black.opacity(0.55))
                }
                if playbackActive {
                    MediaGestureOverlay(
                        onTap: { controlsVisible.toggle() },
                        onDoubleTap: { showGesture(controller.doubleTap(at: Double($0))) },
                        onSeekChanged: { dx in
                            controller.previewSeek(seekOrigin + dx / max(geometry.size.width, 1) * controller.duration)
                        },
                        onSeekEnded: { dx in
                            controller.endScrubbing(at: seekOrigin + dx / max(geometry.size.width, 1) * controller.duration)
                        },
                        onSeekBegan: { seekOrigin = controller.currentTime; controller.beginScrubbing() },
                        onSeekCancelled: { controller.cancelScrubbing() },
                        onHoldBegan: { controller.beginBoost() }, onHoldEnded: { controller.endBoost() }
                    )
                    .accessibilityElement().accessibilityLabel("视频画面")
                    .accessibilityAction(named: "播放或暂停") { controller.togglePlayback() }
                    .accessibilityAction(named: "前进 10 秒") { controller.skip(by: 10) }
                    .accessibilityAction(named: "后退 10 秒") { controller.skip(by: -10) }
                }
                if playbackActive, case .preparing = controller.phase {
                    ProgressView("加载中").tint(PeachTheme.coral).foregroundStyle(.white)
                        .allowsHitTesting(false)
                }
                if isActive, case .failed(let message) = controller.phase {
                    VStack(spacing: 12) {
                        Text(message).font(.footnote).foregroundStyle(.white.opacity(0.7))
                        Button("跳过") { onAdvance(1) }.buttonStyle(.borderedProminent).tint(PeachTheme.coral)
                    }.padding(30)
                }
                if controller.isBoosting {
                    Text("2×").font(.headline.monospacedDigit()).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.6), in: Capsule()).allowsHitTesting(false)
                }
                if let gestureFeedback {
                    Text(gestureFeedback).font(.headline).foregroundStyle(.white)
                        .padding(16).background(.black.opacity(0.5), in: Capsule()).allowsHitTesting(false)
                }
                if controlsVisible || controller.seekPreview != nil || controller.isScrubbing {
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: onOpenDetail) {
                                    Text(current.title).font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(2)
                                }.buttonStyle(.plain)
                                Text(authorLine)
                                    .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(spacing: 14) {
                                Button { controller.setMuted(!controller.isMuted) } label: {
                                    Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .frame(width: 44, height: 36).foregroundStyle(.white)
                                }.accessibilityLabel(controller.isMuted ? "打开声音" : "静音")
                                feedbackButton(kind: "dislike", icon: "hand.thumbsdown", active: current.feedback == "dislike", count: nil)
                                feedbackButton(kind: "seen", icon: "eye", active: current.feedback == "seen", count: nil)
                                feedbackButton(kind: "o", icon: "heart", active: false, count: localCount ?? current.oCount)
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 12)
                        if isActive {
                            HStack(spacing: 12) {
                                Spacer()
                                modeButton("rectangle.expand.vertical", "影院模式") { expandedMode = .theater; expanded = true }
                                modeButton("pip.enter", "小窗") { presentation.startPiP() }
                                modeButton("arrow.up.left.and.arrow.down.right", "全屏") { expandedMode = .fullscreen; expanded = true }
                            }.padding(.horizontal, 16)
                            PlaybackSeekBar(controller: controller, api: api, item: current)
                                .padding(.horizontal, 20).padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .task(id: playbackActive) {
            guard playbackActive else { return }
            presentation.appear()
            presentation.onPiPStarted = { dismiss() }
            controller.onEnded = onEnded
            await controller.activate()
        }
        .onChange(of: playbackActive) { _, active in if !expanded { controller.setActive(active) } }
        .onChange(of: controller.isPlaying) { _, playing in
            if playing { controlsVisible = false }
        }
        .onChange(of: item.oCount) { _, count in localCount = count }
        .onDisappear { if !expanded { presentation.disappear() } }
        .fullScreenCover(isPresented: $expanded, onDismiss: {
            if controller.isPiPActive { dismiss(); return }
            presentation.appear(); presentation.onPiPStarted = { dismiss() }
            if isActive { Task { await controller.activate() } }
        }) { PlayerView(session: presentation, preserveOnExit: true, initialMode: expandedMode) }
        .onChange(of: presentation.message) { _, message in if let message { showGesture(message) } }
        .task(id: item.id) {
            if let fresh = try? await api.item(id: item.id), !Task.isCancelled { detail = fresh }
        }
    }

    private func modeButton(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).frame(width: 44, height: 44).foregroundStyle(.white) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func showGesture(_ message: String) {
        let identifier = UUID(); feedbackID = identifier; gestureFeedback = message
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if feedbackID == identifier { gestureFeedback = nil }
        }
    }

    private func feedbackButton(kind: String, icon: String, active: Bool, count: Int?) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    let result = try await api.feedback(id: item.id, kind: kind)
                    if let fresh = try? await api.item(id: item.id) { detail = fresh }
                    if kind == "o", let count = result.oCount { localCount = count }
                    onFeedback(kind, result.oCount ?? current.oCount)
                } catch let failure {
                    onFeedback("写入失败：\(failure.localizedDescription)", current.oCount)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? PeachTheme.coral : .white)
                    .frame(width: 46, height: 46).background(.black.opacity(0.42), in: Circle())
                if let count {
                    Text("高潮 \(count)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityLabel(kind == "o" ? "记一次高潮" : kind == "seen" ? "看过" : "不合口味")
    }
}
