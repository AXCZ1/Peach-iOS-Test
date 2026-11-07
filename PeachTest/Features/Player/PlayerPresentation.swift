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
    let surface = PlayerLayerView()
    @Published private(set) var pipPossible = false
    @Published var message: String?
    var onPiPStarted: (() -> Void)?
    private var pip: AVPictureInPictureController?
    private var possibleObserver: NSKeyValueObservation?
    private var playerObserver: AnyCancellable?
    private var restoreCompletion: ((Bool) -> Void)?
    private var visible = false
    private var restoring = false

    init(api: PeachAPI, item: PeachItem, controller: PlaybackController? = nil) {
        self.api = api; self.item = item
        self.controller = controller ?? PlaybackController(api: api, item: item, preferOriginal: true)
        super.init()
        surface.playerLayer.videoGravity = .resizeAspect
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
        if !controller.isPiPActive && !restoring && !keepPlayback { controller.stop() }
    }
    func startPiP() {
        controller.endBoost()
        guard let pip, pip.isPictureInPicturePossible else {
            message = "当前视频尚不能进入画中画"; return
        }
        pip.startPictureInPicture()
    }
    func close() {
        pip?.stopPictureInPicture()
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
        controller.setPictureInPicture(false)
        if !visible && !restoring { controller.stop() }
        if PlaybackSessions.shared.retained === self { PlaybackSessions.shared.retained = nil }
    }
}

struct SessionVideoSurface: UIViewRepresentable {
    let session: PlayerPresentation
    func makeUIView(context: Context) -> PlayerLayerView { session.surface }
    func updateUIView(_ view: PlayerLayerView, context: Context) {}
}
