import SwiftUI

struct PlayerControlsVisibility {
    var visible = true
    private(set) var activity = 0

    mutating func noteActivity() { activity &+= 1 }

    mutating func show() {
        visible = true
        noteActivity()
    }
}

/// Shared player layout. The host owns playback and chooses the actions.
struct PlayerControls: View {
    @ObservedObject var session: PlayerPresentation
    @ObservedObject var model: PlaybackController
    @ObservedObject var orientation: PlaybackOrientation
    @Binding var visibility: PlayerControlsVisibility
    @Environment(\.scenePhase) private var scenePhase
    let fullscreen: Bool
    var preserveOnExit = false
    var keepVisibleDuringWallScrub = false
    var pausesFullscreenPlaybackWhileDragging = false
    let marks: [ClimaxMark]
    let feedbackBusy: Bool
    let onClose: () -> Void
    let onRecord: () -> Void
    let onRotate: () -> Void
    let onPiP: () -> Void

    private var item: PeachItem { session.item }
    private var api: PeachAPI { session.api }
    private var interacting: Bool { model.isScrubbing || model.isBoosting }

    private var showsChrome: Bool {
        if preserveOnExit { return visibility.visible || keepVisibleDuringWallScrub }
        return !fullscreen || visibility.visible || model.isScrubbing
    }

    private var hideAfterActivity: Int? {
        guard fullscreen, visibility.visible, !interacting, scenePhase == .active else { return nil }
        return visibility.activity
    }

    var body: some View {
        let activity = hideAfterActivity
        Group {
            if showsChrome {
                chrome.transition(.opacity)
            }
        }
        .task(id: activity) {
            guard let activity else { return }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled, visibility.activity == activity, !interacting else { return }
            withAnimation(.easeInOut(duration: 0.18)) { visibility.visible = false }
        }
    }

    private func interaction() {
        if fullscreen { visibility.show() }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: onClose) {
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
                Button {
                    interaction()
                    model.setMuted(!model.isMuted)
                } label: {
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
                if fullscreen {
                    HStack(spacing: 8) {
                        PlaybackSeekBar(controller: model, api: api, item: item, inlineTimes: true,
                                        usesLocalSeekThumbnails: true, marks: marks,
                                        pausesPlaybackWhileDragging: pausesFullscreenPlaybackWhileDragging,
                                        onInteraction: interaction)
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
    }

    private var playbackActions: some View {
        Group {
            playerIcon("heart", label: "记一次高潮", action: onRecord)
                .disabled(feedbackBusy)
            playerIcon("pip.enter", label: "小窗播放", action: onPiP)
                .opacity(session.canStartPiP ? 1 : 0.45)
            playerIcon(orientation.landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       label: orientation.landscape ? "返回竖屏" : "横屏全屏", action: onRotate)
        }
    }

    private func playerIcon(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            interaction()
            action()
        } label: {
            let icon = Image(systemName: name).font(.system(size: 18))
                .frame(width: 44, height: 44).foregroundStyle(.white)
            if fullscreen { icon.contentShape(Rectangle()) }
            else { icon }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
