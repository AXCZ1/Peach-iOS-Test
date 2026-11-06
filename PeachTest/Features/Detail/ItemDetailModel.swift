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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
