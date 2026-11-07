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

struct PreviewFilmstrip: View {
    private enum FrameState {
        case image(UIImage)
        case failed(String)
    }

    private struct FrameRequest: Equatable {
        let seconds: Double
        let key: MediaCacheKey
    }

    private struct LoadID: Equatable {
        let frames: [FrameRequest]
        let retry: Int
    }

    let api: PeachAPI
    let item: PeachItem
    let playbackPresented: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var metadata: TimelineMetadata?
    @State private var error: String?
    @State private var selected = 0
    @State private var expanded = false
    @State private var reload = 0
    @State private var frameRetry = 0
    @State private var visibleIndices: Set<Int> = []
    @State private var frames: [MediaCacheKey: FrameState] = [:]

    private var stripRequests: [FrameRequest] {
        guard scenePhase == .active, !playbackPresented, !expanded, let metadata else { return [] }
        let count = min(30, metadata.frames ?? 0)
        guard count > 0 else { return [] }
        let visible = visibleIndices.filter { $0 < count }.sorted()
        let indices: [Int]
        if let last = visible.last, last > 1 {
            indices = visible + Array((last + 1)..<min(count, last + 3))
        } else {
            // Keep the same first batch when the user scrolls down to the strip.
            indices = Array(0..<min(4, count))
        }
        return indices.map { request(at: metadata.sampleTime(at: $0)) }
    }

    var body: some View {
        let requests = stripRequests
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("预览图").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if (metadata?.frames ?? 0) > 0 {
                    Text("原图").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let metadata, let count = metadata.frames, count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(0..<min(30, count), id: \.self) { index in
                            stripFrame(request(at: metadata.sampleTime(at: index)), index: index)
                        }
                    }
                }
                .frame(height: 186)
            } else if let error {
                HStack { Text(error).font(.footnote); Button("重试") { reload += 1 } }.foregroundStyle(.secondary)
            } else { ProgressView().tint(PeachTheme.coral) }
        }
        .task(id: LoadID(frames: requests, retry: frameRetry)) {
            await loadOriginals(requests)
        }
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

    private func stripFrame(_ request: FrameRequest, index: Int) -> some View {
        Button {
            if case .image = frames[request.key] {
                selected = index
                expanded = true
            } else {
                retry(request)
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    PeachTheme.surface
                    switch frames[request.key] {
                    case .image(let image): Image(uiImage: image).resizable().scaledToFit()
                    case .failed(let error):
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                            .accessibilityLabel("原图读取失败，点按重试").accessibilityHint(error)
                    case nil: ProgressView().tint(.white)
                    }
                }
                .frame(width: 288, height: 162).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(MediaClock.text(request.seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(frames[request.key] == nil)
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .scrollView)
            let viewport = CGRect(origin: .zero, size: proxy.bounds(of: .scrollView)?.size ?? .zero)
            return frame.intersection(viewport).width > 0
        } action: { visible in
            if visible { visibleIndices.insert(index) }
            else { visibleIndices.remove(index) }
        }
        .onDisappear { visibleIndices.remove(index) }
    }

    private func gallery(_ metadata: TimelineMetadata) -> some View {
        let requests = scenePhase == .active ? [request(at: metadata.sampleTime(at: selected))] : []
        return ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selected) {
                ForEach(0..<min(30, metadata.frames ?? 0), id: \.self) { index in
                    slide(metadata, index: index).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            Button { expanded = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .foregroundStyle(.white).padding().accessibilityLabel("关闭预览图")
        }
        .task(id: LoadID(frames: requests, retry: frameRetry)) {
            await loadOriginals(requests)
        }
    }

    private func slide(_ metadata: TimelineMetadata, index: Int) -> some View {
        let request = request(at: metadata.sampleTime(at: index))
        let state = frames[request.key]
        return VStack {
            switch state {
            case .image(let image):
                ZoomableFrame(image: image)
            case .failed(let error):
                Button("原图读取失败，重试") { retry(request) }.accessibilityHint(error)
            case nil:
                ProgressView("正在加载原图…").controlSize(.small).tint(.white)
            }
            Text("\(index + 1) / \(min(30, metadata.frames ?? 0)) · \(MediaClock.text(request.seconds))")
                .font(.caption.monospacedDigit()).foregroundStyle(.white)
            if case .image(let image) = state, let pixels = image.cgImage {
                Text("\(pixels.width) × \(pixels.height)")
            }
        }
        .padding(.vertical, 60)
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
    private func request(at seconds: Double) -> FrameRequest {
        let key = MediaCacheKey(url: api.baseURL, kind: .originalFrame, resource: "\(item.mediaCacheIdentity):\(seconds)")
        return FrameRequest(seconds: seconds, key: key)
    }

    private func retry(_ request: FrameRequest) {
        frames[request.key] = nil
        frameRetry += 1
    }

    private func loadOriginals(_ requests: [FrameRequest]) async {
        guard !requests.isEmpty, !Task.isCancelled else { return }
        // Retain only the current window; older originals live in the disk cache.
        let keys = Set(requests.map(\.key))
        frames = frames.filter { keys.contains($0.key) }
        var misses: [FrameRequest] = []
        for request in requests where frames[request.key] == nil {
            let data = await MediaDiskCache.shared.read(request.key)
            guard !Task.isCancelled else { return }
            if let data, let image = UIImage(data: data) {
                frames[request.key] = .image(image)
            } else {
                misses.append(request)
            }
        }
        guard !misses.isEmpty, !Task.isCancelled else { return }

        let session = UUID().uuidString
        defer { api.cancelStream(sessionID: session) }
        do {
            let plan = try await api.streamPlan(id: item.id, sessionID: session)
            try Task.checkCancellation()
            let url = try api.playbackURL(plan: plan, id: item.id, sessionID: session)
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPCookiesKey": cookies])
            await withTaskGroup(of: Void.self) { writes in
                var writing = false
                for request in misses {
                    do {
                        let frame = try await OriginalVideoFrame.capture(asset: asset, seconds: request.seconds,
                                                                         hls: plan.protocolName == "hls")
                        try Task.checkCancellation()
                        frames[request.key] = .image(UIImage(cgImage: frame))
                        // Encode at most one PNG while the next frame is being decoded.
                        if writing { _ = await writes.next() }
                        guard !Task.isCancelled else { return }
                        writes.addTask(priority: .utility) {
                            guard !Task.isCancelled, let data = try? OriginalVideoFrame.png(frame), !Task.isCancelled else { return }
                            await MediaDiskCache.shared.store(data, for: request.key)
                        }
                        writing = true
                    } catch {
                        guard !Task.isCancelled else { return }
                        frames[request.key] = .failed(error.localizedDescription)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            for request in misses {
                frames[request.key] = .failed(error.localizedDescription)
            }
        }
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
