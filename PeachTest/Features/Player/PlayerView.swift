import AVKit
import SwiftUI

@MainActor
final class PlayerModel: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var buffered = 0.0
    @Published private(set) var formatNote: String?
    @Published private(set) var isScrubbing = false

    let sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let api: PeachAPI
    private let item: PeachItem
    private var timeObserver: Any?
    private var itemStatus: NSKeyValueObservation?
    private var timeControlStatus: NSKeyValueObservation?
    private var playbackLikelyToKeepUp: NSKeyValueObservation?
    private var loadedTimeRanges: NSKeyValueObservation?
    private var itemError: NSKeyValueObservation?
    private var stallTask: Task<Void, Never>?
    private var startedAt: Date?

    init(api: PeachAPI, item: PeachItem) {
        self.api = api
        self.item = item
    }

    func start() async {
        do {
            let plan = try await api.streamPlan(id: item.id, sessionID: sessionID)
            let source: URL
            if let raw = plan.src, !raw.isEmpty {
                source = api.mediaURL(raw)
            } else {
                source = api.streamURL(id: item.id, sessionID: sessionID)
            }
            formatNote = plan.protocolName == "hls" ? "HLS 自适应分片" : "原始 MP4 流"
            let cookies = HTTPCookieStorage.shared.cookies(for: source) ?? []
            let asset = AVURLAsset(url: source, options: [
                "AVURLAssetHTTPCookiesKey": cookies
            ])
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 8
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            player.allowsExternalPlayback = true
            self.player = player
            observe(player, item: playerItem)
            startedAt = Date()
            player.play()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing || player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func seek(to time: Double) {
        guard let player else { return }
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func beginScrubbing() {
        isScrubbing = true
        player?.pause()
    }

    func endScrubbing() {
        isScrubbing = false
        player?.play()
    }

    func stop() {
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        api.cancelStream(sessionID: sessionID)
        player = nil
    }

    private func observe(_ player: AVPlayer, item: AVPlayerItem) {
        itemStatus = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    if self.phase == .preparing { self.phase = .ready }
                case .failed:
                    self.phase = .failed(Self.describe(item.error))
                default: break
                }
            }
        }
        itemError = item.observe(\.error, options: [.new]) { [weak self] item, _ in
            guard let error = item.error else { return }
            Task { @MainActor in self?.phase = .failed(Self.describe(error)) }
        }
        timeControlStatus = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in self?.isPlaying = player.timeControlStatus == .playing }
        }
        playbackLikelyToKeepUp = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            Task { @MainActor in
                if let self, case .preparing = self.phase, item.status == .readyToPlay { self.phase = .ready }
            }
        }
        loadedTimeRanges = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let range = item.loadedTimeRanges.last?.timeRangeValue else { return }
            let seconds = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
            Task { @MainActor in self?.buffered = seconds }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in self?.currentTime = seconds }
        }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled, self.phase == .preparing else { return }
            self.phase = .failed("播放源长时间没有响应。请检查手机与 Peach 是否在同一 Wi-Fi，或换一个 MP4 作品验证。")
        }
    }

    private func removeObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemStatus = nil
        timeControlStatus = nil
        playbackLikelyToKeepUp = nil
        loadedTimeRanges = nil
        itemError = nil
        stallTask?.cancel()
        stallTask = nil
    }

    private static func describe(_ error: Error?) -> String {
        guard let error else { return "播放器无法打开这个视频。" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "无法连接 Peach。请确认手机在同一 Wi-Fi，且服务地址可访问。"
            case NSURLErrorTimedOut:
                return "连接 Peach 超时。请检查网络后重试。"
            default:
                break
            }
        }
        if ns.domain == AVFoundationErrorDomain {
            return "这个文件当前无法在 iPhone 上播放（\(ns.code)）。可先换一个 MP4 作品验证。"
        }
        return ns.localizedDescription
    }
}

struct PlayerView: View {
    let item: PeachItem
    let api: PeachAPI
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlayerModel
    @State private var scrubValue = 0.0
    @State private var scrubbing = false
    @State private var controlsVisible = true

    init(item: PeachItem, api: PeachAPI) {
        self.item = item
        self.api = api
        _model = StateObject(wrappedValue: PlayerModel(api: api, item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = model.player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() } }
            }

            switch model.phase {
            case .preparing:
                loading
            case .failed(let message):
                failure(message)
            case .ready:
                EmptyView()
            }

            if controlsVisible {
                chrome
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.currentTime) { _, value in
            if !scrubbing { scrubValue = value }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(PeachTheme.coral).scaleEffect(1.2)
            Text("正在连接播放源…").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(PeachTheme.coral)
            Text("无法播放")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(PeachTheme.coral)
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("关闭播放")
                Spacer()
                VStack(spacing: 2) {
                    Text(item.displayNumber.isEmpty ? "Peach" : item.displayNumber)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                    if let note = model.formatNote {
                        Text(note).font(.system(size: 9)).foregroundStyle(.white.opacity(0.38))
                    }
                }
                Spacer()
                Color.clear.frame(width: 42, height: 42)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    Button { model.seek(to: model.currentTime - 15) } label: {
                        Image(systemName: "gobackward.15").font(.system(size: 24, weight: .medium))
                    }
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .frame(width: 64, height: 64)
                            .background(PeachTheme.coral, in: Circle())
                            .foregroundStyle(.black)
                    }
                    Button { model.seek(to: model.currentTime + 15) } label: {
                        Image(systemName: "goforward.15").font(.system(size: 24, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Text(clock(scrubbing ? scrubValue : model.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: $scrubValue, in: 0...max(model.duration, 1)) { editing in
                        scrubbing = editing
                        if editing { model.beginScrubbing() } else { model.seek(to: scrubValue); model.endScrubbing() }
                    }
                    .tint(PeachTheme.coral)
                    .accessibilityLabel("播放进度")
                    Text(clock(model.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 50, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
