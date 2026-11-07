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
    private var restoreCompletion: ((Bool) -> Void)?
    private var visible = false
    private var restoring = false

    init(api: PeachAPI, item: PeachItem, controller: PlaybackController? = nil, allowsScreenScrubbing: Bool = true) {
        self.api = api; self.item = item
        self.controller = controller ?? PlaybackController(api: api, item: item)
        self.allowsScreenScrubbing = allowsScreenScrubbing
        super.init()
        surface.playerLayer.videoGravity = .resizeAspect
        frameObserver = surface.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak controller = self.controller] layer, _ in
            guard layer.isReadyForDisplay, let player = layer.player else { return }
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
    }
    func appear() {
        visible = true; restoring = false
        restoreCompletion?(true); restoreCompletion = nil
        PlaybackSessions.shared.stopPrevious(except: self)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { message = error.localizedDescription }
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
        PlaybackSessions.shared.stopPrevious(except: self)
        PlaybackSessions.shared.retained = self
        controller.setPictureInPicture(true)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStarted?()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        if pictureInPictureController === vlcPiP { releaseVLCPiP() }
        controller.setPictureInPicture(false)
        message = error.localizedDescription
        if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        if visible { completionHandler(true); return }
        restoring = true; restoreCompletion = completionHandler
        PlaybackSessions.shared.restored = self
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
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
