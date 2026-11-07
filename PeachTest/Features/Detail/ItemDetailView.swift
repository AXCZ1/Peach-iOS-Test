import SwiftUI

struct ItemDetailView: View {
    let item: PeachItem
    let api: PeachAPI
    @StateObject private var model: ItemDetailModel
    @State private var playerPresented = false
    @State private var toast: String?
    @State private var undoAction: SingleUseAction?
    @State private var toastID = UUID()
    @State private var busy = false

    init(item: PeachItem, api: PeachAPI) {
        self.item = item
        self.api = api
        _model = StateObject(wrappedValue: ItemDetailModel(api: api, item: item))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    metadata
                }
                .padding(.bottom, 110)
            }
            .background(PeachTheme.background.ignoresSafeArea())

            if let toast {
                ToastBar(message: toast, undo: undoAction)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(current.displayNumber.isEmpty ? "作品" : current.displayNumber)
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
                    Text(current.resumeTime > 5 ? "继续播放" : "播放").font(.headline)
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

            ratingRow
            actionRow

            Button {
                Task { await recordClimax() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "heart.fill")
                    Text("记一次高潮")
                    Spacer()
                    Text("\(current.oCount)")
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(.black.opacity(0.28), in: Capsule())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(PeachTheme.coral, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("detail.climax")

            PreviewFilmstrip(api: api, item: current)

            if !current.performers.isEmpty {
                section("演员") {
                    FlowLayout(spacing: 7) {
                        ForEach(current.performers, id: \.self) { value in
                            NavigationLink(value: EntityRoute(kind: "performer", name: value)) {
                                facet(value, icon: "person.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let date = current.releaseDate, !date.isEmpty {
                section("发行日期") {
                    Text(date).font(.subheadline).foregroundStyle(.white.opacity(0.72))
                }
            }

            if !current.tags.isEmpty {
                section("标签") {
                    FlowLayout(spacing: 7) {
                        ForEach(current.tags, id: \.self) { value in
                            NavigationLink(value: EntityRoute(kind: "tag", name: value)) {
                                facet(value, icon: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if current.progress > 0 {
                section("观看进度") {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: current.progress)
                            .tint(PeachTheme.coral)
                        Text("已观看 \(Int(current.progress * 100))% · 播放 \(current.playCount) 次")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                    }
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

    private var ratingRow: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    Task {
                        do {
                            let value = try await model.rate(star: star)
                            if value == 0 { showToast("已取消评分", undo: nil) }
                        } catch let failure {
                            showToast(failure.localizedDescription, undo: nil)
                        }
                    }
                } label: {
                    Image(systemName: star <= current.ratingStars ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundStyle(star <= current.ratingStars ? PeachTheme.amber : .white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel(star == current.ratingStars ? "取消评分" : "评为 \(star) 星")
            }
            Text(current.ratingStars > 0 ? "\(current.ratingStars) 星" : "未评分")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
            Spacer()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(
                title: current.watchLater ? "已稍后看" : "稍后看",
                icon: current.watchLater ? "bookmark.fill" : "bookmark",
                active: current.watchLater
            ) { await toggleLater() }
            actionButton(
                title: "喜欢",
                icon: current.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                active: current.liked
            ) { await toggleLiked() }
            actionButton(
                title: "看过",
                icon: current.feedback == "seen" ? "eye.fill" : "eye",
                active: current.feedback == "seen"
            ) { await toggleFeedback("seen") }
            actionButton(
                title: "不合口味",
                icon: current.feedback == "dislike" ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                active: current.feedback == "dislike"
            ) { await toggleFeedback("dislike") }
        }
    }

    private func actionButton(title: String, icon: String, active: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? PeachTheme.coral : .white.opacity(0.65))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(active ? PeachTheme.coral.opacity(0.12) : PeachTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
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

    private func toggleLater() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let on = try await api.toggleWatchLater(id: current.id)
            await model.refresh()
            let assetID = current.id
            showToast(on ? "已加入稍后看" : "已移出稍后看", undo: {
                Task { await undoWrite(assetID: assetID, climax: false) }
            })
        } catch let failure {
            showToast(failure.localizedDescription, undo: nil)
        }
    }

    private func toggleLiked() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let target = !current.liked
        do {
            try await api.setLiked(id: current.id, liked: target)
            await model.refresh()
            showToast(target ? "已标记喜欢" : "已取消喜欢", undo: nil)
        } catch let failure {
            showToast(failure.localizedDescription, undo: nil)
        }
    }

    private func toggleFeedback(_ kind: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await api.feedback(id: current.id, kind: kind)
            await model.refresh()
            let label = kind == "seen" ? "看过" : "不合口味"
            showToast(result.feedback == kind ? "已标记\(label)" : "已取消\(label)", undo: nil)
        } catch let failure {
            showToast(failure.localizedDescription, undo: nil)
        }
    }

    private func recordClimax() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await api.feedback(id: current.id, kind: "o")
            await model.refresh()
            let assetID = current.id
            showToast("已记一次高潮 · \(result.oCount ?? current.oCount)", undo: {
                Task { await undoWrite(assetID: assetID, climax: true) }
            })
        } catch let failure {
            showToast(failure.localizedDescription, undo: nil)
        }
    }

    private func undoWrite(assetID: Int, climax: Bool) async {
        busy = true
        defer { busy = false }
        do {
            if climax { _ = try await api.feedback(id: assetID, kind: "o-undo") }
            else { _ = try await api.toggleWatchLater(id: assetID) }
            await model.refresh()
            showToast("已撤销", undo: nil)
        } catch let failure {
            await model.refresh()
            showToast("撤销结果未确认：\(failure.localizedDescription)", undo: nil)
        }
    }

    private func showToast(_ message: String, undo: (() -> Void)?) {
        let identifier = UUID()
        toastID = identifier
        withAnimation(.easeOut(duration: 0.2)) {
            toast = message
            undoAction = undo.map { SingleUseAction($0) }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastID == identifier {
                withAnimation(.easeIn(duration: 0.2)) {
                    toast = nil
                    undoAction = nil
                }
            }
        }
    }
}

struct ToastBar: View {
    let message: String
    var undo: SingleUseAction?
    @State private var consumed = false

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let undo {
                Button("撤销") {
                    guard let action = undo.take() else { return }
                    consumed = true
                    action()
                }
                    .disabled(consumed)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PeachTheme.coral)
            }
        }
        .onChange(of: undo?.id) { _, _ in consumed = false }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(PeachTheme.line))
    }
}
