#if canImport(AVFoundation)
import AVFoundation
import Combine
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
    @Published private(set) var isBoosting = false
    @Published private(set) var isPiPActive = false
    private var foregroundActive = false
    private let previewOnly: Bool
    private let prefersOriginal: Bool
    private var originalUnavailable = false
    private var requestedPlannedStream = false
    private var fallbackTask: Task<Void, Never>?
    private var previewHop: Task<Void, Never>?
    private var cachedPreview: CachedPreviewAsset?

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
    private var intent = PlaybackIntent()
    private var watchSeconds = 0.0
    private var seeks = 0
    private var lastTick: Date?
    private var lastActivityAt = Date.distantPast
    private var pendingResume: Double?
    private var endObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var didEnd = false

    init(api: PeachAPI, item: PeachItem, previewOnly: Bool = false, preferOriginal: Bool = false) {
        self.previewOnly = previewOnly
        self.prefersOriginal = preferOriginal && ["mp4", "m4v", "mov"].contains((item.name as NSString).pathExtension.lowercased())
        self.api = api
        self.item = item
    }

    private func start() async {
        guard intent.isActive else { return }
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
            intent.newSession()
            lastActivityAt = .distantPast
        }
        guard !started else { return }
        started = true
        phase = .preparing
        if !previewOnly {
            if let local = PlayerMemory.shared.position(for: item.id) {
                pendingResume = local
            } else if item.resumeTime > 0 {
                pendingResume = item.resumeTime
            }
        }
        await prepareStream(for: sessionID)
    }

    private func canInstallStream(for requestedSession: String) -> Bool {
        requestedSession == sessionID && !stopped && intent.isActive && !Task.isCancelled
    }

    private func prepareStream(for requestedSession: String) async {
        guard canInstallStream(for: requestedSession) else { return }
        do {
            if prefersOriginal, !originalUnavailable {
                do {
                    let source = try await api.originalPlaybackURL(id: item.id)
                    guard canInstallStream(for: requestedSession) else { return }
                    let asset = AVURLAsset(url: source)
                    if try await Self.hasDecodableVideo(in: asset) {
                        guard canInstallStream(for: requestedSession) else { return }
                        install(asset, note: "原文件直放", original: true)
                        return
                    }
                } catch where Self.canUseCompatibility(after: error) {
                    // The endpoint or the device's decoder does not support this original.
                }
                guard canInstallStream(for: requestedSession) else { return }
                originalUnavailable = true
            }
            requestedPlannedStream = true
            let plan = try await api.streamPlan(id: item.id, sessionID: requestedSession)
            guard canInstallStream(for: requestedSession) else { return }
            let source = try api.playbackURL(plan: plan, id: item.id, sessionID: requestedSession)
            let cookies = HTTPCookieStorage.shared.cookies(for: source) ?? []
            var asset = AVURLAsset(url: source, options: ["AVURLAssetHTTPCookiesKey": cookies])
            if previewOnly, plan.protocolName == "range", plan.mimeType == "video/mp4",
               let cached = try? await PreviewRangeSource.open(origin: api.baseURL, identity: item.mediaCacheIdentity, fetch: { [api] range, version in
                   try await api.previewBytes(from: source, range: range, validator: version)
               }) {
                guard canInstallStream(for: requestedSession) else { return }
                let preview = CachedPreviewAsset(source: cached)
                cachedPreview = preview
                asset = preview.asset
            }
            guard canInstallStream(for: requestedSession) else { return }
            install(asset, note: plan.protocolName == "hls" ? "HLS 自适应分片" : "原始 MP4 流")
        } catch {
            guard requestedSession == sessionID, !stopped, !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private static func hasDecodableVideo(in asset: AVURLAsset) async throws -> Bool {
        // An asset can be playable with just its audio even if no video track can be decoded.
        for track in try await asset.loadTracks(withMediaType: .video) {
            if try await track.load(.isDecodable) { return true }
        }
        return false
    }

    private static func canUseCompatibility(after error: Error) -> Bool {
        let status = (error as? PeachAPIError)?.status
        return status == 404 || status == 405 || isFormatFailure(error)
    }

    private func install(_ asset: AVURLAsset, note: String, original: Bool = false) {
        let playerItem = AVPlayerItem(asset: asset)
        if !original { playerItem.preferredForwardBufferDuration = previewOnly ? 2 : 8 }
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = !previewOnly
        player.allowsExternalPlayback = true
        formatNote = note
        self.player = player
        observe(player, item: playerItem, original: original)
        player.isMuted = isMuted
        if !previewOnly { applyPlaybackIntent() }
        startTicker()
    }

    func togglePlayback() {
        intent.wantsPlayback.toggle()
        applyPlaybackIntent()
        if !intent.wantsPlayback { flushActivity() }
    }

    func doubleTap(at fraction: Double) -> String {
        switch PlaybackTap.action(at: fraction) {
        case .backward: skip(by: -10); return "后退 10 秒"
        case .forward: skip(by: 10); return "前进 10 秒"
        case .toggle:
            togglePlayback()
            return intent.wantsPlayback ? "播放" : "暂停"
        }
    }

    func setActive(_ foreground: Bool) {
        if !foreground { endBoost() }
        foregroundActive = foreground
        let active = foreground || isPiPActive
        intent.isActive = active
        if !active {
            endBoost()
            stopPreviewHops()
            player?.pause()
            isPlaying = false
            intent.scrubbing = false
            isScrubbing = false
            seekPreview = nil
            flushActivity()
            // A pending plan must not survive a page switch. Its late result is
            // rejected by session identity, including a quick return to this page.
            if started, player == nil, !stopped {
                cancelPreparation()
                sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                started = false
            }
        } else if previewOnly {
            startPreviewHops()
        } else {
            applyPlaybackIntent()
        }
    }

    func activate() async {
        setActive(true)
        if started, !stopped { return }
        await start()
    }

    func pause() {
        endBoost()
        intent.wantsPlayback = false
        applyPlaybackIntent()
        flushActivity()
    }

    func resume() {
        intent.wantsPlayback = true
        applyPlaybackIntent()
    }

    private func applyPlaybackIntent() {
        if intent.mayPlay, !stopped {
            lastTick = Date()
            player?.defaultRate = isBoosting ? 2 : 1
            player?.play()
        } else {
            player?.pause()
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        seekPreview = nil
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        seeks += 1
        if !previewOnly { PlayerMemory.shared.save(clamped, for: item.id) }
        flushActivity()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func setPictureInPicture(_ active: Bool) {
        isPiPActive = active
        setActive(foregroundActive)
    }

    func beginBoost() {
        guard intent.mayPlay, !stopped, player != nil else { return }
        isBoosting = true
        applyPlaybackIntent()
    }

    func endBoost() {
        guard isBoosting else { return }
        isBoosting = false
        player?.defaultRate = 1
        if intent.mayPlay, !stopped { player?.rate = 1 }
    }

    func beginScrubbing() {
        endBoost()
        isScrubbing = true
        intent.scrubbing = true
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
        intent.scrubbing = false
        seek(to: time)
        applyPlaybackIntent()
    }

    func cancelScrubbing() {
        isScrubbing = false
        intent.scrubbing = false
        seekPreview = nil
        applyPlaybackIntent()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
    }

    func stop() {
        guard !stopped else { return }
        endBoost()
        isPiPActive = false
        stopPreviewHops()
        if !previewOnly, let player, !didEnd {
            let position = player.currentTime().seconds
            if position.isFinite, position > 1 { PlayerMemory.shared.save(position, for: item.id) }
        }
        flushActivity(force: true)
        stopped = true
        intent.isActive = false
        intent.scrubbing = false
        isScrubbing = false
        isPlaying = false
        seekPreview = nil
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        cachedPreview?.cancel(); cachedPreview = nil
        cancelPreparation()
        player = nil
    }

    private func cancelPreparation() {
        fallbackTask?.cancel()
        fallbackTask = nil
        if requestedPlannedStream {
            api.cancelStream(sessionID: sessionID)
            requestedPlannedStream = false
        }
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
        guard !previewOnly, !stopped, let player else { return }
        let playing = intent.mayPlay && player.timeControlStatus == .playing
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
        guard !previewOnly, let player else { return }
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

    private func observe(_ player: AVPlayer, item playerItem: AVPlayerItem, original: Bool) {
        itemStatus = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : (self.item.duration ?? 0)
                    if self.phase == .preparing { self.phase = .ready }
                    if self.previewOnly { self.startPreviewHops() }
                    else { self.restorePositionIfNeeded(player) }
                case .failed:
                    self.handleFailure(item.error, player: player, item: item, original: original)
                default: break
                }
            }
        }
        itemError = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            guard let error = item.error else { return }
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player else { return }
                self.handleFailure(error, player: player, item: item, original: original)
            }
        }
        timeControlStatus = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player else { return }
                let playing = player.timeControlStatus == .playing
                if playing, !self.intent.mayPlay { player.pause() }
                self.isPlaying = playing && self.intent.mayPlay
                if !self.previewOnly, self.intent.consumePlayMark(isPlaying: playing) {
                    Task { try? await self.api.markPlayed(id: self.item.id) }
                }
            }
        }
        playbackLikelyToKeepUp = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            Task { @MainActor in
                if let self, !self.stopped, self.player === player, case .preparing = self.phase, item.status == .readyToPlay { self.phase = .ready }
            }
        }
        loadedTimeRanges = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let range = item.loadedTimeRanges.last?.timeRangeValue else { return }
            let seconds = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player else { return }
                self.buffered = seconds
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player else { return }
                self.currentTime = seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped, self.player === player, self.intent.isActive else { return }
                self.didEnd = true
                if !self.previewOnly { PlayerMemory.shared.clear(self.item.id) }
                self.flushActivity(force: true, ended: true)
                self.onEnded?()
            }
        }
        if original {
            failedToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                Task { @MainActor in
                    guard let self, !self.stopped, self.player === player else { return }
                    self.handleFailure(error ?? playerItem.error, player: player, item: playerItem, original: true)
                }
            }
        }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled, !self.stopped, self.player === player, self.phase == .preparing else { return }
            self.phase = .failed("播放源长时间没有响应。请检查网络与 Peach 服务地址。")
        }
    }

    private func handleFailure(_ error: Error?, player: AVPlayer, item: AVPlayerItem, original: Bool) {
        // Transport/auth failures should not start an expensive transcode.
        guard original, Self.isFormatFailure(error),
              item.errorLog()?.events.contains(where: { (400...599).contains($0.errorStatusCode) }) != true else {
            phase = .failed(Self.describe(error))
            return
        }
        originalUnavailable = true
        pendingResume = pendingResume ?? currentTime
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        self.player = nil
        isPlaying = false
        buffered = 0
        lastTick = nil
        phase = .preparing
        if intent.isActive {
            let requestedSession = sessionID
            fallbackTask = Task { [weak self] in await self?.prepareStream(for: requestedSession) }
        } else {
            started = false
        }
    }

    private static func isFormatFailure(_ error: Error?) -> Bool {
        let formatCodes: [AVError.Code] = [.decodeFailed, .invalidSourceMedia, .fileFormatNotRecognized, .fileFailedToParse,
                                            .decoderNotFound, .incompatibleAsset, .formatUnsupported, .noSourceTrack]
        var cause = error.map { $0 as NSError }
        var failedToDecode = false
        while let current = cause {
            if current.domain == NSURLErrorDomain { return false }
            if current.domain == AVFoundationErrorDomain, formatCodes.contains(where: { $0.rawValue == current.code }) {
                failedToDecode = true
            }
            cause = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return failedToDecode
    }

    private func startPreviewHops() {
        guard previewOnly, previewHop == nil, phase == .ready, intent.mayPlay, let player else { return }
        let length = duration
        previewHop = Task { [weak self] in
            var index = 0
            do {
                while !Task.isCancelled {
                    let position = length * PreviewPlayback.positions[index]
                    try await PreviewPlayback.playSample(on: player, at: position)
                    index = (index + 1) % PreviewPlayback.positions.count
                }
            } catch {
                guard let self, !Task.isCancelled, !self.stopped, self.player === player else { return }
                player.pause()
                self.phase = .failed(Self.describe(error))
            }
        }
    }

    private func stopPreviewHops() {
        guard let previewHop else { return }
        previewHop.cancel()
        self.previewHop = nil
        player?.currentItem?.cancelPendingSeeks()
    }

    private func restorePositionIfNeeded(_ player: AVPlayer) {
        guard let target = pendingResume else { return }
        pendingResume = nil
        guard duration > 0, target > 5, target < duration - 10 else { return }
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
        if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }
        failedToEndObserver = nil
    }

    private static func describe(_ error: Error?) -> String {
        guard let error else { return "播放器无法打开这个视频。" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "无法连接 Peach。请检查网络与服务地址。"
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

#endif

