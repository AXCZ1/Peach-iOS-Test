import AVKit
import SwiftUI

struct PlayerView: View {
    let item: PeachItem
    let api: PeachAPI
    var startsMuted = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlaybackController
    @State private var scrubValue = 0.0
    @State private var scrubbing = false
    @State private var controlsVisible = true
    private let seekSeconds: Double

    init(item: PeachItem, api: PeachAPI, startsMuted: Bool = false) {
        self.item = item
        self.api = api
        self.startsMuted = startsMuted
        let stored = UserDefaults.standard.double(forKey: "peach.seek.seconds")
        seekSeconds = stored >= 1 ? stored : 10
        _model = StateObject(wrappedValue: PlaybackController(api: api, item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = model.player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() } }
            }

            switch model.phase {
            case .preparing:
                loading
            case .failed(let message):
                failure(message)
            case .ready:
                EmptyView()
            }

            if controlsVisible {
                chrome
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            model.setMuted(startsMuted)
            await model.start()
        }
        .onDisappear { model.stop() }
        .onChange(of: model.currentTime) { _, value in
            if !scrubbing { scrubValue = value }
        }
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

            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    Button { model.skip(by: -seekSeconds) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 24, weight: .medium))
                    }
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .frame(width: 64, height: 64)
                            .background(PeachTheme.coral, in: Circle())
                            .foregroundStyle(.black)
                    }
                    Button { model.skip(by: seekSeconds) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 24, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Text(clock(scrubbing ? scrubValue : model.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: $scrubValue, in: 0...max(model.duration, 1)) { editing in
                        scrubbing = editing
                        if editing { model.beginScrubbing() }
                        else { model.endScrubbing(at: scrubValue) }
                    }
                    .tint(PeachTheme.coral)
                    .accessibilityLabel("播放进度")
                    Text(clock(model.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 50, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
