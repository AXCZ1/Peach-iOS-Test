import SwiftUI
import UIKit

struct PreviewBoundsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct DwellVideoPreview: View {
    @StateObject private var controller: PlaybackController
    init(item: PeachItem, api: PeachAPI) {
        _controller = StateObject(wrappedValue: PlaybackController(api: api, item: item, previewOnly: true))
    }
    var body: some View {
        ZStack {
            if let player = controller.player, controller.phase == .ready {
                Color.black
                VideoSurface(player: player)
            }
        }
        .allowsHitTesting(false)
        .task { controller.setMuted(true); await controller.activate() }
        .onDisappear { controller.stop() }
    }
}

struct TimelineFrameView: View {
    let api: PeachAPI
    let item: PeachItem
    let metadata: TimelineMetadata
    let index: Int
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            PeachTheme.surface
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView().tint(.white) }
        }
        .task(id: "\(item.id):\(index)") {
            guard let tile = metadata.tile(at: Double(index) * (metadata.interval ?? 0) + 0.001) else { failed = true; return }
            let sheet = await PeachImageCache.shared.image(for: api.timelineURL(id: item.id, sheet: tile.sheet, source: tile.source))
            guard !Task.isCancelled else { return }
            image = sheet?.cropped(to: tile.region); failed = image == nil
        }
    }
}

struct PreviewFilmstrip: View {
    let api: PeachAPI
    let item: PeachItem
    @State private var metadata: TimelineMetadata?
    @State private var error: String?
    @State private var selected = 0
    @State private var expanded = false
    @State private var reload = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预览图").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            if let metadata, let count = metadata.frames, count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(0..<min(30, count), id: \.self) { index in
                            Button { selected = index; expanded = true } label: {
                                VStack(spacing: 5) {
                                    TimelineFrameView(api: api, item: item, metadata: metadata, index: index)
                                        .frame(width: 144, height: 81).clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(MediaClock.text(timestamp(index, metadata)))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 105)
            } else if let error {
                HStack { Text(error).font(.footnote); Button("重试") { reload += 1 } }.foregroundStyle(.secondary)
            } else { ProgressView().tint(PeachTheme.coral) }
        }
        .task(id: "\(item.id):\(reload)") {
            error = nil
            do {
                metadata = try await api.timeline(id: item.id)
                if (metadata?.frames ?? 0) == 0 { error = "预览图尚未生成" }
            } catch { self.error = "预览图读取失败" }
        }
        .fullScreenCover(isPresented: $expanded) {
            if let metadata {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    TabView(selection: $selected) {
                        ForEach(0..<min(30, metadata.frames ?? 0), id: \.self) { index in
                            VStack {
                                TimelineFrameView(api: api, item: item, metadata: metadata, index: index)
                                Text("\(index + 1) / \(min(30, metadata.frames ?? 0)) · \(MediaClock.text(timestamp(index, metadata)))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.white)
                            }.padding(.vertical, 60).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                    Button { expanded = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .foregroundStyle(.white).padding().accessibilityLabel("关闭预览图")
                }
            }
        }
    }
    private func timestamp(_ index: Int, _ metadata: TimelineMetadata) -> Double {
        if let values = metadata.timestamps, values.indices.contains(index) { return values[index] }
        return Double(index) * (metadata.interval ?? 0)
    }
}
