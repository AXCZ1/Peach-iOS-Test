import AVFoundation
import SwiftUI
import UIKit

struct PreviewBoundsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct DwellVideoPreview: View {
    @StateObject private var controller: PlaybackController
    @State private var hasFrame = false
    @State private var startedPlaying = false
    init(item: PeachItem, api: PeachAPI) {
        _controller = StateObject(wrappedValue: PlaybackController(api: api, item: item, previewOnly: true))
    }
    var body: some View {
        ZStack {
            if let player = controller.player, controller.phase == .ready {
                DwellVideoSurface(player: player, hasFrame: $hasFrame)
                    .background(.black)
                    .opacity(hasFrame && startedPlaying ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .task { controller.setMuted(true); await controller.activate() }
        .onChange(of: controller.isPlaying, initial: true) { _, playing in
            if playing { startedPlaying = true }
        }
        .onDisappear { controller.stop() }
    }
}

private struct DwellVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    @Binding var hasFrame: Bool

    func makeCoordinator() -> Coordinator { Coordinator(hasFrame: $hasFrame) }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        context.coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak coordinator = context.coordinator] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor in coordinator?.hasFrame.wrappedValue = ready }
        }
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {}

    @MainActor final class Coordinator {
        let hasFrame: Binding<Bool>
        var observation: NSKeyValueObservation?
        init(hasFrame: Binding<Bool>) { self.hasFrame = hasFrame }
    }
}

struct TimelineFrameView: View {
    let api: PeachAPI
    let item: PeachItem
    let metadata: TimelineMetadata
    let index: Int
    var onLoad: ((UIImage) -> Void)?
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            PeachTheme.surface
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView().tint(.white) }
        }
        .task(id: "\(item.id):\(metadata.madeAt ?? 0):\(index)") {
            guard let tile = metadata.tile(atIndex: index) else { failed = true; return }
            let sheet = await PeachImageCache.shared.image(for: api.timelineURL(id: item.id, sheet: tile.sheet, source: tile.source, madeAt: metadata.madeAt))
            guard !Task.isCancelled else { return }
            image = sheet?.cropped(to: tile.region); failed = image == nil
            if let image { onLoad?(image) }
        }
    }
}

struct PreviewFilmstrip: View {
    let api: PeachAPI
    let item: PeachItem
    let playbackPresented: Bool
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var original = PreviewOriginalLoader()
    @State private var metadata: TimelineMetadata?
    @State private var error: String?
    @State private var selected = 0
    @State private var expanded = false
    @State private var reload = 0
    @State private var leadingIndex: Int?
    @State private var visible = false
    @State private var thumbnails: [Int: UIImage] = [:]

    private var requestedTime: Double? {
        guard scenePhase == .active, !playbackPresented,
              let metadata, let count = metadata.frames, count > 0 else { return nil }
        let index = expanded ? selected : leadingIndex ?? 0
        guard index < count, expanded || (visible && thumbnails[index] != nil) else { return nil }
        return metadata.sampleTime(at: index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("预览图").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if (metadata?.frames ?? 0) > 0 {
                    Text("点开看原画").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let metadata, let count = metadata.frames, count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(0..<min(30, count), id: \.self) { index in
                            Button {
                                selected = index
                                original.load(api: api, item: item, seconds: metadata.sampleTime(at: index))
                                expanded = true
                            } label: {
                                VStack(spacing: 5) {
                                    TimelineFrameView(api: api, item: item, metadata: metadata, index: index) {
                                        thumbnails[index] = $0
                                    }
                                    .frame(width: 288, height: 162).clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(MediaClock.text(metadata.sampleTime(at: index)))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).disabled(thumbnails[index] == nil)
                        }
                    }.scrollTargetLayout()
                }
                .scrollPosition(id: $leadingIndex, anchor: .leading)
                .frame(height: 186)
            } else if let error {
                HStack { Text(error).font(.footnote); Button("重试") { reload += 1 } }.foregroundStyle(.secondary)
            } else { ProgressView().tint(PeachTheme.coral) }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .scrollView)
            let viewport = CGRect(origin: .zero, size: proxy.bounds(of: .scrollView)?.size ?? .zero)
            return frame.height > 0 && frame.intersection(viewport).height >= frame.height * 0.5
        } action: { visible = $0 }
        .onChange(of: requestedTime, initial: true) { _, seconds in
            if let seconds { original.load(api: api, item: item, seconds: seconds, preload: !expanded) }
            else { original.cancel() }
        }
        .onDisappear { if !expanded { original.cancel() } }
        .task(id: "\(item.id):\(reload)") {
            error = nil
            do {
                metadata = try await api.timeline(id: item.id)
                if (metadata?.frames ?? 0) == 0 { error = "预览图尚未生成" }
            } catch { self.error = "预览图读取失败" }
        }
        .fullScreenCover(isPresented: $expanded) {
            if let metadata { gallery(metadata) }
        }
    }

    private func gallery(_ metadata: TimelineMetadata) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selected) {
                ForEach(0..<min(30, metadata.frames ?? 0), id: \.self) { index in
                    slide(metadata, index: index).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            Button { expanded = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .foregroundStyle(.white).padding().accessibilityLabel("关闭预览图")
        }
    }

    private func slide(_ metadata: TimelineMetadata, index: Int) -> some View {
        let seconds = metadata.sampleTime(at: index)
        let active = index == selected && original.seconds == seconds
        let frame = active ? original.image : nil
        return VStack {
            if let image = frame ?? thumbnails[index] {
                ZoomableFrame(image: image)
            } else {
                TimelineFrameView(api: api, item: item, metadata: metadata, index: index) { thumbnails[index] = $0 }
            }
            Text("\(index + 1) / \(min(30, metadata.frames ?? 0)) · \(MediaClock.text(seconds))")
                .font(.caption.monospacedDigit()).foregroundStyle(.white)
            if index == selected {
                if let image = frame?.cgImage {
                    Text("\(image.width) × \(image.height)")
                } else if active, let error = original.error {
                    Button("原画读取失败，重试") {
                        original.load(api: api, item: item, seconds: seconds, retry: true)
                    }.accessibilityHint(error)
                } else {
                    ProgressView("正在加载原画…").controlSize(.small).tint(.white)
                }
            }
        }
        .padding(.vertical, 60)
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
}

@MainActor private final class PreviewOriginalLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var error: String?
    private(set) var seconds: Double?
    private var key: MediaCacheKey?
    private var request: Task<Void, Never>?

    func load(api: PeachAPI, item: PeachItem, seconds: Double, preload: Bool = false, retry: Bool = false) {
        let key = MediaCacheKey(url: api.baseURL, kind: .originalFrame, resource: "\(item.mediaCacheIdentity):\(seconds)")
        guard self.key != key || retry || (!preload && error != nil) else { return }
        cancel()
        self.key = key
        self.seconds = seconds
        request = Task { [weak self] in
            do {
                if let data = await MediaDiskCache.shared.read(key), let cached = UIImage(data: data) {
                    if !Task.isCancelled { self?.image = cached }
                    return
                }
                if preload { try await Task.sleep(for: .milliseconds(350)) }
                try Task.checkCancellation()
                let session = UUID().uuidString
                defer { api.cancelStream(sessionID: session) }
                let plan = try await api.streamPlan(id: item.id, sessionID: session)
                let url = try api.playbackURL(plan: plan, id: item.id, sessionID: session)
                let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPCookiesKey": cookies])
                let frame = try await OriginalVideoFrame.capture(asset: asset, seconds: seconds, hls: plan.protocolName == "hls")
                try Task.checkCancellation()
                self?.image = UIImage(cgImage: frame)
                let data = try await Task.detached(priority: .utility) { try OriginalVideoFrame.png(frame) }.value
                if !Task.isCancelled { await MediaDiskCache.shared.store(data, for: key) }
            } catch {
                if !Task.isCancelled, self?.image == nil { self?.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        request?.cancel()
        request = nil
        key = nil
        seconds = nil
        image = nil
        error = nil
    }
}

private struct ZoomableFrame: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = FrameScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        let view = context.coordinator.imageView
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        return scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {
        if context.coordinator.imageView.image !== image { context.coordinator.imageView.image = image }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }

    private final class FrameScrollView: UIScrollView {
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGestureRecognizer, zoomScale <= minimumZoomScale { return false }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
    }
}
