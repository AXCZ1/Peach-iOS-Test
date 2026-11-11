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
    @Published private(set) var localPlayer: (any LocalOriginalPlayer)?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPausedByUser = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var buffered = 0.0
    @Published private(set) var formatNote: String?
    @Published private(set) var isMuted = false
    @Published private(set) var isScrubbing = false
    @Published private(set) var seekPreview: Double? = nil
    @Published private(set) var isBoosting = false
    @Published private(set) var isPiPActive = false
    var hasVideoSurface: Bool { player != nil || localPlayer != nil }
    private var foregroundActive = false
    private let previewOnly: Bool
    private let usesDirectRateControl: Bool
    private let makeLocalPlayer: @MainActor (URL, LocalOriginalDecoder) -> (any LocalOriginalPlayer)?
    private var avOriginalURL: URL?
    private var didDisplayAVFrame = false
    private var firstFrameTask: Task<Void, Never>?
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
    private var intent = PlaybackIntent() {
        didSet {
            if oldValue.wantsPlayback != intent.wantsPlayback {
                isPausedByUser = !intent.wantsPlayback
            }
        }
    }
    private var watchSeconds = 0.0
    private var seeks = 0
    private var lastTick: Date?
    private var lastActivityAt = Date.distantPast
    private var pendingResume: Double?
    private var endObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var didEnd = false

    init(api: PeachAPI, item: PeachItem, previewOnly: Bool = false, usesDirectRateControl: Bool = false,
         makeLocalPlayer: (@MainActor (URL, LocalOriginalDecoder) -> (any LocalOriginalPlayer)?)? = nil) {
        self.previewOnly = previewOnly
        self.usesDirectRateControl = usesDirectRateControl
        self.api = api
        self.item = item
        self.makeLocalPlayer = makeLocalPlayer ?? Self.defaultLocalPlayer
    }

    private static func defaultLocalPlayer(_ url: URL, _ decoder: LocalOriginalDecoder) -> (any LocalOriginalPlayer)? {
        #if os(iOS) && !SWIFT_PACKAGE
        VLCOriginalPlayer(url: url, decoder: decoder)
        #else
        nil
        #endif
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
            pendingResume = PlayerMemory.shared.position(for: item.id) ?? item.resumeTime
        }
        await prepareStream(for: sessionID)
    }

    private func canInstallStream(for requestedSession: String) -> Bool {
        requestedSession == sessionID && !stopped && intent.isActive && !Task.isCancelled
    }

    private func prepareStream(for requestedSession: String) async {
        guard canInstallStream(for: requestedSession) else { return }
        do {
            try await prepareOriginal(for: requestedSession)
        } catch {
            guard requestedSession == sessionID, !stopped, !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func prepareOriginal(for requestedSession: String) async throws {
        let source = try await api.originalPlaybackURL(id: item.id)
        guard canInstallStream(for: requestedSession) else { return }
        if item.canProbeOriginalWithAVFoundation {
            var asset = AVURLAsset(url: source)
            do {
                if try await Self.hasDecodableVideo(in: asset) {
                    guard canInstallStream(for: requestedSession) else { return }
                    if previewOnly, (item.name as NSString).pathExtension.lowercased() == "mp4",
                       let cached = try? await PreviewRangeSource.open(origin: api.baseURL, identity: item.mediaCacheIdentity, fetch: { [api] range, version in
                           try await api.previewBytes(from: source, range: range, validator: version)
                       }) {
                        guard canInstallStream(for: requestedSession) else { return }
                        let preview = CachedPreviewAsset(source: cached)
                        cachedPreview = preview
                        asset = preview.asset
                    }
                    guard canInstallStream(for: requestedSession) else { return }
                    install(asset, note: "原文件直放", originalURL: source)
                    return
                }
            } catch where Self.isFormatFailure(error) {
                // Use the same original stream with the other decoder.
            }
        }
        guard canInstallStream(for: requestedSession) else { return }
        installLocalPlayer(for: source)
    }

    private static func hasDecodableVideo(in asset: AVURLAsset) async throws -> Bool {
        // An asset can be playable with just its audio even if no video track can be decoded.
        for track in try await asset.loadTracks(withMediaType: .video) {
            if try await track.load(.isDecodable) { return true }
        }
        return false
    }

    private func install(_ asset: AVURLAsset, note: String, originalURL: URL? = nil) {
        let playerItem = AVPlayerItem(asset: asset)
        if previewOnly { playerItem.preferredForwardBufferDuration = 2 }
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = !previewOnly
        player.allowsExternalPlayback = true
        formatNote = note
        avOriginalURL = originalURL
        didDisplayAVFrame = false
        self.player = player
        observe(player, item: playerItem, original: originalURL != nil)
        player.isMuted = isMuted
        if !previewOnly { applyPlaybackIntent() }
        startTicker()
    }

    private func installLocalPlayer(for source: URL, decoder: LocalOriginalDecoder = .automatic) {
        guard let backend = makeLocalPlayer(source, decoder) else {
            phase = .failed("此设备没有可解码这个原文件的播放器。")
            return
        }
        duration = item.duration ?? duration
        formatNote = decoder == .software ? "原文件直放 · VLC 软件解码" : "原文件直放 · VLC"
        backend.onEvent = { [weak self, weak backend] event in
            guard let self, let backend, self.localPlayer === backend, !self.stopped else { return }
            self.handleLocalEvent(event, source: source, decoder: decoder)
        }
        localPlayer = backend
        backend.setMuted(isMuted)
        if previewOnly {
            if duration > 0 { startPreviewHops() }
            else { backend.setPlayback(true, rate: 1) }
            return
        }
        if let target = pendingResume, target > 5, duration <= 0 || target < duration - 10 {
            currentTime = target
            backend.seek(to: target) { _ in }
        }
        pendingResume = nil
        applyPlaybackIntent()
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
            pauseInstalledPlayer()
            isPlaying = false
            intent.scrubbing = false
            isScrubbing = false
            seekPreview = nil
            flushActivity()
            // A pending ticket must not survive a page switch. Its late result is
            // rejected by session identity, including a quick return to this page.
            if started, !hasVideoSurface, !stopped {
                sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                started = false
            }
        } else if previewOnly {
            startPreviewHops()
            if duration <= 0 { localPlayer?.setPlayback(true, rate: 1) }
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
            let rate: Float = isBoosting ? 2 : 1
            if let localPlayer {
                localPlayer.setPlayback(true, rate: rate)
            } else {
                player?.defaultRate = rate
                player?.play()
                watchForFirstFrame()
            }
        } else {
            pauseInstalledPlayer()
        }
    }

    private func pauseInstalledPlayer() {
        player?.pause()
        localPlayer?.setPlayback(false, rate: 1)
        firstFrameTask?.cancel()
        firstFrameTask = nil
    }

    var climaxPosition: Double? { isScrubbing ? nil : reportingPosition }

    func seek(to time: Double, completion: (() -> Void)? = nil) {
        guard hasVideoSurface else { completion?(); return }
        seekPreview = nil
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        currentTime = clamped
        if let localPlayer {
            localPlayer.seek(to: clamped) { [weak self, weak localPlayer] reached in
                defer { completion?() }
                guard let self, let localPlayer, self.localPlayer === localPlayer, !self.stopped,
                      let reached else { return }
                self.currentTime = reached
                self.seeks += 1
                if !self.previewOnly { PlayerMemory.shared.save(reached, for: self.item.id) }
                self.flushActivity()
            }
            return
        }
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        seeks += 1
        if !previewOnly { PlayerMemory.shared.save(clamped, for: item.id) }
        flushActivity()
        completion?()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func setPictureInPicture(_ active: Bool) {
        isPiPActive = active
        setActive(foregroundActive)
    }

    func beginBoost() {
        guard intent.mayPlay, !stopped, hasVideoSurface else { return }
        isBoosting = true
        if usesDirectRateControl {
            setBackendRate(2)
        } else {
            applyPlaybackIntent()
        }
    }

    func endBoost() {
        guard isBoosting else { return }
        isBoosting = false
        if usesDirectRateControl {
            setBackendRate(1)
            return
        }
        if let localPlayer {
            localPlayer.setPlayback(intent.mayPlay && !stopped, rate: 1)
            return
        }
        setBackendRate(1)
    }

    // Like NAS iOS, a speed gesture changes rate without issuing play/pause.
    private func setBackendRate(_ rate: Float) {
        if let localPlayer {
            localPlayer.setRate(rate)
        } else {
            player?.defaultRate = rate
            if intent.mayPlay, !stopped { player?.rate = rate }
        }
    }

    func beginScrubbing(pausesPlayback: Bool = true) {
        endBoost()
        isScrubbing = true
        intent.scrubbing = pausesPlayback
        if pausesPlayback { pauseInstalledPlayer() }
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
        let pausedForScrub = intent.scrubbing
        isScrubbing = false
        intent.scrubbing = false
        seek(to: time)
        if pausedForScrub { applyPlaybackIntent() }
    }

    func cancelScrubbing() {
        let pausedForScrub = intent.scrubbing
        isScrubbing = false
        intent.scrubbing = false
        seekPreview = nil
        if pausedForScrub { applyPlaybackIntent() }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        localPlayer?.setMuted(muted)
    }

    func stop() {
        guard !stopped else { return }
        endBoost()
        isPiPActive = false
        stopPreviewHops()
        if !previewOnly, let position = reportingPosition, !didEnd {
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
        localPlayer?.onEvent = nil
        localPlayer?.stop()
        localPlayer = nil
        avOriginalURL = nil
        cachedPreview?.cancel(); cachedPreview = nil
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
        guard !previewOnly, !stopped, hasVideoSurface else { return }
        let playing = intent.mayPlay && (player.map { $0.timeControlStatus == .playing } ?? isPlaying)
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
        guard !previewOnly, let position = reportingPosition else { return }
        guard !stopped || force else { return }
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

    private var reportingPosition: Double? {
        if let localPlayer { return localPlayer.reportingPosition }
        return player?.currentTime().seconds
    }

    private func handleLocalEvent(_ event: LocalPlaybackEvent, source: URL, decoder: LocalOriginalDecoder) {
        switch event {
        case let .sample(position, length, playing, hasFrame):
            if let position, !intent.scrubbing { currentTime = position }
            if length > 0, length != duration { duration = length }
            if hasFrame, phase == .preparing { phase = .ready }
            if previewOnly { startPreviewHops() }
            updatePlaying(playing)
        case .ended:
            if intent.isActive { finishPlayback() }
        case let .failed(message, canRetryInSoftware):
            stopPreviewHops()
            flushActivity(force: true)
            localPlayer?.onEvent = nil
            localPlayer?.stop()
            localPlayer = nil
            ticker?.cancel()
            ticker = nil
            isPlaying = false
            if canRetryInSoftware, decoder == .automatic, !previewOnly, intent.mayPlay {
                pendingResume = currentTime
                phase = .preparing
                installLocalPlayer(for: source, decoder: .software)
            } else {
                phase = .failed(message)
            }
        }
    }

    private func updatePlaying(_ playing: Bool) {
        let activePlayback = playing && intent.mayPlay
        if isPlaying != activePlayback { isPlaying = activePlayback }
        if !previewOnly, intent.consumePlayMark(isPlaying: playing) {
            Task { try? await self.api.markPlayed(id: self.item.id) }
        }
    }

    private func finishPlayback() {
        didEnd = true
        if !previewOnly { PlayerMemory.shared.clear(item.id) }
        flushActivity(force: true, ended: true)
        onEnded?()
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
                self.updatePlaying(playing)
                self.watchForFirstFrame()
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
                self.finishPlayback()
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
        guard original, let source = avOriginalURL, Self.isFormatFailure(error), !Self.hasHTTPFailure(item) else {
            phase = .failed(Self.describe(error))
            return
        }
        switchToLocalPlayer(source: source, replacing: player)
    }

    func noteDisplayedFrame(for player: AVPlayer) {
        guard self.player === player else { return }
        didDisplayAVFrame = true
        watchForFirstFrame()
    }

    private func watchForFirstFrame() {
        guard let player, let source = avOriginalURL, !didDisplayAVFrame,
              !stopped, intent.mayPlay, !isPiPActive, player.timeControlStatus == .playing else {
            firstFrameTask?.cancel()
            firstFrameTask = nil
            return
        }
        guard firstFrameTask == nil else { return }
        firstFrameTask = Task { [weak self, weak player] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, let player, self.player === player else { return }
            self.firstFrameTask = nil
            // A decoder can play the audio track without ever displaying video.
            guard !self.didDisplayAVFrame, !self.stopped, self.intent.mayPlay,
                  !self.isPiPActive, player.timeControlStatus == .playing,
                  let item = player.currentItem, !Self.hasHTTPFailure(item) else { return }
            self.switchToLocalPlayer(source: source, replacing: player)
        }
    }

    private static func hasHTTPFailure(_ item: AVPlayerItem) -> Bool {
        item.errorLog()?.events.contains(where: { (400...599).contains($0.errorStatusCode) }) == true
    }

    private func switchToLocalPlayer(source: URL, replacing player: AVPlayer) {
        if !previewOnly { pendingResume = pendingResume ?? currentTime }
        stopPreviewHops()
        avOriginalURL = nil
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        cachedPreview?.cancel(); cachedPreview = nil
        self.player = nil
        isPlaying = false
        buffered = 0
        lastTick = nil
        phase = .preparing
        installLocalPlayer(for: source)
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
        guard previewOnly, previewHop == nil, intent.mayPlay, duration > 0 else { return }
        if case .failed = phase { return }
        let player = self.player
        let localPlayer = self.localPlayer
        guard (phase == .ready && player != nil) || localPlayer != nil else { return }
        let length = duration
        let previewSession = sessionID
        previewHop = Task { [weak self] in
            var index = 0
            do {
                while !Task.isCancelled {
                    let position = length * PreviewPlayback.positions[index]
                    if let player { try await PreviewPlayback.playSample(on: player, at: position) }
                    else if let localPlayer {
                        try await PreviewPlayback.playSample(on: localPlayer, at: position, duration: length)
                    }
                    index = (index + 1) % PreviewPlayback.positions.count
                }
            } catch {
                guard let self, !Task.isCancelled, !self.stopped, self.sessionID == previewSession else { return }
                if let player, let item = player.currentItem, let source = self.avOriginalURL,
                   Self.isFormatFailure(error), !Self.hasHTTPFailure(item) {
                    self.switchToLocalPlayer(source: source, replacing: player)
                } else {
                    self.pauseInstalledPlayer()
                    self.phase = .failed(Self.describe(error))
                }
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
        firstFrameTask?.cancel()
        firstFrameTask = nil
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

