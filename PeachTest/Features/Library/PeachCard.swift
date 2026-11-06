import SwiftUI

struct PeachCard: View {
    let item: PeachItem
    let api: PeachAPI
    var density: PeachDensity = .big

    private var coverURL: URL? {
        guard item.hasCover else { return nil }
        return api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey)
    }

    var body: some View {
        if density == .big {
            bigCard
        } else {
            denseCard
        }
    }

    private var bigCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: coverURL)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                statusBadges
                    .padding(8)

                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 9))
                    Text(item.durationText).font(.caption2.monospacedDigit().weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.displayNumber.isEmpty ? "—" : item.displayNumber)
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(PeachTheme.coral)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let resolution = item.resolution {
                        Text(resolution)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                    }
                }
                Text(item.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                if !item.performers.isEmpty {
                    Text(item.performers.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                } else if let studio = item.studio, !studio.isEmpty {
                    Text(studio)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.card.\(item.id)")
        .accessibilityLabel("\(item.displayNumber)，\(item.title)")
    }

    private var denseCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: coverURL)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                if item.progress > 0 {
                    Rectangle()
                        .fill(PeachTheme.coral)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: CGFloat(item.progress), anchor: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                if item.watchLater || item.isFlagged {
                    HStack(spacing: 3) {
                        if item.watchLater { Image(systemName: "bookmark.fill") }
                        if item.isFlagged { Image(systemName: "heart.fill") }
                    }
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            Text(item.displayNumber.isEmpty ? item.title : item.displayNumber)
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            if !item.performers.isEmpty {
                Text(item.performers.prefix(1).joined())
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.card.\(item.id)")
    }

    private var statusBadges: some View {
        HStack(spacing: 4) {
            if item.watchLater {
                badge("bookmark.fill", color: .white)
            }
            if item.isFlagged {
                badge("heart.fill", color: PeachTheme.coral)
            }
        }
    }

    private func badge(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(5)
            .background(.black.opacity(0.5), in: Circle())
    }
}
