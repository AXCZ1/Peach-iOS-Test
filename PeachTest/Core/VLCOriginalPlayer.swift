struct VLCSeekConfirmation {
    let target: Int32
    var displayedBeforeJump: UInt64?
    var origin: Double? = nil

    mutating func observe(position: Double, displayedPictures: UInt64?, playing: Bool) -> Bool {
        let targetSeconds = Double(target) / 1_000
        let distance = abs(position - targetSeconds)
        let arrived: Bool
        if let origin {
            let jumpDistance = abs(origin - targetSeconds)
            if jumpDistance >= 2 {
                arrived = distance < min(12.0, jumpDistance * 0.5)
            } else {
                arrived = distance < 1.5 || abs(position - origin) >= 1.0
            }
        } else {
            arrived = distance < min(12.0, max(1.0, targetSeconds * 0.5))
        }
        guard arrived else {
            if let previous = displayedBeforeJump, let displayedPictures {
                displayedBeforeJump = max(previous, displayedPictures)
            }
            return false
        }
        guard playing, let displayedBeforeJump else { return true }
        return (displayedPictures ?? 0) > displayedBeforeJump
    }
}

#if os(iOS) && !SWIFT_PACKAGE
import AVFoundation
import UIKit
@preconcurrency import VLCKit

/// The URL is Peach's signed Range URL, so VLC doesn't need the App's cookie or password.
@MainActor
final class VLCOriginalPlayer: LocalOriginalPlayer {
    let view = UIView()
    var onEvent: ((LocalPlaybackEvent) -> Void)?

    private var player: VLCMediaPlayer?
    private var playbackRequested = false
    private var muted = false
    private var hasFrame = false
    private var didEnd = false
    private var position = 0.0
    private var firstFrameDeadline: ContinuousClock.Instant?
    private var pulse: Task<Void, Never>?
    private var pendingSeek: Seek?
    private let confirmsSeekFrames: Bool
    private var playCallMilliseconds: Int?
    private var seekCallMilliseconds: Int?
    private var picturesAtSeek: UInt64?
    private var picturesBeforeVisibleLayer: UInt64 = 0
    private var lastDisplayFailureCode: Int?

    private struct Seek {
        let target: Int32
        let completion: (Double?) -> Void
        var confirmation: VLCSeekConfirmation?
        var deadline: ContinuousClock.Instant?
    }

    private static let logSink = VLCPrivateLogSink()
    fileprivate static let installLogSink: Void = {
        VLCLibrary.shared().loggers = [logSink]
    }()

    init(url: URL, decoder: LocalOriginalDecoder, confirmsSeekFrames: Bool = false, mutedOnly: Bool = false) {
        self.confirmsSeekFrames = confirmsSeekFrames
        self.muted = mutedOnly
        _ = Self.installLogSink
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        let player = VLCMediaPlayer()
        player.drawable = view
        let media = VLCMedia(url: url)
        if mutedOnly {
            media?.addOption(":no-audio")
        }
        if confirmsSeekFrames {
            media?.addOption(":input-fast-seek")
            media?.addOption(":network-caching=300")
        }
        if decoder == .software { media?.addOption(":no-hw-dec") }
        player.media = media
        self.player = player
        PeachRuntimeLogger.shared.log(
            "VLC 初始化 decoder=\(decoder == .software ? "software" : "auto") confirmsSeek=\(confirmsSeekFrames) mutedOnly=\(mutedOnly) url=\(url.absoluteString)",
            level: .info,
            category: "player.vlc",
            source: "VLCOriginalPlayer"
        )
    }

    var reportingPosition: Double? {
        guard hasFrame, pendingSeek == nil else { return nil }
        return position
    }

    var isSeekable: Bool { player?.isSeekable == true }

    var pictureInPictureLayer: AVSampleBufferDisplayLayer? {
        // VLCKit's Apple renderer puts the decoded frames into this layer.
        func findLayer(in view: UIView) -> AVSampleBufferDisplayLayer? {
            if let layer = view.layer as? AVSampleBufferDisplayLayer { return layer }
            for child in view.subviews {
                if let layer = findLayer(in: child) { return layer }
            }
            return nil
        }
        return findLayer(in: view)
    }

    func setPlayback(_ shouldPlay: Bool, rate: Float) {
        guard let player else { return }
        let rateChanged = abs(player.rate - rate) > 0.01
        player.rate = rate
        if confirmsSeekFrames, shouldPlay, playbackRequested, rateChanged, hasFrame, pendingSeek == nil {
            flushDisplayLayer(onlyWhenFailed: false)
        }
        if rateChanged {
            PeachRuntimeLogger.shared.log(
                "VLC 速率变更 rate=\(rate) shouldPlay=\(shouldPlay)",
                level: .debug,
                category: "player.vlc",
                source: "VLCOriginalPlayer"
            )
        }
        if shouldPlay, !playbackRequested {
            playbackRequested = true
            if didEnd {
                didEnd = false
                hasFrame = false
                position = 0
            }
            if !hasFrame { firstFrameDeadline = ContinuousClock.now + .seconds(15) }
            applyMute(to: player)
            PeachRuntimeLogger.shared.log(
                "VLC 请求起播/恢复 rate=\(rate) hasFrame=\(hasFrame)",
                level: .info,
                category: "player.vlc",
                source: "VLCOriginalPlayer"
            )
            let started = ContinuousClock.now
            player.play()
            applyMute(to: player)
            if confirmsSeekFrames { playCallMilliseconds = elapsedMilliseconds(since: started) }
        } else if !shouldPlay, playbackRequested {
            playbackRequested = false
            firstFrameDeadline = nil
            player.pause()
            PeachRuntimeLogger.shared.log(
                "VLC 暂停 pos=\(String(format: "%.2f", position))",
                level: .debug,
                category: "player.vlc",
                source: "VLCOriginalPlayer"
            )
            onEvent?(.sample(position: reportingPosition, duration: duration(of: player), playing: false, hasFrame: hasFrame))
        }
        updatePulse()
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        if let player { applyMute(to: player) }
    }

    func seek(to time: Double, completion: @escaping (Double?) -> Void) {
        guard let player, time.isFinite, time >= 0, time * 1_000 <= Double(Int32.max) else {
            completion(nil)
            return
        }
        cancelSeek()
        pendingSeek = Seek(target: Int32((time * 1_000).rounded()), completion: completion)
        PeachRuntimeLogger.shared.log(
            "VLC 请求跳转 target=\(String(format: "%.2f", time))s",
            level: .debug,
            category: "player.vlc",
            source: "VLCOriginalPlayer"
        )
        applyMute(to: player)
        updatePulse()
    }

    func stop() {
        pulse?.cancel()
        pulse = nil
        cancelSeek()
        firstFrameDeadline = nil
        playbackRequested = false
        guard let player else { return }
        self.player = nil
        player.audio?.isMuted = true
        player.pause()
        player.drawable = nil
        PeachRuntimeLogger.shared.log(
            "VLC stop() 移交后台释放队列 pos=\(String(format: "%.2f", position)) hasFrame=\(hasFrame)",
            level: .info,
            category: "player.vlc",
            source: "VLCOriginalPlayer"
        )
        let retirement = VLCPlayerRetirement(player)
        retirement.stopAndReleaseWhenStopped()
    }

    private func updatePulse() {
        guard playbackRequested || (pendingSeek != nil && player?.isSeekable == true) else {
            pulse?.cancel()
            pulse = nil
            return
        }
        guard pulse == nil else { return }
        pulse = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.poll()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    private func poll() {
        guard let player else { return }
        resumeFailedDisplayIfNeeded()
        let state = player.state
        let checkingSeek = confirmsSeekFrames && pendingSeek != nil
        let statistics = (!hasFrame || checkingSeek) && state != .stopped ? player.media?.statistics : nil
        let displayedCount = statistics?.displayedPictures ?? 0
        let displayedFrame = displayedCount > 0
        let canRetryInSoftware = !hasFrame && !displayedFrame && (statistics?.demuxReadBytes ?? 0) > 0
        if state == .error {
            fail("iPhone 无法打开原文件。请检查 Peach 连接和文件格式。", canRetryInSoftware: canRetryInSoftware)
            return
        }
        let milliseconds = player.time.intValue
        if milliseconds >= 0 {
            position = Double(milliseconds) / 1_000
        }
        let total = duration(of: player)
        markFirstFrameIfReady(displayedCount: displayedCount)
        // VLC 4 reports .stopped at EOF. It also starts in .stopped before opening.
        if state == .stopped, hasFrame, !didEnd {
            playbackRequested = false
            cancelSeek()
            didEnd = true
            if total > 0 { position = total }
            onEvent?(.sample(position: position, duration: total, playing: false, hasFrame: true))
            onEvent?(.ended)
            updatePulse()
            return
        }
        updateSeek(on: player, displayedPictures: statistics?.displayedPictures, canRetryInSoftware: canRetryInSoftware)
        guard self.player != nil else { return }
        markFirstFrameIfReady(displayedCount: displayedCount)
        if let deadline = firstFrameDeadline, ContinuousClock.now >= deadline {
            let message: String
            if confirmsSeekFrames, let statistics, statistics.demuxReadBytes > 0 {
                message = statistics.decodedVideo > 0
                    ? "VLC 已解码视频，但没有显示画面。"
                    : "已读取原文件，但 VLC 没有解出视频帧。"
            } else {
                message = "原文件没有输出画面。"
            }
            fail(message, canRetryInSoftware: canRetryInSoftware)
            return
        }
        applyMute(to: player)
        onEvent?(.sample(position: reportingPosition, duration: total,
                        playing: playbackRequested && player.isPlaying && reportingPosition != nil,
                        hasFrame: hasFrame))
        updatePulse()
    }

    private func markFirstFrameIfReady(displayedCount: UInt64) {
        guard !hasFrame else { return }
        let displayedFrame = displayedCount > 0
        if confirmsSeekFrames {
            // A failed sample-buffer layer drops pictures while VLC still counts
            // them. A missing layer keeps the previous displayed-picture rule.
            if let layer = pictureInPictureLayer {
                if layer.status == .failed {
                    picturesBeforeVisibleLayer = max(picturesBeforeVisibleLayer, displayedCount)
                    return
                }
                guard pendingSeek == nil, displayedCount > picturesBeforeVisibleLayer else { return }
            } else {
                guard pendingSeek == nil, displayedFrame else { return }
            }
        } else {
            guard pendingSeek == nil, displayedFrame else { return }
        }
        hasFrame = true
        firstFrameDeadline = nil
        PeachRuntimeLogger.shared.log(
            "VLC 首帧出画 facts=\(playbackFacts())",
            level: .info,
            category: "player.vlc",
            source: "VLCOriginalPlayer"
        )
    }

    private func updateSeek(on player: VLCMediaPlayer, displayedPictures: UInt64?, canRetryInSoftware: Bool) {
        guard var seek = pendingSeek else { return }
        if seek.confirmation == nil {
            guard player.isSeekable else { return }
            let beforeJump = confirmsSeekFrames && playbackRequested ? (displayedPictures ?? 0) : nil
            let origin = hasFrame ? position : nil
            seek.confirmation = VLCSeekConfirmation(target: seek.target, displayedBeforeJump: beforeJump, origin: origin)
            seek.deadline = ContinuousClock.now + .seconds(12)
            pendingSeek = seek
            // The sample-buffer display keeps the last image across a time jump
            // and then drops every later picture once its status is failed.
            if confirmsSeekFrames { prepareDisplayForTimeJump() }
            picturesAtSeek = displayedPictures
            let started = ContinuousClock.now
            player.time = VLCTime(int: seek.target)
            if confirmsSeekFrames { seekCallMilliseconds = elapsedMilliseconds(since: started) }
            if !hasFrame { firstFrameDeadline = ContinuousClock.now + .seconds(15) }
            return
        }
        // A native clock jump can precede the next video frame.
        let displayFailed = confirmsSeekFrames && pictureInPictureLayer?.status == .failed
        if !displayFailed && seek.confirmation?.observe(position: position, displayedPictures: displayedPictures, playing: playbackRequested) == true {
            pendingSeek = nil
            PeachRuntimeLogger.shared.log(
                "VLC 跳转确认完成 targetMs=\(seek.target) pos=\(String(format: "%.2f", position))s",
                level: .debug,
                category: "player.vlc",
                source: "VLCOriginalPlayer"
            )
            seek.completion(position)
        } else if let deadline = seek.deadline, ContinuousClock.now >= deadline {
            let hasNewFrames = (displayedPictures ?? 0) > (picturesAtSeek ?? 0)
            let nearTarget = abs(position - Double(seek.target) / 1_000) < 30
            if !displayFailed && hasNewFrames && (hasFrame || nearTarget) {
                pendingSeek = nil
                PeachRuntimeLogger.shared.log(
                    "VLC 跳转超时兜底放行 targetMs=\(seek.target) pos=\(String(format: "%.2f", position))s",
                    level: .warning,
                    category: "player.vlc",
                    source: "VLCOriginalPlayer"
                )
                seek.completion(position)
            } else if confirmsSeekFrames && playbackRequested {
                fail("未能跳转到指定位置。", canRetryInSoftware: canRetryInSoftware)
            } else {
                pendingSeek = nil
                PeachRuntimeLogger.shared.log(
                    "VLC 非播放状态跳转超时 targetMs=\(seek.target) facts=\(playbackFacts())",
                    level: .warning,
                    category: "player.vlc",
                    source: "VLCOriginalPlayer"
                )
                seek.completion(nil)
            }
        } else {
            pendingSeek = seek
        }
    }

    private func cancelSeek() {
        let seek = pendingSeek
        pendingSeek = nil
        seek?.completion(nil)
    }

    /// VLC 4 timestamps samples against the host clock and does not flush the
    /// sample-buffer layer on seek. Once that layer fails for any reason other
    /// than revoked decoder resources, its display callback drops every later
    /// picture and the previous image stays. The host clock itself is left
    /// alone: picture-in-picture timing is calculated from it.
    private func prepareDisplayForTimeJump() {
        flushDisplayLayer(onlyWhenFailed: false)
    }

    private func resumeFailedDisplayIfNeeded() {
        flushDisplayLayer(onlyWhenFailed: true)
    }

    private func flushDisplayLayer(onlyWhenFailed: Bool) {
        guard confirmsSeekFrames, let layer = pictureInPictureLayer else { return }
        if layer.status == .failed {
            lastDisplayFailureCode = (layer.error as NSError?)?.code ?? lastDisplayFailureCode
            PeachRuntimeLogger.shared.log(
                "VLC AVSampleBufferDisplayLayer 状态 failed code=\(lastDisplayFailureCode ?? -1) err=\(layer.error?.localizedDescription ?? "unknown")，执行 flush()",
                level: .warning,
                category: "player.vlc",
                source: "VLCOriginalPlayer"
            )
        } else if onlyWhenFailed {
            return
        }
        layer.flush()
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let parts = start.duration(to: .now).components
        return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    private func playbackFacts() -> String {
        let stateName: String
        switch player?.state {
        case .opening: stateName = "opening"
        case .playing: stateName = "playing"
        case .paused: stateName = "paused"
        case .stopping: stateName = "stopping"
        case .stopped: stateName = "stopped"
        case .error: stateName = "error"
        default: stateName = "none"
        }
        let stats = player?.media?.statistics
        let shown = stats?.displayedPictures ?? 0
        let shownText = picturesAtSeek.map { "显示 \($0)→\(shown)" } ?? "显示 \(shown)"
        let playCall = playCallMilliseconds.map { "播放调用 \($0)ms" } ?? "播放调用未计时"
        let seekCall = seekCallMilliseconds.map { "跳转调用 \($0)ms" } ?? "未调用跳转"
        let target = pendingSeek.map { String(format: "目标 %.1f", Double($0.target) / 1_000) } ?? "无跳转"
        var layerText: String
        if let layer = pictureInPictureLayer {
            switch layer.status {
            case .unknown: layerText = "画面层 unknown"
            case .rendering: layerText = "画面层 rendering"
            case .failed: layerText = "画面层 failed \((layer.error as NSError?)?.code ?? 0)"
            @unknown default: layerText = "画面层 other"
            }
            if layer.status != .failed, let lastDisplayFailureCode {
                layerText += "，曾失败 \(lastDisplayFailureCode)"
            }
        } else {
            layerText = "画面层未创建"
            if let lastDisplayFailureCode { layerText += "，曾失败 \(lastDisplayFailureCode)" }
        }
        return "时间 \(String(format: "%.1f", position))s，状态 \(stateName)，\(target)，\(playCall)，\(seekCall)。读取 \(stats?.demuxReadBytes ?? 0)，解码 \(stats?.decodedVideo ?? 0)，\(shownText)，丢失 \(stats?.lostPictures ?? 0)。\(layerText)"
    }

    private func applyMute(to player: VLCMediaPlayer) {
        let mute = muted || pendingSeek != nil
        if let audio = player.audio, audio.isMuted != mute { audio.isMuted = mute }
    }

    private func duration(of player: VLCMediaPlayer) -> Double {
        guard let length = player.media?.length.intValue, length > 0 else { return 0 }
        return Double(length) / 1_000
    }

    private func fail(_ message: String, canRetryInSoftware: Bool) {
        let reported = confirmsSeekFrames ? message + "\n" + playbackFacts() : message
        PeachRuntimeLogger.shared.log(
            "VLC 播放失败 retrySW=\(canRetryInSoftware): \(reported)",
            level: .error,
            category: "player.vlc",
            source: "VLCOriginalPlayer"
        )
        if confirmsSeekFrames, pendingSeek != nil { hasFrame = false }
        stop()
        onEvent?(.failed(reported, canRetryInSoftware: canRetryInSoftware))
    }
}

@MainActor
final class VLCOriginalFrameDecoder: NSObject, VLCMediaThumbnailerDelegate {
    private let media: VLCMedia
    private var size: CGSize?
    private var thumbnailer: VLCMediaThumbnailer?
    private var continuation: CheckedContinuation<CGImage, Error>?

    init?(url: URL, width: Int?, height: Int?) {
        _ = VLCOriginalPlayer.installLogSink
        guard let media = VLCMedia(url: url) else { return nil }
        media.addOption(":input-fast-seek")
        media.addOption(":no-audio")
        self.media = media
        if let width, let height, width > 0, height > 0 {
            size = CGSize(width: width, height: height)
        }
        super.init()
    }

    func capture(at seconds: Double) async throws -> CGImage {
        guard seconds.isFinite, seconds >= 0, seconds * 1_000 <= Double(Int32.max) else {
            throw PeachAPIError(message: "预览图时间无效")
        }
        let sourceSize = try await originalSize()
        let scale = min(1.0, min(960.0 / max(sourceSize.width, 1), 540.0 / max(sourceSize.height, 1)))
        let targetSize = CGSize(width: max(1, (sourceSize.width * scale).rounded()),
                                height: max(1, (sourceSize.height * scale).rounded()))
        try Task.checkCancellation()
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.thumbnailWidth = targetSize.width
        thumbnailer.thumbnailHeight = targetSize.height
        thumbnailer.snapshotTime = VLCTime(int: Int32((seconds * 1_000).rounded()))
        thumbnailer.preciseSeek = false
        thumbnailer.hardwareDecodingEnabled = true
        let id = ObjectIdentifier(thumbnailer)
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(24)) } catch { return }
            self?.finish(id, result: .failure(PeachAPIError(message: "等待原画帧超时")), cancel: true)
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.thumbnailer = thumbnailer
                self.continuation = continuation
                thumbnailer.fetchThumbnail()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(id, result: .failure(CancellationError()), cancel: true)
            }
        }
    }

    private func originalSize() async throws -> CGSize {
        if let size { return size }
        let parser = VLCMediaParser(library: VLCLibrary.shared(), timeout: 8_000)
        guard parser.queue(media, options: VLCMediaParsingOptions(rawValue: 1)) == 0 else {
            throw PeachAPIError(message: "无法读取原文件的分辨率")
        }
        defer { parser.cancelAllParsing() }
        let deadline = ContinuousClock.now + .seconds(9)
        while media.parsedStatus == .none || media.parsedStatus == .pending {
            guard ContinuousClock.now < deadline else { throw PeachAPIError(message: "读取原文件分辨率超时") }
            try await Task.sleep(for: .milliseconds(80))
        }
        guard let video = media.videoTracks.compactMap(\.video).first, video.width > 0, video.height > 0 else {
            throw PeachAPIError(message: "无法读取原文件的分辨率")
        }
        let dimensions = CGSize(width: Int(video.width), height: Int(video.height))
        size = dimensions
        return dimensions
    }

    nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        let id = ObjectIdentifier(mediaThumbnailer)
        Task { @MainActor [weak self] in
            self?.finish(id, result: .failure(PeachAPIError(message: "iPhone 无法从原文件取帧")))
        }
    }

    nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let id = ObjectIdentifier(mediaThumbnailer)
        Task { @MainActor [weak self] in self?.finish(id, result: .success(thumbnail)) }
    }

    private func finish(_ id: ObjectIdentifier, result: Result<CGImage, Error>, cancel: Bool = false) {
        guard let thumbnailer, ObjectIdentifier(thumbnailer) == id else { return }
        if cancel { thumbnailer.cancel() }
        self.thumbnailer = nil
        let pending = continuation
        continuation = nil
        switch result {
        case .success(let image):
            PeachRuntimeLogger.shared.log(
                "VLC 缩略图取帧成功 \(image.width)x\(image.height)",
                level: .debug,
                category: "player.vlc",
                source: "VLCOriginalFrameDecoder"
            )
        case .failure(let error) where !(error is CancellationError):
            PeachRuntimeLogger.shared.log(
                "VLC 缩略图取帧失败: \(error.localizedDescription)",
                level: .warning,
                category: "player.vlc",
                source: "VLCOriginalFrameDecoder"
            )
        default: break
        }
        pending?.resume(with: result)
    }
}

/// VLCKit stops asynchronously; retire and release each player off the main thread.
private final class VLCPlayerRetirement: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Peach.VLC.retirement", qos: .utility)
    private var player: VLCMediaPlayer?
    private var stateObserver: NSObjectProtocol?
    private var timeoutItem: DispatchWorkItem?
    private var retainedSelf: VLCPlayerRetirement?
    private var didFinish = false

    init(_ player: VLCMediaPlayer) { self.player = player }

    func stopAndReleaseWhenStopped() {
        queue.async { [self] in
            guard let player else {
                finish(clearMedia: false)
                return
            }
            retainedSelf = self
            stateObserver = NotificationCenter.default.addObserver(
                forName: VLCMediaPlayer.stateChangedNotification,
                object: player,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [weak self] in self?.finishIfStopped() }
            }
            player.stop()
            finishIfStopped()
            guard !didFinish else { return }
            let timeout = DispatchWorkItem { [weak self] in
                self?.finishOnTimeout()
            }
            timeoutItem = timeout
            queue.asyncAfter(deadline: .now() + .seconds(5), execute: timeout)
        }
    }

    private func finishIfStopped() {
        guard !didFinish, let player else { return }
        guard player.state == .stopped else { return }
        finish(clearMedia: true)
    }

    private func finishOnTimeout() {
        guard !didFinish else { return }
        let stoppedNow = player?.state == .stopped
        PeachRuntimeLogger.shared.log(
            "VLC 后台释放超时 5s state=\(player?.state.rawValue ?? -1) clearMedia=\(stoppedNow)",
            level: .warning,
            category: "player.vlc",
            source: "VLCPlayerRetirement"
        )
        finish(clearMedia: stoppedNow)
    }

    private func finish(clearMedia: Bool) {
        didFinish = true
        timeoutItem?.cancel()
        timeoutItem = nil
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
            self.stateObserver = nil
        }
        if clearMedia {
            player?.media = nil
        }
        player = nil
        retainedSelf = nil
        PeachRuntimeLogger.shared.log(
            "VLC 后台释放完成 clearMedia=\(clearMedia)",
            level: .debug,
            category: "player.vlc",
            source: "VLCPlayerRetirement"
        )
    }
}

/// Forwards all VLCKit log levels into PeachRuntimeLogger without writing signed playback URLs to stderr.
private final class VLCPrivateLogSink: NSObject, VLCLogging {
    var level: VLCLogLevel = VLCLogLevel(rawValue: 3)!

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        let mappedLevel: PeachLogLevel
        switch level.rawValue {
        case 0: mappedLevel = .error
        case 1: mappedLevel = .warning
        case 2: mappedLevel = .info
        default: mappedLevel = .debug
        }
        var fields: [String: String] = ["vlc_level": String(level.rawValue)]
        if let context {
            fields["module"] = context.module
            fields["object_type"] = context.objectType
            fields["object_id"] = String(context.objectId)
            fields["thread_id"] = String(context.threadId)
            if let header = context.header, !header.isEmpty { fields["header"] = header }
            if let file = context.file, !file.isEmpty {
                fields["file"] = "\(file):\(context.line)"
            }
            if let fn = context.function, !fn.isEmpty { fields["function"] = fn }
        }
        let category = context.map { "vlc.\($0.module)" } ?? "vlc"
        PeachRuntimeLogger.shared.log(
            message,
            level: mappedLevel,
            category: category,
            source: context?.objectType ?? "VLCKit",
            fields: fields
        )
    }
}
#endif
