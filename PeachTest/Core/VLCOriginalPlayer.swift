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

    private struct Seek {
        let target: Int32
        let completion: (Double?) -> Void
        var issued = false
        var deadline: ContinuousClock.Instant?
    }

    private static let retirementQueue = DispatchQueue(label: "Peach.VLC.retirement", qos: .utility)
    private static let logSink = VLCPrivateLogSink()
    fileprivate static let installLogSink: Void = {
        VLCLibrary.shared().loggers = [logSink]
    }()

    init(url: URL, decoder: LocalOriginalDecoder, interactivePlayback: Bool = false) {
        _ = Self.installLogSink
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        let player = VLCMediaPlayer()
        player.drawable = view
        let media = VLCMedia(url: url)
        if decoder == .software { media?.addOption(":no-hw-dec") }
        // This binary is libVLC 3.0.23: it has no clock-master. A late PCR while
        // clock-jitter is left at 5000 ms takes ES_OUT_RESET_PCR, flushes the
        // pipeline and rebuffers. At 2x that stall is the frozen, late picture.
        // Time-stretch then spends the catch-up on scaletempo instead of frames.
        if interactivePlayback {
            media?.addOption(":network-caching=300")
            media?.addOption(":clock-jitter=0")
            media?.addOption(":no-audio-time-stretch")
        }
        player.media = media
        self.player = player
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
        player.rate = rate
        if shouldPlay, !playbackRequested {
            playbackRequested = true
            if didEnd {
                didEnd = false
                hasFrame = false
                position = 0
            }
            if !hasFrame { firstFrameDeadline = ContinuousClock.now + .seconds(15) }
            applyMute(to: player)
            player.play()
        } else if !shouldPlay, playbackRequested {
            playbackRequested = false
            firstFrameDeadline = nil
            player.pause()
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
        let retirement = VLCPlayerRetirement(player)
        Self.retirementQueue.async { retirement.stopAndReleaseWhenStopped() }
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
        let state = player.state
        let statistics = !hasFrame && state != .stopped ? player.media?.statistics : nil
        let displayedFrame = (statistics?.displayedPictures ?? 0) > 0
        let canRetryInSoftware = !displayedFrame && (statistics?.demuxReadBytes ?? 0) > 0
        if state == .error {
            fail("iPhone 无法打开原文件。请检查 Peach 连接和文件格式。", canRetryInSoftware: canRetryInSoftware)
            return
        }
        let milliseconds = player.time.intValue
        if milliseconds >= 0 {
            position = Double(milliseconds) / 1_000
        }
        let total = duration(of: player)
        if displayedFrame {
            hasFrame = true
            firstFrameDeadline = nil
        }
        if let deadline = firstFrameDeadline, ContinuousClock.now >= deadline {
            fail("原文件没有输出画面。", canRetryInSoftware: canRetryInSoftware)
            return
        }
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
        updateSeek(on: player)
        applyMute(to: player)
        onEvent?(.sample(position: reportingPosition, duration: total,
                        playing: playbackRequested && player.isPlaying && reportingPosition != nil,
                        hasFrame: hasFrame))
        updatePulse()
    }

    private func updateSeek(on player: VLCMediaPlayer) {
        guard var seek = pendingSeek else { return }
        let deadline = seek.deadline ?? (ContinuousClock.now + .seconds(8))
        seek.deadline = deadline
        if !seek.issued, player.isSeekable {
            seek.issued = true
            pendingSeek = seek
            player.time = VLCTime(int: seek.target)
            return
        }
        let reached = seek.issued && abs(position - Double(seek.target) / 1_000) < 1
        if reached || ContinuousClock.now >= deadline {
            pendingSeek = nil
            seek.completion(reached ? position : nil)
        } else {
            pendingSeek = seek
        }
    }

    private func cancelSeek() {
        let seek = pendingSeek
        pendingSeek = nil
        seek?.completion(nil)
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
        stop()
        onEvent?(.failed(message, canRetryInSoftware: canRetryInSoftware))
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
        let size = try await originalSize()
        try Task.checkCancellation()
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.thumbnailWidth = size.width
        thumbnailer.thumbnailHeight = size.height
        thumbnailer.snapshotTime = VLCTime(int: Int32((seconds * 1_000).rounded()))
        thumbnailer.preciseSeek = true
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
        pending?.resume(with: result)
    }
}

/// VLCKit stops asynchronously; keep the decoder alive until it finishes.
private final class VLCPlayerRetirement: @unchecked Sendable {
    private let player: VLCMediaPlayer
    private var stateObserver: NSObjectProtocol?
    private var didFinish = false

    init(_ player: VLCMediaPlayer) { self.player = player }

    func stopAndReleaseWhenStopped() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: VLCMediaPlayer.stateChangedNotification,
            object: player, queue: .main
        ) { [self] _ in
            finishIfStopped()
        }
        player.stop()
        finishIfStopped()
    }

    private func finishIfStopped() {
        DispatchQueue.main.async { [self] in
            guard !didFinish, player.state == .stopped else { return }
            didFinish = true
            if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
            stateObserver = nil
            player.media = nil
        }
    }
}

/// Do not let VLC write signed playback URLs to its default stderr logger.
private final class VLCPrivateLogSink: NSObject, VLCLogging {
    var level: VLCLogLevel = VLCLogLevel(rawValue: 3)!
    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {}
}
#endif
