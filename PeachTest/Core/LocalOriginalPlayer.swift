#if canImport(AVFoundation)
import Foundation

enum LocalOriginalDecoder: Equatable {
    case automatic, software
}

enum LocalPlaybackEvent {
    case sample(position: Double?, duration: Double, playing: Bool, hasFrame: Bool)
    case ended
    case failed(String, canRetryInSoftware: Bool = false)
}

@MainActor
protocol LocalOriginalPlayer: AnyObject {
    var reportingPosition: Double? { get }
    var onEvent: ((LocalPlaybackEvent) -> Void)? { get set }

    func setPlayback(_ shouldPlay: Bool, rate: Float)
    func setRate(_ rate: Float)
    func setMuted(_ muted: Bool)
    func seek(to time: Double, completion: @escaping (Double?) -> Void)
    func stop()
}
#endif
