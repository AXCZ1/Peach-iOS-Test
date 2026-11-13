import Foundation

enum MediaClock {
    static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = total % 3600 / 60, remainder = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

enum EntityKind: String, CaseIterable, Identifiable, Sendable {
    case performer, studio, tag, series, creator
    var id: String { rawValue }
    var label: String {
        switch self {
        case .performer: return "演员"
        case .studio: return "厂牌"
        case .tag: return "标签"
        case .series: return "系列"
        case .creator: return "创作者"
        }
    }
    var apiKind: String {
        switch self {
        case .performer: return "performers"
        case .studio: return "studios"
        case .tag: return "tags"
        case .series: return "series"
        case .creator: return "creators"
        }
    }
    static func canonical(_ value: String) -> String {
        allCases.first { $0.rawValue == value || $0.apiKind == value }?.rawValue ?? value
    }
}

enum PlaybackTap: Equatable {
    case backward, toggle, forward
    static func action(at fraction: Double) -> Self {
        if fraction < 0.25 { return .backward }
        if fraction >= 0.75 { return .forward }
        return .toggle
    }
}

struct PlaybackTapSequence {
    enum Action: Equatable {
        case wait(until: TimeInterval, showPreviousSingle: Bool)
        case togglePlayback
        case seek(offset: Double, startsSequence: Bool)
    }

    private enum State {
        case idle
        case first(PlaybackTap, until: TimeInterval)
        case seeking(PlaybackTap, until: TimeInterval, offset: Double)
    }

    private var state = State.idle

    mutating func register(_ zone: PlaybackTap, at timestamp: TimeInterval) -> Action {
        var showPreviousSingle = false
        switch state {
        case .first(let previous, let deadline):
            if previous == zone, timestamp <= deadline {
                if zone == .toggle {
                    state = .idle
                    return .togglePlayback
                }
                let offset = zone == .forward ? 10.0 : -10.0
                state = .seeking(zone, until: timestamp + 0.7, offset: offset)
                return .seek(offset: offset, startsSequence: true)
            }
            showPreviousSingle = true
        case .seeking(let previous, let deadline, let offset) where previous == zone && timestamp <= deadline:
            let next = offset + (zone == .forward ? 10 : -10)
            state = .seeking(zone, until: timestamp + 0.7, offset: next)
            return .seek(offset: next, startsSequence: false)
        default: break
        }
        let deadline = timestamp + 0.3
        state = .first(zone, until: deadline)
        return .wait(until: deadline, showPreviousSingle: showPreviousSingle)
    }

    mutating func finishSingle() {
        state = .idle
    }
}

/// Page visibility never overwrites a user's pause choice. Preparing a player
/// is not a play event; only an allowed, observed playback consumes the mark.
struct PlaybackIntent {
    var isActive = false
    var wantsPlayback = true
    var scrubbing = false
    private var marked = false
    var mayPlay: Bool { isActive && wantsPlayback && !scrubbing }
    mutating func newSession() { marked = false; scrubbing = false }
    mutating func consumePlayMark(isPlaying: Bool) -> Bool {
        guard isPlaying, mayPlay, !marked else { return false }
        marked = true
        return true
    }
}

@MainActor
final class SingleUseAction {
    let id = UUID()
    private var action: (@MainActor () -> Void)?
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    func take() -> (@MainActor () -> Void)? {
        defer { action = nil }
        return action
    }
}

struct ImmersivePagination {
    let seed: Int
    private(set) var offset = 0
    private(set) var loading = false
    private(set) var exhausted = false
    init(seed: Int = Int.random(in: 1...99990)) { self.seed = seed }
    mutating func begin() -> Bool {
        guard !loading, !exhausted else { return false }
        loading = true
        return true
    }
    mutating func finish(received: Int, total: Int) {
        offset += received
        loading = false
        exhausted = received == 0 || offset >= total
    }
    mutating func fail() { loading = false }
}

struct CoverFrame: Decodable, Hashable, Sendable {
    let cx: Double?
    let cy: Double?
    let layout: String?
}

struct PosterBox: Decodable, Hashable, Sendable {
    let x0: Double
    let y0: Double
    let x1: Double
    let y1: Double
    let px: [Double]
    let method: String?

    var normalized: ImageRegion? {
        guard px.count == 2, px[0] > 0, px[1] > 0,
              x0 >= 0, y0 >= 0, x1 > x0, y1 > y0, x1 <= px[0], y1 <= px[1] else { return nil }
        return ImageRegion(x: x0 / px[0], y: y0 / px[1], width: (x1-x0) / px[0], height: (y1-y0) / px[1])
    }
}

struct ImageRegion: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    static let full = ImageRegion(x: 0, y: 0, width: 1, height: 1)
}

struct TimelineMetadata: Decodable, Sendable {
    let frames: Int?
    let interval: Double?
    let columns: Int?
    let rows: Int?
    let source: String?
    let cues: [[Double]]?
    let timestamps: [Double]?
    let madeAt: Double?
    // A class permits Peach's optional nested fallback without recursive value storage.
    let fallback: TimelineFallback?

    enum CodingKeys: String, CodingKey {
        case frames, interval, columns, rows, source, cues, timestamps, fallback
        case madeAt = "made_at"
    }

    func sampleTime(at index: Int) -> Double {
        if let timestamps, timestamps.indices.contains(index) { return timestamps[index] }
        if let cues, cues.indices.contains(index), let start = cues[index].first { return start }
        return Double(index) * (interval ?? 0)
    }

    func frame(at seconds: Double) -> Int? {
        guard seconds.isFinite, seconds >= 0, let frames, frames > 0 else { return nil }
        if let cues, !cues.isEmpty {
            var low = 0, high = min(frames, cues.count)
            while low < high {
                let mid = (low + high) / 2
                guard cues[mid].count >= 2 else { return nil }
                if cues[mid][0] <= seconds { low = mid + 1 } else { high = mid }
            }
            let index = low - 1
            guard index >= 0, cues[index].count >= 2,
                  seconds < cues[index][1] || (index == cues.count-1 && seconds == cues[index][1]) else { return nil }
            return index
        }
        guard let interval, interval.isFinite, interval > 0 else { return nil }
        return Int(min(Double(frames - 1), floor(seconds / interval)))
    }

    func tile(at seconds: Double) -> TimelineTile? {
        guard let index = frame(at: seconds) else { return nil }
        return tile(atIndex: index)
    }

    func tile(atIndex index: Int) -> TimelineTile? {
        guard let frames, index >= 0, index < frames else { return nil }
        let columns = max(1, self.columns ?? 10), rows = max(1, self.rows ?? 10)
        let perSheet = columns * rows, sheet = index / perSheet, cell = index % perSheet
        let actualRows = (min(perSheet, frames - sheet * perSheet) + columns - 1) / columns
        return TimelineTile(sheet: sheet, region: ImageRegion(
            x: Double(cell % columns) / Double(columns), y: Double(cell / columns) / Double(actualRows),
            width: 1 / Double(columns), height: 1 / Double(actualRows)), source: source ?? "peach")
    }
}

final class TimelineFallback: Decodable, Sendable {
    let value: TimelineMetadata
    init(from decoder: Decoder) throws { value = try TimelineMetadata(from: decoder) }
}

struct TimelineTile: Equatable, Sendable {
    let sheet: Int
    let region: ImageRegion
    let source: String
    static func nineGrid(time: Double, duration: Double) -> ImageRegion {
        let fraction = duration > 0 ? min(1, max(0, time / duration)) : 0
        let cell = min(8, Int(fraction * 9))
        return ImageRegion(x: Double(cell % 3) / 3, y: Double(cell / 3) / 3, width: 1 / 3, height: 1 / 3)
    }
}

/// Matches Peach 0.52.0 card-art/hover.ts local-video preview positions.
enum PreviewPlayback {
    static let positions: [Double] = [0.08, 0.22, 0.36, 0.5, 0.64, 0.78, 0.9]
}

enum DwellSelection {
    static let minimumVisibleRatio: CGFloat = 0.65
    static let dwellDurationSeconds: TimeInterval = 1.0

    static func isEligible(frame: CGRect, viewport: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0, viewport.width > 0, viewport.height > 0 else { return false }
        let intersection = frame.intersection(viewport)
        guard !intersection.isNull else { return false }
        return intersection.height / min(frame.height, viewport.height) >= minimumVisibleRatio
    }

    static func candidate(bounds: [Int: CGRect], viewport: CGRect) -> Int? {
        bounds.filter { _, frame in
            isEligible(frame: frame, viewport: viewport)
        }.min { abs($0.value.midY - viewport.midY) < abs($1.value.midY - viewport.midY) }?.key
    }

    /// Retains the active preview while at least 65% of its cover stays visible in the viewport;
    /// otherwise clears it and returns the next dwell candidate.
    static func activeOrNextCandidate(activeID: Int?, bounds: [Int: CGRect], viewport: CGRect) -> (retainedActiveID: Int?, nextCandidateID: Int?) {
        if let activeID, let frame = bounds[activeID], isEligible(frame: frame, viewport: viewport) {
            return (activeID, nil)
        }
        return (nil, candidate(bounds: bounds, viewport: viewport))
    }
}
