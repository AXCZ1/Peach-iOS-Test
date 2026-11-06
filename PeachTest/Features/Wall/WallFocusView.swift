import SwiftUI

/// Expanded wall tile. The web wall grows one card to a 6×6 gear and moves the
/// other eleven around it; on the phone the focused item takes the screen and
/// the wall remains behind a dimmed backdrop. Controls mirror the web focus
/// panel: play, watch later, sound, detail and close.
struct WallFocusView: View {
    let api: PeachAPI
    let item: PeachItem
    let muted: Bool
    let onClose: () -> Void
    let onPlay: () -> Void
    let onLater: () -> Void
    let onMute: () -> Void
    let onDetail: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("收起作品")
                    Spacer()
                    if item.watchLater {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(PeachTheme.coral)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer(minLength: 8)

                RemoteImage(url: api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey))
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                            .font(.system(size: 21, weight: .bold).monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        Text(item.durationText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text(item.title)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                    Text(item.performers.isEmpty ? (item.studio ?? "未归属") : item.performers.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    if item.progress > 0 {
                        ProgressView(value: item.progress)
                            .tint(PeachTheme.coral)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 10)

                HStack(spacing: 10) {
                    Button { onPlay() } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 58, height: 58)
                            .background(PeachTheme.coral, in: Circle())
                    }
                    .accessibilityLabel("播放")
                    focusButton(item.watchLater ? "bookmark.fill" : "bookmark", title: item.watchLater ? "移出稍后看" : "稍后看", action: onLater)
                    focusButton(muted ? "speaker.slash" : "speaker.wave.2", title: muted ? "静音" : "有声", action: onMute)
                    focusButton("info.circle", title: "详情", action: onDetail)
                }
                .padding(.bottom, 26)
            }
        }
    }

    private func focusButton(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.1), in: Circle())
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
