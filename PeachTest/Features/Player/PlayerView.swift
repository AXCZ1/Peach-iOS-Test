import AVKit
import SwiftUI

enum PlayerDisplayMode { case standard, theater, fullscreen }

struct PlayerView: View {
    let item: PeachItem
    let api: PeachAPI
    var startsMuted = false
    var preserveOnExit = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: PlayerPresentation
    @StateObject private var model: PlaybackController
    @State private var displayMode: PlayerDisplayMode = .standard
    @State private var previousMode: PlayerDisplayMode = .standard
    @State private var toast: String?
    @State private var undoAction: SingleUseAction?
    @State private var toastID = UUID()
    @State private var feedbackBusy = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var gestureFeedback: String?
    @State private var feedbackID = UUID()
    @State private var controlsVisible = true

    init(item: PeachItem, api: PeachAPI, startsMuted: Bool = false) {
        let session = PlayerPresentation(api: api, item: item)
        session.controller.setMuted(startsMuted)
        self.init(session: session, startsMuted: startsMuted)
    }

    init(session: PlayerPresentation, startsMuted: Bool = false, preserveOnExit: Bool = false, initialMode: PlayerDisplayMode = .standard) {
        _displayMode = State(initialValue: initialMode)
        self.preserveOnExit = preserveOnExit
        self.item = session.item; self.api = session.api; self.startsMuted = startsMuted
        _session = StateObject(wrappedValue: session)
        _model = StateObject(wrappedValue: session.controller)
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 0) {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.player != nil {
                SessionVideoSurface(session: session)
                    .ignoresSafeArea(edges: displayMode == .fullscreen ? .all : [])
                MediaGestureOverlay(
                    onTap: { withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() } },
                    onDoubleTap: { fraction in showGesture(model.doubleTap(at: Double(fraction))) },
                    onSeekChanged: { _ in }, onSeekEnded: { _ in }, allowsHorizontalSeek: false,
                    onHoldBegan: { model.beginBoost() }, onHoldEnded: { model.endBoost() }
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

            if model.isBoosting {
                Text("2×").font(.headline.monospacedDigit()).foregroundStyle(.white)
                    .padding(12).background(.black.opacity(0.6), in: Capsule()).allowsHitTesting(false)
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
        .frame(height: displayMode == .fullscreen ? geometry.size.height :
            displayMode == .theater ? max(220, geometry.size.height - 44) : max(220, geometry.size.width * 9 / 16))
        if displayMode != .fullscreen {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title).font(.headline).foregroundStyle(.white)
                Text(item.performers.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                if displayMode == .standard { PreviewFilmstrip(api: api, item: item) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        }.scrollDisabled(displayMode == .fullscreen).background(Color.black)
        .overlay(alignment: .bottom) {
            if let toast { ToastBar(message: toast, undo: undoAction).padding(20) }
        }
        }
        .ignoresSafeArea(edges: displayMode == .fullscreen ? .all : [])
        .statusBarHidden(displayMode == .fullscreen)
        .persistentSystemOverlays(.hidden)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.activate()
        }
        .onAppear {
            session.appear()
            session.onPiPStarted = { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { session.disappear(keepPlayback: preserveOnExit) }
        .onChange(of: session.message) { _, message in if let message { showToast(message) } }
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
                Button { if !preserveOnExit { session.close() }; dismiss() } label: {
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

            VStack(spacing: 0) {
                PlaybackSeekBar(controller: model, api: api, item: item)
                HStack(spacing: 14) {
                    Spacer()
                    playerIcon(displayMode == .theater ? "rectangle.compress.vertical" : "rectangle.expand.vertical", label: "影院模式") {
                        model.endBoost()
                        displayMode = displayMode == .theater ? .standard : .theater
                    }
                    playerIcon("heart", label: "记一次高潮") { Task { await recordClimax() } }
                        .disabled(feedbackBusy)
                    playerIcon("pip.enter", label: "小窗播放") { session.startPiP() }
                        .opacity(session.pipPossible ? 1 : 0.45)
                    playerIcon(displayMode == .fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: "全屏") {
                        model.endBoost()
                        if displayMode == .fullscreen { displayMode = previousMode }
                        else { previousMode = displayMode; displayMode = .fullscreen }
                    }
                }.frame(height: 44)
            }.padding(.horizontal, 20).padding(.bottom, 8)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func playerIcon(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 18)).frame(width: 44, height: 44).foregroundStyle(.white) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func recordClimax() async {
        guard !feedbackBusy else { return }
        feedbackBusy = true
        defer { feedbackBusy = false }
        do {
            let result = try await api.feedback(id: item.id, kind: "o")
            showToast("已记录 · \(result.oCount ?? 0)", undo: {
                Task {
                    do {
                        _ = try await api.feedback(id: item.id, kind: "o-undo")
                        showToast("已撤销本次记录")
                    } catch { showToast("撤销失败：\(error.localizedDescription)") }
                }
            })
        } catch { showToast("记录失败：\(error.localizedDescription)") }
    }

    private func showToast(_ message: String, undo: (() -> Void)? = nil) {
        let token = UUID(); toastID = token; toast = message
        undoAction = undo.map { SingleUseAction($0) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastID == token { toast = nil; undoAction = nil }
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
