import SwiftUI
import UIKit

@MainActor
final class PeachAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let scene = window?.windowScene, PlaybackOrientation.owner?.scene === scene else { return .allButUpsideDown }
        return .landscape
    }
}

@MainActor
final class PlaybackOrientation: ObservableObject {
    fileprivate static weak var owner: PlaybackOrientation?
    fileprivate weak var scene: UIWindowScene?
    weak var playbackWindow: UIWindow?
    @Published private(set) var landscape = false
    private var previous: UIInterfaceOrientationMask = .portrait

    func toggle(onError: @escaping (String) -> Void) {
        if landscape {
            release(to: .portrait, onError: onError)
            return
        }
        guard let scene = playbackWindow?.windowScene ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) }) else {
            onError("播放器窗口尚未准备好")
            return
        }
        self.scene = scene
        let orientation: UIInterfaceOrientation
        if #available(iOS 26.0, *) { orientation = scene.effectiveGeometry.interfaceOrientation }
        else { orientation = scene.interfaceOrientation }
        previous = orientation == .landscapeLeft ? .landscapeLeft : orientation == .landscapeRight ? .landscapeRight : .portrait
        Self.owner = self
        landscape = true
        PeachRuntimeLogger.shared.log("请求切换横屏播放", level: .info, category: "orientation", source: "PlaybackOrientation")
        request(orientation.isLandscape ? previous : .landscapeRight, in: scene) { [weak self] error in
            guard let self, Self.owner === self else { return }
            Self.owner = nil
            self.landscape = false
            self.updateControllers(in: scene)
            PeachRuntimeLogger.shared.log("切换横屏失败: \(error.localizedDescription)", level: .error, category: "orientation", source: "PlaybackOrientation")
            onError(error.localizedDescription)
        }
    }

    func restore() { release(to: previous, onError: { _ in }) }

    private func release(to mask: UIInterfaceOrientationMask, onError: @escaping (String) -> Void) {
        guard Self.owner === self, let scene else { return }
        Self.owner = nil
        landscape = false
        PeachRuntimeLogger.shared.log("恢复页面方向 mask=\(mask.rawValue)", level: .debug, category: "orientation", source: "PlaybackOrientation")
        request(mask, in: scene) { error in
            PeachRuntimeLogger.shared.log("恢复页面方向失败: \(error.localizedDescription)", level: .warning, category: "orientation", source: "PlaybackOrientation")
            onError(error.localizedDescription)
        }
    }

    private func request(_ mask: UIInterfaceOrientationMask, in scene: UIWindowScene, onError: @escaping (Error) -> Void) {
        updateControllers(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask), errorHandler: onError)
    }

    private func updateControllers(in scene: UIWindowScene) {
        var controller = (playbackWindow ?? scene.windows.first(where: \.isKeyWindow))?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
    }
}

struct PlaybackWindowAnchor: UIViewRepresentable {
    let orientation: PlaybackOrientation

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.orientation = orientation
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.orientation = orientation
        if let window = view.window { orientation.playbackWindow = window }
    }

    final class Anchor: UIView {
        weak var orientation: PlaybackOrientation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { orientation?.playbackWindow = window }
        }
    }
}
