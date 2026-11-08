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

    private let defaults: UserDefaults
    private static let sortKey = "peach.library.sort"
    private static let ascendingKey = "peach.library.ascending"
    private var api: PeachAPI?
    private var generation = 0
    private let pageSize = 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let sort = CatalogSort(rawValue: defaults.string(forKey: Self.sortKey) ?? "") ?? .seed
        filter = LibraryFilter(sort: sort, ascending: sort.supportsDirection && defaults.bool(forKey: Self.ascendingKey))
    }

    private func saveOrder() {
        defaults.set(filter.sort.rawValue, forKey: Self.sortKey)
        defaults.set(filter.sort.supportsDirection && filter.ascending, forKey: Self.ascendingKey)
    }

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
        filter = LibraryFilter(libraryID: selectedLibraryID, sort: filter.sort, ascending: filter.ascending, seed: filter.seed)
        await reload()
    }

    func setState(_ state: CatalogState) async {
        filter.state = state
        await reload()
    }

    func setSort(_ sort: CatalogSort) async {
        if filter.sort == sort {
            if sort.supportsDirection { filter.ascending.toggle() }
        } else {
            filter.sort = sort
            filter.ascending = false
        }
        if sort == .seed { filter.seed = Int.random(in: 1...99990) }
        saveOrder()
        await reload()
    }

    func shuffle() async {
        filter.sort = .seed
        filter.seed = Int.random(in: 1...99990)
        saveOrder()
        await reload()
    }

    func applySheet(_ updated: LibraryFilter) async {
        filter = updated
        saveOrder()
        await reload()
    }

    func apply(_ patch: (inout LibraryFilter) -> Void) async {
        patch(&filter)
        filter.libraryID = selectedLibraryID
        await reload()
    }

    func replace(item: PeachItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func apiIndex(kind: String, query: String = "") async throws -> [PeachFacet] {
        guard let api else { return [] }
        return try await api.index(kind: kind, query: query)
    }
}
