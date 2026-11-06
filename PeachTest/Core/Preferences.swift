import Foundation
import SwiftUI

/// Local display and playback preferences. They are kept in UserDefaults so a
/// density change or muted wall survives relaunching the app, matching the
/// browser's `localStorage` behaviour for density and photo size.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let density = "peach.density"
        static let wallImage = "peach.wall.image"
        static let wallMuted = "peach.wall.muted"
        static let seekSeconds = "peach.seek.seconds"
    }

    @Published var density: PeachDensity {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }
    @Published var wallImage: WallImage {
        didSet { defaults.set(wallImage.rawValue, forKey: Key.wallImage) }
    }
    @Published var wallMuted: Bool {
        didSet { defaults.set(wallMuted, forKey: Key.wallMuted) }
    }
    @Published var seekSeconds: Double {
        didSet { defaults.set(seekSeconds, forKey: Key.seekSeconds) }
    }

    private let defaults = UserDefaults.standard

    init() {
        density = PeachDensity(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .big
        wallImage = WallImage(rawValue: defaults.string(forKey: Key.wallImage) ?? "") ?? .cover
        // The web wall mounts the normal stage player on a user click, so it
        // starts audible. Keep the same default; the speaker control is ours.
        wallMuted = defaults.object(forKey: Key.wallMuted) as? Bool ?? false
        let seek = defaults.double(forKey: Key.seekSeconds)
        // The 0.52.0 player defaults to 10 seconds; keep parity unless the
        // user changed the stored value.
        seekSeconds = seek >= 1 && seek <= 300 ? seek : 10
    }
}
