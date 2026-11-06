import SwiftUI

struct ItemDetailView: View {
    let item: PeachItem
    let api: PeachAPI
    @StateObject private var model: ItemDetailModel
    @State private var playerPresented = false

    init(item: PeachItem, api: PeachAPI) {
        self.item = item
        self.api = api
        _model = StateObject(wrappedValue: ItemDetailModel(api: api, item: item))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                metadata
            }
            .padding(.bottom, 40)
        }
        .background(PeachTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load() }
        .fullScreenCover(isPresented: $playerPresented) {
            if let current = model.item {
                PlayerView(item: current, api: api)
            }
        }
    }

    private var current: PeachItem { model.item ?? item }

    private var coverURL: URL? {
        guard current.hasCover else { return nil }
        return api.coverURL(code: current.coverKey.isEmpty ? current.displayNumber : current.coverKey)
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: coverURL)
                .aspectRatio(16 / 9, contentMode: .fit)
            LinearGradient(colors: [.clear, PeachTheme.background], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            Button {
                playerPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("播放").font(.headline)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(PeachTheme.coral, in: Capsule())
                .shadow(color: PeachTheme.coral.opacity(0.35), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)
            .accessibilityIdentifier("detail.play")
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if !current.displayNumber.isEmpty {
                        Text(current.displayNumber)
                            .font(.caption.weight(.bold).monospaced())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PeachTheme.coral, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if let studio = current.studio, !studio.isEmpty {
                        Text(studio)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                Text(current.title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.title")
                if let original = current.originalTitle, !original.isEmpty, original != current.title {
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            HStack(spacing: 0) {
                spec("时长", current.durationText)
                divider
                spec("画质", current.resolution ?? "未知")
                divider
                spec("大小", current.sizeText ?? "未知")
            }
            .padding(.vertical, 14)
            .background(PeachTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !current.performers.isEmpty {
                section("演员") {
                    flow(current.performers, icon: "person.fill")
                }
            }

            if let date = current.releaseDate, !date.isEmpty {
                section("发行日期") {
                    Text(date).font(.subheadline).foregroundStyle(.white.opacity(0.72))
                }
            }

            if !current.tags.isEmpty {
                section("标签") {
                    flow(current.tags, icon: nil)
                }
            }

            section("文件") {
                Text(current.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }

            if case .failed(let message) = model.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(PeachTheme.coral)
            }
        }
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle().fill(PeachTheme.line).frame(width: 1, height: 28)
    }

    private func spec(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.7)
            content()
        }
    }

    private func flow(_ values: [String], icon: String?) -> some View {
        FlowLayout(spacing: 7) {
            ForEach(values, id: \.self) { value in
                facet(value, icon: icon)
            }
        }
    }

    private func facet(_ value: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9)) }
            Text(value).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(PeachTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(PeachTheme.line))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
