import AVKit
import SwiftUI

struct PlayerView: View {
    private enum PlaybackFeedback: Equatable {
        case toggle
        case seek(seconds: Int, forward: Bool)
    }

    let item: PeachItem
    let api: PeachAPI
    let preserveOnExit: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var session: PlayerPresentation
    @StateObject private var model: PlaybackController
    @StateObject private var orientation = PlaybackOrientation()
    @State private var toast: String?
    @State private var undoAction: SingleUseAction?
    @State private var toastID = UUID()
    @State private var feedbackBusy = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var gestureFeedback: String?
    @State private var feedbackID = UUID()
    @State private var feedback: PlaybackFeedback?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var tapSequence = PlaybackTapSequence()
    @State private var singleTapTask: Task<Void, Never>?
    @State private var skipAnchor = 0.0
    @State private var controlsVisible = true
    @State private var screenScrubOrigin: Double?
    @State private var dismissOffset: CGFloat = 0
    @State private var marks: [ClimaxMark] = []

    init(item: PeachItem, api: PeachAPI) {
        let controller = PlaybackController(api: api, item: item, usesIndependentVLCClock: true)
        self.init(session: PlayerPresentation(api: api, item: item, controller: controller))
    }

    init(session: PlayerPresentation, preserveOnExit: Bool = false) {
        self.preserveOnExit = preserveOnExit
        self.item = session.item; self.api = session.api
        _session = StateObject(wrappedValue: session)
        _model = StateObject(wrappedValue: session.controller)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.hasVideoSurface {
                SessionVideoSurface(session: session).ignoresSafeArea().offset(y: dismissOffset)
                screenGestures.ignoresSafeArea()
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
            if preserveOnExit, let gestureFeedback {
                Text(gestureFeedback).font(.headline).foregroundStyle(.white)
                    .padding(16).background(.black.opacity(0.5), in: Capsule())
                    .allowsHitTesting(false)
            }
            if !preserveOnExit, model.phase == .ready {
                playbackFeedback
            }
            if controlsVisible || screenScrubOrigin != nil {
                chrome
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast { ToastBar(message: toast, undo: undoAction).padding(20) }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.activate()
        }
        .onAppear {
            marks = ClimaxMarks.local.list(origin: api.baseURL, item: item)
            session.appear()
            session.onPiPStarted = { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                screenScrubOrigin = nil; dismissOffset = 0
                resetTapSequence()
                feedbackTask?.cancel()
                feedback = nil
            }
            model.setActive(phase == .active)
        }
        .onDisappear {
            resetTapSequence()
            feedbackTask?.cancel()
            orientation.restore()
            session.disappear(keepPlayback: preserveOnExit)
        }
        .onChange(of: session.message) { _, message in if let message { showToast(message) } }
        .onChange(of: model.isScrubbing) { _, scrubbing in
            if scrubbing { resetTapSequence() }
        }
        .onChange(of: model.isPlaying) { _, playing in
            guard playing else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private var screenGestures: some View {
        GeometryReader { geometry in
            screenGestureLayer(width: geometry.size.width)
        }
    }

    private func screenGestureLayer(width: CGFloat) -> some View {
        let dragScale: Double = preserveOnExit ? 0.5 : 0.05
        let timeForDrag: (CGFloat, Double) -> Double = { dx, origin in
            origin + Double(dx / max(1, width)) * model.duration * dragScale
        }
        var overlay = MediaGestureOverlay(
            onTap: { toggleControls() },
            onDoubleTap: { fraction in showGesture(model.doubleTap(at: Double(fraction))) },
            onSeekChanged: { dx in
                if let origin = screenScrubOrigin { model.previewSeek(timeForDrag(dx, origin)) }
            },
            onSeekEnded: { dx in
                guard let origin = screenScrubOrigin else { return }
                screenScrubOrigin = nil
                model.endScrubbing(at: timeForDrag(dx, origin))
            },
            allowsHorizontalSeek: session.allowsScreenScrubbing && model.phase == .ready && model.duration > 0,
            onSeekBegan: {
                guard !model.isScrubbing else { return }
                resetTapSequence()
                screenScrubOrigin = model.currentTime
                model.beginScrubbing(pausesPlayback: preserveOnExit)
                model.previewSeek(model.currentTime)
            },
            onSeekCancelled: {
                guard screenScrubOrigin != nil else { return }
                screenScrubOrigin = nil
                model.cancelScrubbing()
            },
            onHoldBegan: { resetTapSequence(); model.beginBoost() }, onHoldEnded: { model.endBoost() },
            allowsDownwardDismiss: !preserveOnExit && !orientation.landscape && verticalSizeClass != .compact,
            onDismissChanged: { offset in
                if dismissOffset == 0 { resetTapSequence() }
                dismissOffset = offset
            },
            onDismissEnded: { close in
                if close { closePlayer() }
                else { withAnimation(.snappy) { dismissOffset = 0 } }
            }
        )
        if !preserveOnExit {
            overlay.onTimedTap = { fraction, timestamp in handleTimedTap(fraction, timestamp) }
            overlay.holdDuration = 0.25
        }
        return overlay
            .accessibilityElement()
            .accessibilityLabel("视频画面")
            .accessibilityAction(named: "播放或暂停") { model.togglePlayback() }
            .accessibilityAction(named: "前进 10 秒") { model.skip(by: 10) }
            .accessibilityAction(named: "后退 10 秒") { model.skip(by: -10) }
    }

    private var playbackFeedback: some View {
        GeometryReader { geometry in
            let center = geometry.size.width / 2
            if model.isPausedByUser || feedback == .toggle {
                feedbackSymbol(model.isPausedByUser ? "pause.fill" : "play.fill")
                    .position(x: center, y: geometry.size.height / 2)
            }
            if case .seek(let seconds, let forward) = feedback {
                VStack(spacing: 4) {
                    feedbackSymbol(forward ? "goforward" : "gobackward")
                    Text(seconds > 0 ? "+\(seconds)" : "\(seconds)")
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .position(x: geometry.size.width * (forward ? 0.875 : 0.125), y: geometry.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func feedbackSymbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 42, weight: .semibold)).foregroundStyle(.white)
    }

    private func handleTimedTap(_ fraction: CGFloat, _ timestamp: TimeInterval) {
        guard !model.isScrubbing else { return }
        singleTapTask?.cancel()
        switch tapSequence.register(PlaybackTap.action(at: Double(fraction)), at: timestamp) {
        case .wait(let deadline, let showPreviousSingle):
            if showPreviousSingle { toggleControls() }
            singleTapTask = Task { @MainActor in
                let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                tapSequence.finishSingle()
                singleTapTask = nil
                toggleControls()
            }
        case .togglePlayback:
            model.togglePlayback()
            showPlaybackFeedback(.toggle)
        case .seek(let offset, let startsSequence):
            if startsSequence { skipAnchor = model.currentTime }
            // Seek callbacks may still be reporting the old position during rapid taps.
            model.seek(to: skipAnchor + offset)
            let seconds = Int((model.currentTime - skipAnchor).rounded())
            showPlaybackFeedback(.seek(seconds: seconds, forward: offset > 0))
        }
    }

    private func resetTapSequence() {
        singleTapTask?.cancel()
        singleTapTask = nil
        tapSequence.finishSingle()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }
    }

    private func showPlaybackFeedback(_ value: PlaybackFeedback) {
        feedbackTask?.cancel()
        feedback = value
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            feedback = nil
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
                Button(action: closePlayer) {
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

            Group {
                if verticalSizeClass == .compact, !preserveOnExit {
                    HStack(spacing: 8) {
                        PlaybackSeekBar(controller: model, api: api, item: item, inlineTimes: true,
                                        usesLocalSeekThumbnails: true, marks: marks, pausesPlaybackWhileDragging: false)
                        HStack(spacing: 6) { playbackActions }
                    }.padding(.bottom, 2)
                } else {
                    VStack(spacing: 0) {
                        PlaybackSeekBar(controller: model, api: api, item: item,
                                        usesLocalSeekThumbnails: !preserveOnExit, marks: preserveOnExit ? [] : marks,
                                        pausesPlaybackWhileDragging: preserveOnExit)
                        HStack(spacing: 14) {
                            Spacer()
                            playbackActions
                        }.frame(height: 44)
                    }.padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 20)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
        .offset(y: dismissOffset)
    }

    private func closePlayer() {
        if !preserveOnExit { session.close() }
        dismiss()
    }

    @ViewBuilder private var playbackActions: some View {
        playerIcon("heart", label: "记一次高潮") {
            let position = model.climaxPosition
            Task { await recordClimax(at: position) }
        }
            .disabled(feedbackBusy)
        playerIcon("pip.enter", label: "小窗播放") { session.startPiP() }
            .opacity(session.canStartPiP ? 1 : 0.45)
        playerIcon(orientation.landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                   label: orientation.landscape ? "返回竖屏" : "横屏全屏") {
            model.endBoost()
            orientation.toggle { showToast("屏幕切换失败：\($0)") }
        }
    }

    private func playerIcon(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 18)).frame(width: 44, height: 44).foregroundStyle(.white) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func recordClimax(at position: Double?) async {
        guard !feedbackBusy else { return }
        feedbackBusy = true
        defer { feedbackBusy = false }
        do {
            let (count, mark) = try await ClimaxMarks.local.record(api: api, item: item, at: position)
            marks = ClimaxMarks.local.list(origin: api.baseURL, item: item)
            showToast("已记录 · \(count)", undo: {
                Task {
                    do {
                        _ = try await ClimaxMarks.local.undo(api: api, item: item, mark: mark)
                        marks = ClimaxMarks.local.list(origin: api.baseURL, item: item)
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

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
