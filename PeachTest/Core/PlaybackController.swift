import AVFoundation
import Foundation

/// Player state shared by the detail stage, the wall and immersive mode.
///
/// It mirrors the 0.52.0 web player: one stream session per mount, a resume
/// position from local memory (falling back to the server's `leave_ratio`),
/// `/api/play` once at first start, and `/api/activity` every ten seconds plus
/// on pause, seek, end and teardown. Only real elapsed playback is accumulated.
@MainActor
final class PlaybackController: ObservableObject {
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
    @Published private(set) var isMuted = false
    @Published private(set) var isScrubbing = false
    @Published private(set) var seekPreview: Double? = nil

    let item: PeachItem
    private(set) var sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var onEnded: (() -> Void)?

    private let api: PeachAPI
    private var timeObserver: Any?
    private var itemStatus: NSKeyValueObservation?
    private var timeControlStatus: NSKeyValueObservation?
    private var playbackLikelyToKeepUp: NSKeyValueObservation?
    private var loadedTimeRanges: NSKeyValueObservation?
    private var itemError: NSKeyValueObservation?
    private var stallTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var started = false
    private var stopped = false
    private var markedPlayed = false
    private var watchSeconds = 0.0
    private var seeks = 0
    private var lastTick: Date?
    private var lastActivityAt = Date.distantPast
    private var pendingResume: Double?
    private var endObserver: NSObjectProtocol?
    private var didEnd = false

    init(api: PeachAPI, item: PeachItem) {
        self.api = api
        self.item = item
    }

    func start() async {
        if stopped {
            // A page recycled by the immersive pager can be scrolled back into
            // view after teardown. Reopen a fresh stream session instead of
            // leaving a dead player behind.
            stopped = false
            started = false
            sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            phase = .preparing
            player = nil
            didEnd = false
            markedPlayed = false
            lastActivityAt = .distantPast
        }
        guard !started else { return }
        started = true
        phase = .preparing
        if let local = PlayerMemory.shared.position(for: item.id) {
            pendingResume = local
        } else if item.resumeTime > 0 {
            pendingResume = item.resumeTime
        }
        do {
            let plan = try await api.streamPlan(id: item.id, sessionID: sessionID)
            guard !stopped else { return }
            let source: URL
            if let raw = plan.src, !raw.isEmpty {
                source = api.mediaURL(raw)
            } else {
                source = api.streamURL(id: item.id, sessionID: sessionID)
            }
            formatNote = plan.protocolName == "hls" ? "HLS 自适应分片" : "原始 MP4 流"
            let cookies = HTTPCookieStorage.shared.cookies(for: source) ?? []
            let asset = AVURLAsset(url: source, options: ["AVURLAssetHTTPCookiesKey": cookies])
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 8
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            player.allowsExternalPlayback = true
            self.player = player
            observe(player, item: playerItem)
            player.isMuted = isMuted
            player.play()
            startTicker()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing || player.rate > 0 {
            pause()
        } else {
            resume()
        }
    }

    /// Called when an immersive page scrolls back into view. A page that has
    /// already prepared its player resumes; a fresh one starts its session.
    func activate() async {
        if started, !stopped {
            if phase == .ready { resume() }
            return
        }
        // Reopening after teardown must build a new AVPlayerItem and observe it
        // again; `start()` resets the dead session first.
        await start()
    }

    func pause() {
        player?.pause()
        flushActivity()
    }

    func resume() {
        lastTick = Date()
        player?.play()
    }

    func seek(to time: Double) {
        guard let player else { return }
        seekPreview = nil
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        seeks += 1
        PlayerMemory.shared.save(clamped, for: item.id)
        flushActivity()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func beginScrubbing() {
        isScrubbing = true
        player?.pause()
    }

    /// Horizontal drag preview: show where a release would land without
    /// interrupting the current picture while the finger is still moving.
    func previewSeek(_ time: Double) {
        seekPreview = max(0, min(time, duration > 0 ? duration : time))
    }

    func clearPreview() {
        seekPreview = nil
    }

    func endScrubbing(at time: Double) {
        isScrubbing = false
        seek(to: time)
        player?.play()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
    }

    func stop() {
        guard !stopped else { return }
        if let player, !didEnd {
            let position = player.currentTime().seconds
            if position.isFinite, position > 1 { PlayerMemory.shared.save(position, for: item.id) }
        }
        flushActivity(force: true)
        stopped = true
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        api.cancelStream(sessionID: sessionID)
        player = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard !stopped, let player else { return }
        let playing = player.timeControlStatus == .playing
        if playing {
            let now = Date()
            if let lastTick {
                let delta = now.timeIntervalSince(lastTick)
                if delta > 0, delta < 2 { watchSeconds += delta }
            }
            lastTick = now
            if Date().timeIntervalSince(lastActivityAt) >= 10 {
                flushActivity()
            }
        } else {
            lastTick = nil
        }
    }

    private func flushActivity(force: Bool = false, ended: Bool = false) {
        guard let player else { return }
        guard !stopped || force else { return }
        let position = player.currentTime().seconds
        let total = duration > 0 ? duration : (item.duration ?? 0)
        let delta = watchSeconds
        let seekCount = seeks
        guard ended || delta >= 1 || seekCount > 0 else { return }
        watchSeconds = 0
        seeks = 0
        lastActivityAt = Date()
        guard position.isFinite, total > 0 else { return }
        Task { [api, item] in
            try? await api.activity(id: item.id, position: position, duration: total,
                                    delta: delta, ended: ended, seeks: seekCount)
        }
        if !ended { PlayerMemory.shared.save(position, for: item.id) }
    }

    private func observe(_ player: AVPlayer, item playerItem: AVPlayerItem) {
        itemStatus = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : (self.item.duration ?? 0)
                    if self.phase == .preparing { self.phase = .ready }
                    self.restorePositionIfNeeded(player)
                    if !self.markedPlayed {
                        self.markedPlayed = true
                        Task { try? await self.api.markPlayed(id: self.item.id) }
                    }
                case .failed:
                    self.phase = .failed(Self.describe(item.error))
                default: break
                }
            }
        }
        itemError = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            guard let error = item.error else { return }
            Task { @MainActor in self?.phase = .failed(Self.describe(error)) }
        }
        timeControlStatus = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in self?.isPlaying = player.timeControlStatus == .playing }
        }
        playbackLikelyToKeepUp = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            Task { @MainActor in
                if let self, case .preparing = self.phase, item.status == .readyToPlay { self.phase = .ready }
            }
        }
        loadedTimeRanges = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let range = item.loadedTimeRanges.last?.timeRangeValue else { return }
            let seconds = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
            Task { @MainActor in self?.buffered = seconds }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in self?.currentTime = seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.didEnd = true
                PlayerMemory.shared.clear(self.item.id)
                self.flushActivity(force: true, ended: true)
                self.onEnded?()
            }
        }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled, self.phase == .preparing else { return }
            self.phase = .failed("播放源长时间没有响应。请检查手机与 Peach 是否在同一 Wi-Fi，或换一个 MP4 作品验证。")
        }
    }

    private func restorePositionIfNeeded(_ player: AVPlayer) {
        guard let target = pendingResume else { return }
        pendingResume = nil
        guard target > 5, duration > 0, target < duration - 10 else { return }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
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
        ticker?.cancel()
        ticker = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
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
            default: break
            }
        }
        if ns.domain == AVFoundationErrorDomain {
            return "这个文件当前无法在 iPhone 上播放（\(ns.code)）。可先换一个 MP4 作品验证。"
        }
        return ns.localizedDescription
    }
}

/// Local resume memory, the same role as `peach.playback-position.v1` in the
/// web client. Cleared at the end so a finished item starts from zero.
final class PlayerMemory: @unchecked Sendable {
    static let shared = PlayerMemory()
    private let defaults = UserDefaults.standard

    private func key(_ id: Int) -> String { "peach.playback.position.\(id)" }

    func position(for id: Int) -> Double? {
        let value = defaults.double(forKey: key(id))
        return value > 0 ? value : nil
    }

    func save(_ position: Double, for id: Int) {
        guard position.isFinite, position >= 0 else { return }
        defaults.set(position, forKey: key(id))
    }

    func clear(_ id: Int) {
        defaults.removeObject(forKey: key(id))
    }
}
