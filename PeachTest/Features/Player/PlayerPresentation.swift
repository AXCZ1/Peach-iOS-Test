import AVKit
import SwiftUI
import Combine

@MainActor
final class PlaybackSessions: ObservableObject {
    static let shared = PlaybackSessions()
    @Published var restored: PlayerPresentation?
    @Published var retained: PlayerPresentation?
    func stopPrevious(except session: PlayerPresentation) {
        guard let previous = retained, previous !== session else { return }
        previous.close(); retained = nil
    }
}

@MainActor
final class PlayerPresentation: NSObject, ObservableObject, Identifiable, AVPictureInPictureControllerDelegate {
    let id = UUID()
    let api: PeachAPI
    let item: PeachItem
    let controller: PlaybackController
    let allowsScreenScrubbing: Bool
    let surface = PlayerLayerView()
    @Published private(set) var pipPossible = false
    @Published var message: String?
    var onPiPStarted: (() -> Void)?
    private var pip: AVPictureInPictureController?
    private var vlcPiP: AVPictureInPictureController?
    private var vlcPiPStart: Task<Void, Never>?
    private var vlcPiPState: AnyCancellable?
    private var possibleObserver: NSKeyValueObservation?
    private var frameObserver: NSKeyValueObservation?
    private var playerObserver: AnyCancellable?
    private var notificationTokens: [NotificationToken] = []
    private var restoreCompletion: ((Bool) -> Void)?
    private var visible = false
    private var restoring = false

    init(api: PeachAPI, item: PeachItem, controller: PlaybackController? = nil, allowsScreenScrubbing: Bool = true) {
        self.api = api; self.item = item
        self.controller = controller ?? PlaybackController(api: api, item: item)
        self.allowsScreenScrubbing = allowsScreenScrubbing
        super.init()
        let itemID = item.id
        surface.playerLayer.videoGravity = .resizeAspect
        frameObserver = surface.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak controller = self.controller] layer, _ in
            let ready = layer.isReadyForDisplay
            PeachRuntimeLogger.shared.log(
                "AVPlayerLayer isReadyForDisplay=\(ready) id=\(itemID)",
                level: ready ? .info : .debug,
                category: "player.avplayer",
                source: "AVPlayerLayer"
            )
            guard ready, let player = layer.player else { return }
            Task { @MainActor in controller?.noteDisplayedFrame(for: player) }
        }
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: surface.playerLayer)
            pip?.delegate = self
            pip?.canStartPictureInPictureAutomaticallyFromInline = false
            possibleObserver = pip?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
                let possible = pip.isPictureInPicturePossible
                Task { @MainActor in self?.pipPossible = possible }
            }
        }
        playerObserver = self.controller.$player.sink { [weak self] player in
            self?.surface.playerLayer.player = player
        }
        notificationTokens.append(NotificationToken(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            PeachRuntimeLogger.shared.log(
                "AVAudioSession 中断事件 type=\(rawType.map(String.init) ?? "unknown") id=\(itemID)",
                level: .warning,
                category: "player.audio",
                source: "AVAudioSession"
            )
        }))
        notificationTokens.append(NotificationToken(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
            PeachRuntimeLogger.shared.log(
                "AVAudioSession 音频路由变化 reason=\(reason.map(String.init) ?? "unknown") outputs=\(outputs) id=\(itemID)",
                level: .debug,
                category: "player.audio",
                source: "AVAudioSession"
            )
        }))
    }
    func appear() {
        visible = true; restoring = false
        restoreCompletion?(true); restoreCompletion = nil
        PlaybackSessions.shared.stopPrevious(except: self)
        PeachRuntimeLogger.shared.log("PlayerPresentation appear id=\(item.id)", level: .info, category: "player.ui", source: "PlayerPresentation")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            PeachRuntimeLogger.shared.log("AVAudioSession 激活失败: \(error.localizedDescription)", level: .error, category: "player.audio", source: "PlayerPresentation")
            message = error.localizedDescription
        }
    }
    func disappear(keepPlayback: Bool = false) {
        visible = false
        onPiPStarted = nil
        if !controller.isPiPActive {
            releaseVLCPiP()
            if !restoring && !keepPlayback { controller.stop() }
        }
    }
    var canStartPiP: Bool {
        if controller.localPlayer != nil {
            return controller.phase == .ready && AVPictureInPictureController.isPictureInPictureSupported()
        }
        return pipPossible
    }
    func startPiP() {
        controller.endBoost()
        if let player = controller.localPlayer as? VLCOriginalPlayer {
            startVLCPiP(player)
            return
        }
        guard let pip, pip.isPictureInPicturePossible else {
            message = "当前视频尚不能进入画中画"; return
        }
        pip.startPictureInPicture()
    }
    private func startVLCPiP(_ player: VLCOriginalPlayer) {
        guard vlcPiP == nil else { return }
        guard canStartPiP, let layer = player.pictureInPictureLayer else {
            message = "当前视频尚不能进入画中画"; return
        }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = !player.isSeekable
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        vlcPiP = pip
        vlcPiPState = controller.$localPlayer.combineLatest(controller.$isPlaying, controller.$duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak pip] backend, _, _ in
                guard let self, let pip, self.vlcPiP === pip else { return }
                if backend != nil { pip.invalidatePlaybackState() }
                else { self.stopVLCPiP() }
            }

        // AVKit may publish readiness after the content source is attached.
        vlcPiPStart = Task { [weak self, weak pip] in
            let deadline = ContinuousClock.now + .seconds(2)
            while !Task.isCancelled, let pip {
                if pip.isPictureInPicturePossible {
                    pip.invalidatePlaybackState()
                    pip.startPictureInPicture()
                    return
                }
                if ContinuousClock.now >= deadline {
                    self?.message = "当前视频尚不能进入画中画"
                    self?.releaseVLCPiP()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    private func releaseVLCPiP() {
        vlcPiPStart?.cancel(); vlcPiPStart = nil
        vlcPiPState = nil
        vlcPiP?.delegate = nil
        vlcPiP = nil
    }
    private func stopVLCPiP() {
        guard let vlcPiP else { return }
        if vlcPiP.isPictureInPictureActive {
            vlcPiP.stopPictureInPicture()
        } else {
            releaseVLCPiP()
            if controller.isPiPActive { controller.setPictureInPicture(false) }
            if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
        }
    }
    func close() {
        pip?.stopPictureInPicture()
        stopVLCPiP()
        controller.stop()
        if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        PeachRuntimeLogger.shared.log("PiP 即将启动 id=\(item.id) backend=\(pictureInPictureController === vlcPiP ? "vlc" : "avplayer")", level: .info, category: "player.pip", source: "PlayerPresentation")
        PlaybackSessions.shared.stopPrevious(except: self)
        PlaybackSessions.shared.retained = self
        controller.setPictureInPicture(true)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        PeachRuntimeLogger.shared.log("PiP 已启动 id=\(item.id)", level: .info, category: "player.pip", source: "PlayerPresentation")
        onPiPStarted?()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        PeachRuntimeLogger.shared.log("PiP 启动失败 id=\(item.id): \(error.localizedDescription)", level: .error, category: "player.pip", source: "PlayerPresentation")
        if pictureInPictureController === vlcPiP { releaseVLCPiP() }
        controller.setPictureInPicture(false)
        message = error.localizedDescription
        if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        PeachRuntimeLogger.shared.log("PiP 恢复全屏界面 id=\(item.id) visible=\(visible)", level: .info, category: "player.pip", source: "PlayerPresentation")
        if visible { completionHandler(true); return }
        restoring = true; restoreCompletion = completionHandler
        PlaybackSessions.shared.restored = self
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        PeachRuntimeLogger.shared.log("PiP 已停止 id=\(item.id) visible=\(visible) restoring=\(restoring)", level: .info, category: "player.pip", source: "PlayerPresentation")
        if pictureInPictureController === vlcPiP { releaseVLCPiP() }
        controller.setPictureInPicture(false)
        if !visible && !restoring { controller.stop() }
        if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
    }
}

extension PlayerPresentation: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if playing { controller.resume() } else { controller.pause() }
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        !controller.isPlaying
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        let duration = controller.duration
        guard duration.isFinite, duration > 0 else {
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        // The VLC renderer timestamps samples against the host clock, not media time.
        let time = controller.localPlayer?.reportingPosition ?? controller.currentTime
        let start = CMTime(seconds: CACurrentMediaTime() - time, preferredTimescale: 1_000)
        return CMTimeRange(start: start, duration: CMTime(seconds: duration, preferredTimescale: 1_000))
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime, completion completionHandler: @escaping @Sendable () -> Void) {
        let interval = skipInterval.seconds
        guard interval.isFinite else { completionHandler(); return }
        controller.seek(to: controller.currentTime + interval) { [weak pictureInPictureController] in
            pictureInPictureController?.invalidatePlaybackState()
            completionHandler()
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
}

struct SessionVideoSurface: UIViewRepresentable {
    let drawable: UIView

    init(session: PlayerPresentation) {
        drawable = (session.controller.localPlayer as? VLCOriginalPlayer)?.view ?? session.surface
    }

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ host: UIView, context: Context) {
        guard drawable.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        drawable.frame = host.bounds
        drawable.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(drawable)
    }
}

private final class NotificationToken: @unchecked Sendable {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
