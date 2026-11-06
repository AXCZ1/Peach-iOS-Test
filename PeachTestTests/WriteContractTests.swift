import XCTest
@testable import PeachTestCore

final class WriteContractTests: XCTestCase {
    func testItemDecodesPersonalRecordFields() throws {
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("""
        {"id":40784,"name":"juq-575.mp4","medium":"video","code":"JUQ-575",
         "has_cover":true,"cover_key":"JUQ-575","performers":["木下凛々子"],
         "tags":["人妻"],"o_count":2,"rating":80,"watch_later":1,"liked":1,
         "feedback":"seen","leave_ratio":0.25,"play_count":3,
         "entity_refs":{"performer":[{"id":47,"name":"木下凛々子","has_image":true}]}}
        """.utf8))
        XCTAssertEqual(item.oCount, 2)
        XCTAssertEqual(item.ratingStars, 4)
        XCTAssertTrue(item.watchLater)
        XCTAssertTrue(item.liked)
        XCTAssertTrue(item.isFlagged)
        XCTAssertEqual(item.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(item.performerRefs.first?.id, 47)
    }

    func testDensityAndWallImagePersistThroughTheirRawValues() {
        XCTAssertEqual(PeachDensity(rawValue: "big"), .big)
        XCTAssertEqual(PeachDensity(rawValue: "dense"), .dense)
        XCTAssertEqual(WallImage(rawValue: "cover"), .cover)
        XCTAssertEqual(WallImage(rawValue: "thumbnail"), .thumbnail)
    }

    func testSortDirectionIsHiddenOnlyForRandom() {
        XCTAssertFalse(CatalogSort.seed.supportsDirection)
        for sort in CatalogSort.allCases where sort != .seed {
            XCTAssertTrue(sort.supportsDirection, sort.rawValue)
        }
    }

    func testWatchLaterResponseAcceptsBoolAndLegacyInteger() throws {
        let on = try JSONDecoder().decode(PeachWatchLaterResponse.self,
                                          from: Data("{\"ok\":true,\"watch_later\":true}".utf8))
        XCTAssertTrue(on.watchLater)
        let legacy = try JSONDecoder().decode(PeachWatchLaterResponse.self,
                                              from: Data("{\"ok\":true,\"watch_later\":1}".utf8))
        XCTAssertTrue(legacy.watchLater)
    }

    func testActivityAndFeedbackDecodeServerReceipts() throws {
        let feedback = try JSONDecoder().decode(PeachFeedbackResponse.self,
                                                from: Data("{\"ok\":true,\"o_count\":3,\"rating\":80}".utf8))
        XCTAssertEqual(feedback.oCount, 3)
        XCTAssertEqual(feedback.rating, 80)
        let activity = try JSONDecoder().decode(PeachActivityResponse.self,
                                                from: Data("{\"ok\":true,\"play_seconds\":10,\"leave_ratio\":0.01,\"seek_count\":1}".utf8))
        XCTAssertEqual(activity.playSeconds, 10)
        XCTAssertEqual(activity.seekCount, 1)
    }
}
