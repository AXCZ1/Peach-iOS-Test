#if canImport(AVFoundation)
import AVFoundation

extension PreviewPlayback {
    @MainActor
    static func playSample(on player: AVPlayer, at position: Double) async throws {
        guard let item = player.currentItem else { return }
        let deadline = ContinuousClock.now + .seconds(18)
        let timeout = Task { @MainActor in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            item.cancelPendingSeeks()
        }
        defer { timeout.cancel() }

        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        let finished = await player.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                                         toleranceBefore: tolerance, toleranceAfter: tolerance)
        try Task.checkCancellation()
        guard finished else { throw item.error ?? PeachAPIError(message: "无法定位视频预览片段") }

        let start = player.currentTime().seconds
        let total = item.duration.seconds
        let end = min(start + 1.4, total.isFinite && total > 0 ? total : .infinity)
        player.playImmediately(atRate: 1)
        // A stalled HLS segment must not use up the time for this sample.
        while player.currentTime().seconds < end - 0.04 {
            if let error = item.error { throw error }
            guard ContinuousClock.now < deadline else { throw PeachAPIError(message: "视频预览缓冲超时") }
            try await Task.sleep(for: .milliseconds(80))
        }
    }
}
#endif
