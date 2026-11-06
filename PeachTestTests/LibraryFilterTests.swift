import XCTest
@testable import PeachTestCore

final class LibraryFilterTests: XCTestCase {
    func testFilterDefaultsToReadOnlyJavCatalog() {
        let filter = LibraryFilter()
        XCTAssertEqual(filter.libraryID, "")
        XCTAssertEqual(filter.query, "")
        XCTAssertTrue(filter.javOnly)
        XCTAssertNil(filter.performer)
        XCTAssertNil(filter.studio)
        XCTAssertNil(filter.tag)
    }

    func testFacetCountsAndIndexShapeDecode() throws {
        let facets = try JSONDecoder().decode(PeachFacets.self, from: Data("""
        {"tags":[{"k":"人妻","n":14}],"tagperformers":[{"k":"木下凛々子","n":5}]}
        """.utf8))
        XCTAssertEqual(facets.tags.first?.key, "人妻")
        XCTAssertEqual(facets.performers.first?.count, 5)

        let index = try JSONDecoder().decode(PeachIndexResponse.self, from: Data("""
        {"items":[{"entity_id":2,"k":"MADONNA","n":7}]}
        """.utf8))
        XCTAssertEqual(index.items.first?.key, "MADONNA")
    }

    func testAddressValidationKeepsOnlyOrigin() throws {
        let url = try PeachAPI.normalizedBaseURL("http://192.168.5.5:8900/")
        XCTAssertEqual(url.absoluteString, "http://192.168.5.5:8900/")
        XCTAssertThrowsError(try PeachAPI.normalizedBaseURL("192.168.5.5:8900"))
        XCTAssertThrowsError(try PeachAPI.normalizedBaseURL("ftp://192.168.5.5/"))
    }

    func testRequestQueryKeepsLiteralPlusEncoded() throws {
        let base = try PeachAPI.normalizedBaseURL("http://192.168.5.5:8900/")
        let url = PeachAPI.makeURL(baseURL: base, path: "/api/items", query: [
            URLQueryItem(name: "performer", value: "A+B 凛々子")
        ])
        XCTAssertTrue(url.absoluteString.contains("A%2BB%20"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("A+B"), url.absoluteString)
    }
}
