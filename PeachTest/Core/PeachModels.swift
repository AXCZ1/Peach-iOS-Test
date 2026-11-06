import Foundation

struct PeachLibrary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let folders: Int
}

struct LibraryResponse: Decodable {
    let libraries: [PeachLibrary]
}

struct PeachPage: Decodable {
    let total: Int?
    let items: [PeachItem]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case total, items
        case hasMore = "has_more"
    }
}

struct PeachItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let code: String?
    let catalogTitle: String?
    let originalTitle: String?
    let studio: String?
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

    enum CodingKeys: String, CodingKey {
        case id, name, code, studio, duration, width, height, size, performers, tags
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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        catalogTitle = try? c.decodeIfPresent(String.self, forKey: .catalogTitle)
        originalTitle = try? c.decodeIfPresent(String.self, forKey: .originalTitle)
        studio = try? c.decodeIfPresent(String.self, forKey: .studio)
        releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        duration = Self.number(c, .duration)
        width = Self.integer(c, .width)
        height = Self.integer(c, .height)
        size = Self.integer64(c, .size)
        performers = Self.strings(c, .performers)
        tags = Self.tags(c, .tags)
        hasCover = (try? c.decodeIfPresent(Bool.self, forKey: .hasCover)) ?? false
        coverKey = (try? c.decodeIfPresent(String.self, forKey: .coverKey)) ?? ""
        coverVersion = try? c.decodeIfPresent(String.self, forKey: .coverVersion)
        hasThumb = (try? c.decodeIfPresent(Bool.self, forKey: .hasThumb)) ?? false
        displayCode = try? c.decodeIfPresent(String.self, forKey: .displayCode)
        displayTitle = try? c.decodeIfPresent(String.self, forKey: .displayTitle)
        isJav = try? c.decodeIfPresent(Bool.self, forKey: .isJav)
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
}

struct PeachFacet: Decodable, Identifiable, Hashable {
    let key: String
    let count: Int

    enum CodingKeys: String, CodingKey { case key = "k", count = "n" }
    var id: String { key }
}

struct PeachFacets: Decodable {
    let tags: [PeachFacet]
    let performers: [PeachFacet]

    enum CodingKeys: String, CodingKey { case tags, performers, tagperformers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = (try? c.decodeIfPresent([PeachFacet].self, forKey: .tags)) ?? []
        performers = (try? c.decodeIfPresent([PeachFacet].self, forKey: .performers))
            ?? (try? c.decodeIfPresent([PeachFacet].self, forKey: .tagperformers))
            ?? []
    }
}

struct PeachIndexResponse: Decodable {
    let items: [PeachFacet]
}

struct StreamPlan: Decodable {
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

struct PeachErrorResponse: Decodable {
    let error: String?
}

struct LibraryFilter: Equatable {
    var libraryID = ""
    var query = ""
    var performer: String?
    var studio: String?
    var tag: String?
    var javOnly = true

    init(libraryID: String = "", query: String = "", performer: String? = nil,
         studio: String? = nil, tag: String? = nil, javOnly: Bool = true) {
        self.libraryID = libraryID
        self.query = query
        self.performer = performer
        self.studio = studio
        self.tag = tag
        self.javOnly = javOnly
    }
}
