#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum OriginalVideoFrame {
    private static let context = CIContext()

    static func capture(asset: AVURLAsset, seconds: Double, hls: Bool) async throws -> CGImage {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if hls { return try await decodedFrame(asset: asset, at: time) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        return try await withTaskCancellationHandler {
            try await generator.image(at: time).image
        } onCancel: {
            Task { @MainActor in generator.cancelAllCGImageGeneration() }
        }
    }

    private static func decodedFrame(asset: AVURLAsset, at time: CMTime) async throws -> CGImage {
        // Peach's ordinary HLS has no I-frame rendition for AVAssetImageGenerator.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        item.preferredForwardBufferDuration = 1
        defer { player.pause(); player.replaceCurrentItem(with: nil) }

        let deadline = ContinuousClock.now + .seconds(22)
        while item.status == .unknown, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard item.status == .readyToPlay else {
            throw item.error ?? PeachAPIError(message: "播放源未准备好，无法提取原图")
        }
        item.add(output)
        let timeout = Task { @MainActor in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            item.cancelPendingSeeks()
        }
        defer { timeout.cancel() }
        let reached = await withTaskCancellationHandler {
            await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } onCancel: {
            Task { @MainActor in item.cancelPendingSeeks() }
        }
        try Task.checkCancellation()
        guard reached else { throw PeachAPIError(message: "定位原图超时") }
        player.playImmediately(atRate: 1)

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let itemTime = player.currentTime()
            if itemTime >= time,
               let pixel = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                let image = CIImage(cvPixelBuffer: pixel)
                if let frame = context.createCGImage(image, from: image.extent) { return frame }
            }
            if let error = item.error { throw error }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw PeachAPIError(message: "等待原画帧超时")
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
#endif
