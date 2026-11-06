import SwiftUI
import UIKit

extension UIImage {
    func cropped(to region: ImageRegion) -> UIImage? {
        guard let cgImage else { return nil }
        let width = Double(cgImage.width), height = Double(cgImage.height)
        let rect = CGRect(x: region.x * width, y: region.y * height,
                          width: region.width * width, height: region.height * height).integral
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

struct CoverPoster: View {
    let item: PeachItem
    let api: PeachAPI
    @State private var source: UIImage?
    @State private var front: UIImage?

    private var url: URL? {
        guard item.hasCover else { return nil }
        return api.coverURL(code: item.coverKey.isEmpty ? item.displayNumber : item.coverKey,
                            thumb: 0, version: item.coverVersion)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PeachTheme.surface
                if let source, let front {
                    Image(uiImage: source).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 18).opacity(0.4)
                    Image(uiImage: front).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: url) {
            source = nil
            front = nil
            guard let url, let image = await PeachImageCache.shared.image(for: url), !Task.isCancelled else { return }
            source = image
            front = image.cropped(to: cropRegion(image)) ?? image
        }
    }

    private func cropRegion(_ image: UIImage) -> ImageRegion {
        if let box = item.posterBox?.normalized { return box }
        let ratio = image.size.width / max(1, image.size.height)
        let code = item.displayNumber.uppercased()
        let still = item.coverFrame?.layout == "still" || code.hasPrefix("FC2")
            || ["IENEE-", "IENFE-", "SDHS-"].contains(where: code.hasPrefix)
        if still || ratio <= 1.2 { return .full }
        let wide = ratio >= 1.75 && ratio < 1.85
            && (item.title.range(of: "blu[\\s-]?ray|ブルーレイ", options: .regularExpression) != nil
                || code.hasPrefix("CWPBD-") || code.hasPrefix("SMBD-"))
        if ratio < 1.65 || wide {
            let fraction = (wide ? 0.85 : 0.704) / ratio
            return ImageRegion(x: 1 - fraction, y: 0, width: fraction, height: 1)
        }
        return .full
    }
}

struct SeekThumbnail: View {
    let api: PeachAPI
    let item: PeachItem
    let time: Double
    let duration: Double
    @State private var metadata: TimelineMetadata?
    @State private var image: UIImage?
    @State private var unavailable = false

    private var requestID: String {
        let tile = metadata?.tile(at: time)
        return "\(item.id):\(tile?.source ?? "grid"):\(tile?.sheet ?? -1):\(tile?.region ?? TimelineTile.nineGrid(time: time, duration: duration))"
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.85)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if unavailable {
                    Text("预览不可用").font(.caption2).foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.65)))
            Text(MediaClock.text(time)).font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.8), in: Capsule())
        }
        .frame(width: 160)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: item.id) {
            let value = try? await api.timeline(id: item.id)
            guard !Task.isCancelled else { return }
            metadata = value
        }
        .task(id: requestID) { await loadFrame() }
    }

    private func loadFrame() async {
        let requestedTime = time
        image = nil
        unavailable = false
        let candidates = [metadata, metadata?.fallback?.value].compactMap { $0 }
        for candidate in candidates {
            guard let tile = candidate.tile(at: requestedTime) else { continue }
            let url = api.timelineURL(id: item.id, sheet: tile.sheet, source: tile.source)
            let sheet = await PeachImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            if let frame = sheet?.cropped(to: tile.region) { image = frame; return }
        }
        if item.hasThumb {
            // /thumb only serves an existing contact sheet. /poster may invoke
            // FFmpeg, so it must not be used for the user's read-only previews.
            let sheet = await PeachImageCache.shared.image(for: api.thumbURL(id: item.id))
            guard !Task.isCancelled else { return }
            image = sheet?.cropped(to: TimelineTile.nineGrid(time: requestedTime, duration: duration))
        }
        unavailable = image == nil
    }
}

struct PlaybackSeekBar: View {
    @ObservedObject var controller: PlaybackController
    let api: PeachAPI
    let item: PeachItem
    @State private var dragging = false
    @State private var value = 0.0

    private var shownTime: Double { dragging ? value : (controller.seekPreview ?? controller.currentTime) }
    private var fraction: Double { min(1, max(0, shownTime / max(controller.duration, 1))) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 3)
                    Capsule().fill(PeachTheme.coral).frame(width: geometry.size.width * fraction, height: 3)
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .offset(x: max(0, (geometry.size.width - 12) * fraction))
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard controller.duration > 0 else { return }
                        if !dragging { dragging = true; controller.beginScrubbing() }
                        value = controller.duration * min(1, max(0, gesture.location.x / max(1, geometry.size.width)))
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        controller.endScrubbing(at: value)
                        dragging = false
                    })
                .accessibilityElement()
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(MediaClock.text(shownTime))，共 \(MediaClock.text(controller.duration))")
                .accessibilityAdjustableAction { direction in
                    controller.skip(by: direction == .increment ? 10 : -10)
                }

                if dragging || controller.seekPreview != nil {
                    SeekThumbnail(api: api, item: item, time: shownTime, duration: controller.duration)
                        .position(x: min(max(80, geometry.size.width * fraction), max(80, geometry.size.width - 80)), y: -60)
                }
            }
            .frame(height: 44)
            HStack {
                Text(MediaClock.text(shownTime))
                Spacer()
                Text(MediaClock.text(controller.duration))
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
        }
        .onChange(of: controller.isScrubbing) { _, scrubbing in
            if !scrubbing { dragging = false }
        }
        .onDisappear {
            if dragging { controller.cancelScrubbing(); dragging = false }
        }
    }
}
