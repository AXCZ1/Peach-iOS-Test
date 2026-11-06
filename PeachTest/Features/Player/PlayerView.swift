import AVKit
import SwiftUI

struct PlayerView: View {
    let item: PeachItem
    let api: PeachAPI
    var startsMuted = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @State private var gestureFeedback: String?
    @State private var feedbackID = UUID()
    @State private var controlsVisible = true

    init(item: PeachItem, api: PeachAPI, startsMuted: Bool = false) {
        self.item = item
        self.api = api
        self.startsMuted = startsMuted
        _model = StateObject(wrappedValue: PlaybackController(api: api, item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = model.player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
                MediaGestureOverlay(
                    onTap: { withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() } },
                    onDoubleTap: { fraction in showGesture(model.doubleTap(at: Double(fraction))) },
                    onSeekChanged: { _ in }, onSeekEnded: { _ in }, allowsHorizontalSeek: false
                )
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("视频画面")
                .accessibilityAction(named: "播放或暂停") { model.togglePlayback() }
                .accessibilityAction(named: "前进 10 秒") { model.skip(by: 10) }
                .accessibilityAction(named: "后退 10 秒") { model.skip(by: -10) }
            }

            switch model.phase {
            case .preparing:
                loading
            case .failed(let message):
                failure(message)
            case .ready:
                EmptyView()
            }

            if let gestureFeedback {
                Text(gestureFeedback).font(.headline).foregroundStyle(.white)
                    .padding(16).background(.black.opacity(0.5), in: Capsule())
                    .allowsHitTesting(false)
            }
            if controlsVisible {
                chrome
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.activate()
        }
        .onAppear { model.setMuted(startsMuted) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.stop() }
        .onChange(of: model.isPlaying) { _, playing in
            guard playing else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(PeachTheme.coral).scaleEffect(1.2)
            Text("正在连接播放源…").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(PeachTheme.coral)
            Text("无法播放")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(PeachTheme.coral)
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("关闭播放")
                Spacer()
                VStack(spacing: 2) {
                    Text(item.displayNumber.isEmpty ? "Peach" : item.displayNumber)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                    if let note = model.formatNote {
                        Text(note).font(.system(size: 9)).foregroundStyle(.white.opacity(0.38))
                    }
                }
                Spacer()
                Button { model.setMuted(!model.isMuted) } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel(model.isMuted ? "打开声音" : "静音")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            PlaybackSeekBar(controller: model, api: api, item: item)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func showGesture(_ message: String) {
        let identifier = UUID()
        feedbackID = identifier
        gestureFeedback = message
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if feedbackID == identifier { gestureFeedback = nil }
        }
    }

}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
