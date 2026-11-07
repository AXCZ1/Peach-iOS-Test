import SwiftUI

struct WallFocusView: View {
    @ObservedObject var session: PlayerPresentation
    @ObservedObject private var controller: PlaybackController
    let showsVideo: Bool
    let onClose: () -> Void
    let onFullScreen: () -> Void
    init(session: PlayerPresentation, showsVideo: Bool, onClose: @escaping () -> Void, onFullScreen: @escaping () -> Void) {
        self.session = session; self.controller = session.controller
        self.showsVideo = showsVideo
        self.onClose = onClose; self.onFullScreen = onFullScreen
    }
    var body: some View {
        ZStack {
            Color.black
            if showsVideo, controller.hasVideoSurface { SessionVideoSurface(session: session) }
            MediaGestureOverlay(onTap: { controller.togglePlayback() },
                onDoubleTap: { _ = controller.doubleTap(at: Double($0)) },
                onSeekChanged: { _ in }, onSeekEnded: { _ in }, allowsHorizontalSeek: false,
                onHoldBegan: { controller.beginBoost() }, onHoldEnded: { controller.endBoost() })
            if controller.phase == .preparing { ProgressView().tint(.white).allowsHitTesting(false) }
            if case .failed(let message) = controller.phase { Text(message).font(.caption).foregroundStyle(.white).padding() }
            VStack {
                HStack { Spacer(); button("xmark", "收起", onClose) }
                Spacer()
                if controller.isBoosting { Text("2×").foregroundStyle(.white).allowsHitTesting(false) }
                HStack {
                    button(controller.isPlaying ? "pause.fill" : "play.fill", "播放或暂停") { controller.togglePlayback() }
                    Spacer()
                    button("arrow.up.left.and.arrow.down.right", "打开播放器", onFullScreen)
                }
                PlaybackSeekBar(controller: controller, api: session.api, item: session.item)
            }.padding(12)
        }
        .task { session.appear(); await controller.activate() }
    }
    private func button(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44).foregroundStyle(.white).background(.black.opacity(0.55), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
