import Foundation

@MainActor
final class ItemDetailModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded(PeachItem)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading
    private let api: PeachAPI
    private let id: Int

    init(api: PeachAPI, item: PeachItem) {
        self.api = api
        self.id = item.id
        state = .loaded(item)
    }

    var item: PeachItem? {
        if case .loaded(let item) = state { return item }
        return nil
    }

    func load() async {
        if item == nil { state = .loading }
        do {
            state = .loaded(try await api.item(id: id))
            PeachRuntimeLogger.shared.log("作品详情加载完成 id=\(id)", level: .debug, category: "detail", source: "ItemDetailModel")
        } catch {
            state = .failed(error.localizedDescription)
            PeachRuntimeLogger.shared.log("作品详情加载失败 id=\(id): \(error.localizedDescription)", level: .error, category: "detail", source: "ItemDetailModel")
        }
    }

    /// Re-reads after a write so the next action toggles from the server's
    /// persisted value rather than an optimistic guess.
    func refresh() async {
        do {
            state = .loaded(try await api.item(id: id))
        } catch {
            PeachRuntimeLogger.shared.log("作品详情刷新失败 id=\(id): \(error.localizedDescription)", level: .warning, category: "detail", source: "ItemDetailModel")
        }
    }

    @discardableResult
    func rate(star: Int) async throws -> Int {
        guard let current = item else { return 0 }
        let value = star == current.ratingStars ? 0 : star * 20
        _ = try await api.feedback(id: id, kind: "rate", value: value)
        await refresh()
        return value
    }
}
