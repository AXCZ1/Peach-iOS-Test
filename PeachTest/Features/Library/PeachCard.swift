import SwiftUI

struct PeachCard: View {
    let item: PeachItem
    let api: PeachAPI

    private var coverURL: URL? {
        guard item.hasCover else { return nil }
        return api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: coverURL)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 9))
                    Text(item.durationText).font(.caption2.monospacedDigit().weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
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
}
