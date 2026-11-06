import Foundation

@MainActor
final class LibraryModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var items: [PeachItem] = []
    @Published private(set) var total = 0
    @Published private(set) var hasMore = false
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var facets: PeachFacets?
    @Published var filter = LibraryFilter()
    @Published var selectedLibraryID: String = ""

    private var api: PeachAPI?
    private var generation = 0
    private let pageSize = 60

    func attach(_ api: PeachAPI) {
        self.api = api
    }

    func select(libraryID: String) async {
        selectedLibraryID = libraryID
        await reload()
    }

    func initialLoad(libraryID: String) async {
        if selectedLibraryID.isEmpty { selectedLibraryID = libraryID }
        await reload()
    }

    func reload() async {
        guard let api else { return }
        generation += 1
        let current = generation
        filter.libraryID = selectedLibraryID
        state = .loading
        do {
            async let pageTask = api.items(filter, offset: 0, limit: pageSize)
            async let facetsTask = api.facets(filter)
            let page = try await pageTask
            let facets = try? await facetsTask
            guard current == generation else { return }
            items = page.items
            total = page.total ?? page.items.count
            hasMore = page.hasMore ?? (items.count < total)
            self.facets = facets
            state = .loaded
        } catch {
            guard current == generation else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: PeachItem) async {
        guard hasMore, state == .loaded, let api else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 12 else { return }
        let current = generation
        filter.libraryID = selectedLibraryID
        do {
            let page = try await api.items(filter, offset: items.count, limit: pageSize)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            hasMore = page.hasMore ?? (items.count < total)
        } catch {
            // Keep the visible page; the user can retry by scrolling.
        }
    }

    func clearFilter() async {
        filter = LibraryFilter(libraryID: selectedLibraryID)
        await reload()
    }

    func apiIndex(kind: String) async throws -> [PeachFacet] {
        guard let api else { return [] }
        return try await api.index(kind)
    }
}
