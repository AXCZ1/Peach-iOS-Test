#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum OriginalVideoFrame {
    private static let tolerance = CMTime(seconds: 0.35, preferredTimescale: 600)

    static func capture(asset: AVURLAsset, seconds: Double) async throws -> CGImage {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try await withTaskCancellationHandler {
            try await generator.image(at: time).image
        } onCancel: {
            Task { @MainActor in generator.cancelAllCGImageGeneration() }
        }
    }

    nonisolated static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw PeachAPIError(message: "无法保存原画帧")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PeachAPIError(message: "无法保存原画帧") }
        return data as Data
    }
}

extension PeachItem {
    var canProbeOriginalWithAVFoundation: Bool {
        ["mp4", "m4v", "mov"].contains((name as NSString).pathExtension.lowercased())
    }
}

@MainActor
final class OriginalFrameReader {
    private var avAsset: AVURLAsset?
    #if os(iOS) && !SWIFT_PACKAGE
    private let url: URL
    private let item: PeachItem
    private lazy var vlc = VLCOriginalFrameDecoder(url: url, width: item.width, height: item.height)
    #endif

    init(api: PeachAPI, item: PeachItem) async throws {
        let url = try await api.originalPlaybackURL(id: item.id)
        try Task.checkCancellation()
        if item.canProbeOriginalWithAVFoundation { avAsset = AVURLAsset(url: url) }
        #if os(iOS) && !SWIFT_PACKAGE
        self.url = url
        self.item = item
        #endif
    }

    func capture(at seconds: Double) async throws -> CGImage {
        try Task.checkCancellation()
        if let avAsset {
            #if os(iOS) && !SWIFT_PACKAGE
            do { return try await OriginalVideoFrame.capture(asset: avAsset, seconds: seconds) }
            catch {
                try Task.checkCancellation()
                if (error as NSError).domain == NSURLErrorDomain { throw error }
                self.avAsset = nil
            }
            #else
            return try await OriginalVideoFrame.capture(asset: avAsset, seconds: seconds)
            #endif
        }
        #if os(iOS) && !SWIFT_PACKAGE
        return try await vlc.capture(at: seconds)
        #else
        throw PeachAPIError(message: "此设备没有可读取该原文件的取帧解码器")
        #endif
    }
}
#endif
