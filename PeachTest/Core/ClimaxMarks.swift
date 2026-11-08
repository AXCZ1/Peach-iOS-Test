import Foundation

struct ClimaxMark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let seconds: Double

    init(seconds: Double) {
        id = UUID()
        self.seconds = seconds
    }
}

@MainActor
struct ClimaxMarks {
    static let local = ClimaxMarks(defaults: .standard)
    let defaults: UserDefaults

    func list(origin: URL, item: PeachItem) -> [ClimaxMark] {
        guard let data = defaults.data(forKey: key(origin, item)) else { return [] }
        return (try? JSONDecoder().decode([ClimaxMark].self, from: data)) ?? []
    }

    func record(api: PeachAPI, item: PeachItem, at seconds: Double?) async throws -> (Int, ClimaxMark?) {
        let result = try await api.feedback(id: item.id, kind: "o")
        guard result.ok == true, let count = result.oCount else {
            throw PeachAPIError(message: "Peach 未确认本次记录")
        }
        guard let seconds, seconds.isFinite, seconds >= 0 else { return (count, nil) }
        let mark = ClimaxMark(seconds: seconds)
        try store(list(origin: api.baseURL, item: item) + [mark], origin: api.baseURL, item: item)
        return (count, mark)
    }

    func undo(api: PeachAPI, item: PeachItem, mark: ClimaxMark?) async throws -> Int {
        let result = try await api.feedback(id: item.id, kind: "o-undo")
        guard result.ok == true, let count = result.oCount else {
            throw PeachAPIError(message: "Peach 未确认撤销")
        }
        if let mark {
            try store(list(origin: api.baseURL, item: item).filter { $0.id != mark.id }, origin: api.baseURL, item: item)
        }
        return count
    }

    private func store(_ marks: [ClimaxMark], origin: URL, item: PeachItem) throws {
        defaults.set(try JSONEncoder().encode(marks), forKey: key(origin, item))
    }

    private func key(_ origin: URL, _ item: PeachItem) -> String {
        "peach.climax.\(MediaDiskCache.filename(MediaCacheKey(url: origin).origin + "/" + item.mediaCacheIdentity))"
    }
}
