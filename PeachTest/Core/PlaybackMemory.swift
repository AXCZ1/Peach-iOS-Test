import Foundation

/// Local resume memory, the same role as `peach.playback-position.v1` in the
/// web client. Cleared at the end so a finished item starts from zero.
final class PlayerMemory: @unchecked Sendable {
    static let shared = PlayerMemory()
    private let defaults = UserDefaults.standard
    private let prefix = "peach.playback.position."

    private func key(_ id: Int) -> String { prefix + String(id) }

    func position(for id: Int) -> Double? {
        let value = defaults.double(forKey: key(id))
        return value > 0 ? value : nil
    }

    func save(_ position: Double, for id: Int) {
        guard position.isFinite, position >= 0 else { return }
        defaults.set(position, forKey: key(id))
    }

    func clear(_ id: Int) {
        defaults.removeObject(forKey: key(id))
    }
}
