import Foundation

struct PeachLibrary: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let folders: Int
}

struct LibraryResponse: Decodable, Sendable {
    let libraries: [PeachLibrary]
}

struct PeachPage: Decodable, Sendable {
    let total: Int?
    let items: [PeachItem]
    let hasMore: Bool?

    init(total: Int?, items: [PeachItem], hasMore: Bool?) {
        self.total = total
        self.items = items
        self.hasMore = hasMore
    }

    enum CodingKeys: String, CodingKey {
        case total, items
        case hasMore = "has_more"
    }
}

struct PeachEntityRef: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let hasImage: Bool?
    let imageVersion: String?
    let hasLogo: Bool?
    let logoVersion: String?
    let avatarFocus: PeachFocus?
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case hasImage = "has_image"
        case imageVersion = "image_version"
        case hasLogo = "has_logo"
        case logoVersion = "logo_version"
        case avatarFocus = "avatar_focus"
    }
}

struct PeachFocus: Decodable, Hashable, Sendable {
    let axis: String?
    let pct: Double?
}

struct PeachItem: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let medium: String?
    let code: String?
    let catalogTitle: String?
    let originalTitle: String?
    let studio: String?
    let creator: String?
    let releaseDate: String?
    let duration: Double?
    let width: Int?
    let height: Int?
    let size: Int64?
    let performers: [String]
    let tags: [String]
    let hasCover: Bool
    let coverKey: String
    let coverVersion: String?
    let hasThumb: Bool
    let displayCode: String?
    let displayTitle: String?
    let isJav: Bool?
    let rating: Double?
    let oCount: Int
    let feedback: String?
    let disposal: String?
    let watchLater: Bool
    let liked: Bool
    let likeReason: String?
    let playCount: Int
    let leaveRatio: Double?
    let playSeconds: Double?
    let maxReached: Double?
    let seekCount: Int
    let editionBadges: [String]
    let regionLabel: String?
    let entities: [String: [String]]
    let entityRefs: [String: [PeachEntityRef]]
    let location: String?
    let cost: String?

    enum CodingKeys: String, CodingKey {
        case id, name, medium, code, studio, creator, duration, width, height, size
        case performers, tags, rating, feedback, disposal, liked, entities
        case catalogTitle = "catalog_title"
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case hasCover = "has_cover"
        case coverKey = "cover_key"
        case coverVersion = "cover_version"
        case hasThumb = "has_thumb"
        case displayCode = "display_code"
        case displayTitle = "display_title"
        case isJav = "is_jav"
        case oCount = "o_count"
        case watchLater = "watch_later"
        case likeReason = "like_reason"
        case playCount = "play_count"
        case leaveRatio = "leave_ratio"
        case playSeconds = "play_seconds"
        case maxReached = "max_reached"
        case seekCount = "seek_count"
        case editionBadges = "edition_badges"
        case regionLabel = "region_label"
        case entityRefs = "entity_refs"
        case location, cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        medium = try? c.decodeIfPresent(String.self, forKey: .medium)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        catalogTitle = try? c.decodeIfPresent(String.self, forKey: .catalogTitle)
        originalTitle = try? c.decodeIfPresent(String.self, forKey: .originalTitle)
        studio = try? c.decodeIfPresent(String.self, forKey: .studio)
        creator = try? c.decodeIfPresent(String.self, forKey: .creator)
        releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        duration = Self.number(c, .duration)
        width = Self.integer(c, .width)
        height = Self.integer(c, .height)
        size = Self.integer64(c, .size)
        performers = Self.strings(c, .performers)
        tags = Self.tags(c, .tags)
        hasCover = Self.boolean(c, .hasCover) ?? false
        coverKey = (try? c.decodeIfPresent(String.self, forKey: .coverKey)) ?? ""
        coverVersion = try? c.decodeIfPresent(String.self, forKey: .coverVersion)
        hasThumb = Self.boolean(c, .hasThumb) ?? false
        displayCode = try? c.decodeIfPresent(String.self, forKey: .displayCode)
        displayTitle = try? c.decodeIfPresent(String.self, forKey: .displayTitle)
        isJav = Self.boolean(c, .isJav)
        rating = Self.number(c, .rating)
        oCount = Self.integer(c, .oCount) ?? 0
        feedback = try? c.decodeIfPresent(String.self, forKey: .feedback)
        disposal = try? c.decodeIfPresent(String.self, forKey: .disposal)
        watchLater = Self.boolean(c, .watchLater) ?? false
        liked = Self.boolean(c, .liked) ?? false
        likeReason = try? c.decodeIfPresent(String.self, forKey: .likeReason)
        playCount = Self.integer(c, .playCount) ?? 0
        leaveRatio = Self.number(c, .leaveRatio)
        playSeconds = Self.number(c, .playSeconds)
        maxReached = Self.number(c, .maxReached)
        seekCount = Self.integer(c, .seekCount) ?? 0
        editionBadges = (try? c.decodeIfPresent([String].self, forKey: .editionBadges)) ?? []
        regionLabel = try? c.decodeIfPresent(String.self, forKey: .regionLabel)
        entities = (try? c.decodeIfPresent([String: [String]].self, forKey: .entities)) ?? [:]
        entityRefs = (try? c.decodeIfPresent([String: [PeachEntityRef]].self, forKey: .entityRefs)) ?? [:]
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        cost = try? c.decodeIfPresent(String.self, forKey: .cost)
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(v) }
        return nil
    }

    private static func integer(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        return nil
    }

    private static func integer64(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int64(v) }
        return nil
    }

    private static func boolean(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        return nil
    }

    private static func strings(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        (try? c.decodeIfPresent([String].self, forKey: key)) ?? []
    }

    private static func tags(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let flat = try? c.decodeIfPresent([String].self, forKey: key) { return flat }
        struct Tag: Decodable { let k: String }
        if let objects = try? c.decodeIfPresent([Tag].self, forKey: key) { return objects.map(\.k) }
        return []
    }

    var title: String {
        if let t = catalogTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let t = originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let t = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return name
    }

    var displayNumber: String {
        if let c = code?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        if let c = displayCode?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return ""
    }

    var resolution: String? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return "\(w)×\(h)"
    }

    var durationText: String {
        guard let duration, duration > 0 else { return "时长未知" }
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : "\(max(1, m)) 分钟"
    }

    var sizeText: String? {
        guard let size, size > 0 else { return nil }
        let gb = Double(size) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(size) / 1_048_576)
    }

    var ratingStars: Int { Int((max(0, min(100, rating ?? 0)) / 20).rounded()) }

    var isFlagged: Bool { oCount > 0 || liked }

    var progress: Double {
        if let leaveRatio, leaveRatio > 0 { return min(max(leaveRatio, 0), 1) }
        if let playSeconds, let duration, duration > 0 { return min(max(playSeconds / duration, 0), 1) }
        return 0
    }

    var resumeTime: Double {
        guard let duration, duration > 0 else { return 0 }
        if let leaveRatio, leaveRatio > 0, leaveRatio < 1 { return leaveRatio * duration }
        return 0
    }

    var performerRefs: [PeachEntityRef] { entityRefs["performer"] ?? [] }
    var studioRefs: [PeachEntityRef] { entityRefs["studio"] ?? [] }
    var creatorRefs: [PeachEntityRef] { entityRefs["creator"] ?? [] }
    var seriesRefs: [PeachEntityRef] { entityRefs["series"] ?? [] }

    /// Copy with only the fields a write changed. Keeping the original optionals
    /// intact matters: `rating = 0` would mean one star less than "unrated",
    /// and `feedback = ""` would stop matching the web client's nil checks.
    init(copying item: PeachItem, oCount: Int? = nil, rating: Double? = nil,
         watchLater: Bool? = nil, liked: Bool? = nil) {
        id = item.id
        name = item.name
        medium = item.medium
        code = item.code
        catalogTitle = item.catalogTitle
        originalTitle = item.originalTitle
        studio = item.studio
        creator = item.creator
        releaseDate = item.releaseDate
        duration = item.duration
        width = item.width
        height = item.height
        size = item.size
        performers = item.performers
        tags = item.tags
        hasCover = item.hasCover
        coverKey = item.coverKey
        coverVersion = item.coverVersion
        hasThumb = item.hasThumb
        displayCode = item.displayCode
        displayTitle = item.displayTitle
        isJav = item.isJav
        self.rating = rating ?? item.rating
        self.oCount = oCount ?? item.oCount
        feedback = item.feedback
        disposal = item.disposal
        self.watchLater = watchLater ?? item.watchLater
        self.liked = liked ?? item.liked
        likeReason = item.likeReason
        playCount = item.playCount
        leaveRatio = item.leaveRatio
        playSeconds = item.playSeconds
        maxReached = item.maxReached
        seekCount = item.seekCount
        editionBadges = item.editionBadges
        regionLabel = item.regionLabel
        entities = item.entities
        entityRefs = item.entityRefs
        location = item.location
        cost = item.cost
    }
}

struct PeachFacet: Decodable, Identifiable, Hashable, Sendable {
    let key: String
    let count: Int
    let entityID: Int?
    let representativeID: Int?
    let hasImage: Bool?
    let imageVersion: String?
    let hasLogo: Bool?
    let logoVersion: String?
    let favorite: Bool?

    enum CodingKeys: String, CodingKey {
        case key = "k"
        case count = "n"
        case entityID = "entity_id"
        case representativeID = "rep"
        case hasImage = "has_image"
        case imageVersion = "image_version"
        case hasLogo = "has_logo"
        case logoVersion = "logo_version"
        case favorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        entityID = try? c.decodeIfPresent(Int.self, forKey: .entityID)
        representativeID = try? c.decodeIfPresent(Int.self, forKey: .representativeID)
        hasImage = try? c.decodeIfPresent(Bool.self, forKey: .hasImage)
        imageVersion = try? c.decodeIfPresent(String.self, forKey: .imageVersion)
        hasLogo = try? c.decodeIfPresent(Bool.self, forKey: .hasLogo)
        logoVersion = try? c.decodeIfPresent(String.self, forKey: .logoVersion)
        favorite = try? c.decodeIfPresent(Bool.self, forKey: .favorite)
    }

    init(key: String, count: Int) {
        self.key = key
        self.count = count
        entityID = nil
        representativeID = nil
        hasImage = nil
        imageVersion = nil
        hasLogo = nil
        logoVersion = nil
        favorite = nil
    }

    var id: String { key }
}

struct PeachFacets: Decodable, Sendable {
    let tags: [PeachFacet]
    let performers: [PeachFacet]
    let creators: [PeachFacet]
    let studios: [PeachFacet]
    let years: [PeachFacet]
    let orientations: [PeachFacet]
    let regions: [PeachFacet]

    enum CodingKeys: String, CodingKey {
        case tags, performers, creators, studios, years, orientations, regions
        case tagperformers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = (try? c.decodeIfPresent([PeachFacet].self, forKey: .tags)) ?? []
        performers = (try? c.decodeIfPresent([PeachFacet].self, forKey: .performers))
            ?? (try? c.decodeIfPresent([PeachFacet].self, forKey: .tagperformers))
            ?? []
        creators = (try? c.decodeIfPresent([PeachFacet].self, forKey: .creators)) ?? []
        studios = (try? c.decodeIfPresent([PeachFacet].self, forKey: .studios)) ?? []
        years = (try? c.decodeIfPresent([PeachFacet].self, forKey: .years)) ?? []
        orientations = (try? c.decodeIfPresent([PeachFacet].self, forKey: .orientations)) ?? []
        regions = (try? c.decodeIfPresent([PeachFacet].self, forKey: .regions)) ?? []
    }
}

struct PeachIndexResponse: Decodable, Sendable {
    let items: [PeachFacet]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
    }
}

struct StreamPlan: Decodable, Sendable {
    let id: Int
    let protocolName: String
    let mimeType: String?
    let duration: Double?
    let src: String?

    enum CodingKeys: String, CodingKey {
        case id, duration, src
        case protocolName = "protocol"
        case mimeType = "mime_type"
    }
}

struct PeachErrorResponse: Decodable, Sendable {
    let error: String?
}

struct PeachFeedbackResponse: Decodable, Sendable {
    let ok: Bool?
    let feedback: String?
    let disposal: String?
    let rating: Double?
    let oCount: Int?

    enum CodingKeys: String, CodingKey {
        case ok, feedback, disposal, rating
        case oCount = "o_count"
    }
}

struct PeachPlayResponse: Decodable, Sendable {
    let ok: Bool?
}

struct PeachSearchHistoryResponse: Decodable, Sendable {
    let items: [String]
}

struct PeachRelatedResponse: Decodable, Sendable {
    let items: [PeachItem]
}

struct PeachLibraryShortcuts: Decodable, Sendable {
    let favorites: [PeachFavorite]
    let filters: [PeachSavedFilter]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? c.decodeIfPresent([PeachFavorite].self, forKey: .favorites)) ?? []
        filters = (try? c.decodeIfPresent([PeachSavedFilter].self, forKey: .filters)) ?? []
    }

    enum CodingKeys: String, CodingKey { case favorites, filters }
}

struct PeachFavorite: Decodable, Identifiable, Sendable {
    let key: String
    let entityID: Int?
    let kind: String
    let name: String
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case key, kind, name
        case entityID = "entity_id"
        case imageURL = "image_url"
    }

    var id: String { key }
}

struct PeachSavedFilter: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let href: String
}

struct PeachActivityResponse: Decodable, Sendable {
    let ok: Bool?
    let playSeconds: Double?
    let leaveRatio: Double?
    let maxReached: Double?
    let seekCount: Int?
    let realRatio: Double?

    enum CodingKeys: String, CodingKey {
        case ok
        case playSeconds = "play_seconds"
        case leaveRatio = "leave_ratio"
        case maxReached = "max_reached"
        case seekCount = "seek_count"
        case realRatio = "real_ratio"
    }
}

struct PeachWatchLaterResponse: Decodable, Sendable {
    let ok: Bool?
    let watchLater: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case watchLater = "watch_later"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .watchLater) {
            watchLater = v
        } else {
            watchLater = (try? c.decodeIfPresent(Int.self, forKey: .watchLater)) == 1
        }
    }
}

struct PeachEntity: Decodable, Sendable {
    let id: Int
    let kind: String
    let canonicalName: String
    let aliases: [String]
    let tags: [PeachFacet]
    let relatedPerformers: [PeachFacet]
    let assetCount: Int
    let representativeAssetID: Int?
    let hasImage: Bool
    let imageVersion: String?
    let hasLogo: Bool?
    let logoVersion: String?
    let favorite: Bool?
    let memberCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, aliases, tags, favorite
        case canonicalName = "canonical_name"
        case relatedPerformers = "related_performers"
        case assetCount = "asset_count"
        case representativeAssetID = "representative_asset_id"
        case hasImage = "has_image"
        case imageVersion = "image_version"
        case hasLogo = "has_logo"
        case logoVersion = "logo_version"
        case memberCount = "member_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        canonicalName = (try? c.decodeIfPresent(String.self, forKey: .canonicalName)) ?? ""
        aliases = (try? c.decodeIfPresent([String].self, forKey: .aliases)) ?? []
        tags = (try? c.decodeIfPresent([PeachFacet].self, forKey: .tags)) ?? []
        relatedPerformers = (try? c.decodeIfPresent([PeachFacet].self, forKey: .relatedPerformers)) ?? []
        assetCount = (try? c.decodeIfPresent(Int.self, forKey: .assetCount)) ?? 0
        representativeAssetID = try? c.decodeIfPresent(Int.self, forKey: .representativeAssetID)
        hasImage = (try? c.decodeIfPresent(Bool.self, forKey: .hasImage)) ?? false
        imageVersion = try? c.decodeIfPresent(String.self, forKey: .imageVersion)
        hasLogo = try? c.decodeIfPresent(Bool.self, forKey: .hasLogo)
        logoVersion = try? c.decodeIfPresent(String.self, forKey: .logoVersion)
        favorite = try? c.decodeIfPresent(Bool.self, forKey: .favorite)
        memberCount = try? c.decodeIfPresent(Int.self, forKey: .memberCount)
    }
}


struct PeachPlaylist: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let itemCount: Int
    let currentAssetID: Int?
    let items: [PeachItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case itemCount = "item_count"
        case currentAssetID = "current_asset_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        itemCount = (try? c.decodeIfPresent(Int.self, forKey: .itemCount)) ?? 0
        currentAssetID = try? c.decodeIfPresent(Int.self, forKey: .currentAssetID)
        items = try? c.decodeIfPresent([PeachItem].self, forKey: .items)
    }
}

struct PeachPlaylistsResponse: Decodable, Sendable {
    let items: [PeachPlaylist]
}

struct PeachPlaylistResponse: Decodable, Sendable {
    let ok: Bool?
    let playlist: PeachPlaylist?
}

struct PeachStats: Decodable, Sendable {
    let recent: [PeachRecentItem]
    let consumption: PeachConsumption?

    enum CodingKeys: String, CodingKey { case recent, consumption }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recent = (try? c.decodeIfPresent([PeachRecentItem].self, forKey: .recent)) ?? []
        consumption = try? c.decodeIfPresent(PeachConsumption.self, forKey: .consumption)
    }
}

struct PeachConsumption: Decodable, Sendable {
    let played: Int?
    let playSeconds: Double?
    let oTotal: Int?
    let liked: Int?
    let dislike: Int?
    let seen: Int?

    enum CodingKeys: String, CodingKey {
        case played, liked, dislike, seen
        case playSeconds = "play_seconds"
        case oTotal = "o_total"
    }
}

struct PeachRecentItem: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let creator: String?
    let playSeconds: Double?
    let duration: Double?
    let leaveRatio: Double?
    let oCount: Int?
    let lastPlayed: Double?
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case id, name, creator, duration, kind
        case playSeconds = "play_seconds"
        case leaveRatio = "leave_ratio"
        case oCount = "o_count"
        case lastPlayed = "last_played"
    }

    var progress: Double {
        if let leaveRatio, leaveRatio > 0 { return min(max(leaveRatio, 0), 1) }
        if let playSeconds, let duration, duration > 0 { return min(max(playSeconds / duration, 0), 1) }
        return 0
    }
}

struct PeachTasks: Decodable, Sendable {
    let running: [PeachTask]
    let finished: [PeachTask]
    let skipped: [PeachTask]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decodeIfPresent([PeachTask].self, forKey: .running)) ?? []
        finished = (try? c.decodeIfPresent([PeachTask].self, forKey: .finished)) ?? []
        skipped = (try? c.decodeIfPresent([PeachTask].self, forKey: .skipped)) ?? []
    }

    enum CodingKeys: String, CodingKey { case running, finished, skipped }
}

struct PeachTask: Decodable, Identifiable, Sendable {
    let id: Int
    let taskKey: String
    let taskLabel: String
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let progressCurrent: Int?
    let progressTotal: Int?
    let progressLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case taskKey = "task_key"
        case taskLabel = "task_label"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case progressCurrent = "progress_current"
        case progressTotal = "progress_total"
        case progressLabel = "progress_label"
    }
}

struct PeachConfiguration: Decodable, Sendable {
    let editable: Bool?
    let mediaDirs: [String]
    let libraryCount: Int?
    let port: Int?
    let facts: [PeachFact]
    let accessMode: String?

    enum CodingKeys: String, CodingKey {
        case editable, port, facts
        case mediaDirs = "media_dirs"
        case libraryCount = "library_count"
        case access
    }

    struct Access: Decodable, Sendable { let mode: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        editable = try? c.decodeIfPresent(Bool.self, forKey: .editable)
        mediaDirs = (try? c.decodeIfPresent([String].self, forKey: .mediaDirs)) ?? []
        libraryCount = try? c.decodeIfPresent(Int.self, forKey: .libraryCount)
        port = try? c.decodeIfPresent(Int.self, forKey: .port)
        facts = (try? c.decodeIfPresent([PeachFact].self, forKey: .facts)) ?? []
        accessMode = (try? c.decodeIfPresent(Access.self, forKey: .access))?.mode
    }
}

struct PeachFact: Decodable, Hashable, Sendable {
    let term: String
    let value: String
}

struct PeachDownloads: Decodable, Sendable {
    let available: Bool?
    let tasks: [PeachDownloadTask]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try? c.decodeIfPresent(Bool.self, forKey: .available)
        tasks = (try? c.decodeIfPresent([PeachDownloadTask].self, forKey: .tasks)) ?? []
    }

    enum CodingKeys: String, CodingKey { case available, tasks }
}

struct PeachDownloadTask: Decodable, Identifiable, Sendable {
    let id: Int?
    let title: String?
    let status: String?
    let progress: Double?
}

struct PeachFollow: Decodable, Sendable {
    let counts: PeachFollowCounts?
    let sources: [PeachFollowSource]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try? c.decodeIfPresent(PeachFollowCounts.self, forKey: .counts)
        sources = (try? c.decodeIfPresent([PeachFollowSource].self, forKey: .sources)) ?? []
    }

    enum CodingKeys: String, CodingKey { case counts, sources }
}

struct PeachFollowCounts: Decodable, Sendable {
    let new: Int?
    let seen: Int?
    let saved: Int?
    let ignored: Int?
}

struct PeachFollowSource: Decodable, Identifiable, Sendable {
    let id: Int?
    let label: String?
    let kind: String?
}

struct PeachLibraryProcessing: Decodable, Sendable {
    let status: String?
    let stage: String?
    let checked: Int?
    let total: Int?
    let issueCount: Int?
    let candidates: Int?

    enum CodingKeys: String, CodingKey {
        case status, stage, checked, total, candidates
        case issueCount = "issue_count"
    }
}

enum CatalogState: String, CaseIterable, Identifiable, Sendable {
    case all = ""
    case fresh
    case later
    case flagged
    case played

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .fresh: return "没看过"
        case .later: return "稍后看"
        case .flagged: return "已标记"
        case .played: return "看过"
        }
    }
}

enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
    case seed, rating, o, plays, dur, size, new, played, release

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seed: return "随机"
        case .rating: return "评分"
        case .o: return "高潮计数"
        case .plays: return "观看次数"
        case .dur: return "时长"
        case .size: return "体积"
        case .new: return "入库时间"
        case .played: return "观看时间"
        case .release: return "发行时间"
        }
    }

    var supportsDirection: Bool { self != .seed }
}

enum PeachDensity: String, CaseIterable, Identifiable, Sendable {
    case big
    case dense

    var id: String { rawValue }
    var label: String { self == .big ? "大图" : "小图" }
}

enum WallImage: String, CaseIterable, Identifiable, Sendable {
    case cover
    case thumbnail

    var id: String { rawValue }
    var label: String { self == .cover ? "封面" : "缩略图" }
}

struct LibraryFilter: Equatable, Sendable {
    var libraryID = ""
    var query = ""
    var performer: String?
    var studio: String?
    var tag: String?
    var series: String?
    var creator: String?
    var javOnly = true
    var state: CatalogState = .all
    var sort: CatalogSort = .seed
    var ascending = false
    var seed = LibraryFilter.dailySeed

    init(libraryID: String = "", query: String = "", performer: String? = nil,
         studio: String? = nil, tag: String? = nil, javOnly: Bool = true,
         state: CatalogState = .all, sort: CatalogSort = .seed, ascending: Bool = false,
         seed: Int = LibraryFilter.dailySeed) {
        self.libraryID = libraryID
        self.query = query
        self.performer = performer
        self.studio = studio
        self.tag = tag
        self.javOnly = javOnly
        self.state = state
        self.sort = sort
        self.ascending = ascending
        self.seed = seed
    }

    var hasActiveFilter: Bool {
        !query.isEmpty || performer != nil || studio != nil || tag != nil
            || series != nil || creator != nil || state != .all
    }

    /// Peach's home grid uses a date-derived seed when no explicit sort is
    /// chosen: the same day keeps one order, the next day changes it.
    static var dailySeed: Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let value = Int(formatter.string(from: Date())) ?? 1
        return value % 9973 == 0 ? 7 : value % 9973
    }
}
