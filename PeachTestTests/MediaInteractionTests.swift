import XCTest
@testable import PeachTestCore

final class MediaInteractionTests: XCTestCase {
    func testExactDurationPreservesSeconds() throws {
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("{\"id\":1,\"duration\":8948.373833}".utf8))
        XCTAssertEqual(item.durationText, "2:29:08")
        XCTAssertEqual(MediaClock.text(3599.99), "59:59")
        XCTAssertEqual(MediaClock.text(3600), "1:00:00")
        XCTAssertEqual(MediaClock.text(8), "0:08")
    }

    func testIndexAndEntityKindsAreSeparate() throws {
        let api = PeachAPI(baseURL: URL(string: "http://example.invalid")!)
        for kind in EntityKind.allCases {
            let image = api.entityImageURL(kind: kind.apiKind, id: 19, version: "v1")
            let query = URLComponents(url: image, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "kind" }?.value, kind.rawValue)
            XCTAssertEqual(query.first { $0.name == "v" }?.value, "v1")
        }
        let facet = try JSONDecoder().decode(PeachFacet.self, from: Data("{\"k\":\"Example\",\"n\":11,\"entity_kind\":\"performer\"}".utf8))
        XCTAssertEqual(facet.entityKind, "performer")
    }

    func testQuarterScreenDoubleTapBoundaries() {
        XCTAssertEqual(PlaybackTap.action(at: 0), .backward)
        XCTAssertEqual(PlaybackTap.action(at: 0.2499), .backward)
        XCTAssertEqual(PlaybackTap.action(at: 0.25), .toggle)
        XCTAssertEqual(PlaybackTap.action(at: 0.7499), .toggle)
        XCTAssertEqual(PlaybackTap.action(at: 0.75), .forward)
        XCTAssertEqual(PlaybackTap.action(at: 1), .forward)
    }

    func testSideTapsExtendTheDeadlineFromTheLatestSkip() {
        var sequence = PlaybackTapSequence()
        XCTAssertEqual(sequence.register(.forward, at: 10), .wait(until: 10.3, showPreviousSingle: false))
        XCTAssertEqual(sequence.register(.forward, at: 10.2), .seek(offset: 10, startsSequence: true))
        XCTAssertEqual(sequence.register(.forward, at: 10.8), .seek(offset: 20, startsSequence: false))
        let fourth = 10.8 + 0.7
        XCTAssertEqual(sequence.register(.forward, at: fourth), .seek(offset: 30, startsSequence: false))
        let expired = fourth + 0.701
        XCTAssertEqual(sequence.register(.forward, at: expired), .wait(until: expired + 0.3, showPreviousSingle: false))
        XCTAssertEqual(sequence.register(.forward, at: expired + 0.1), .seek(offset: 10, startsSequence: true))
    }

    func testSideChainDoesNotCaptureCenterDoubleTapOrOppositeSide() {
        var sequence = PlaybackTapSequence()
        _ = sequence.register(.backward, at: 20)
        XCTAssertEqual(sequence.register(.backward, at: 20.2), .seek(offset: -10, startsSequence: true))
        XCTAssertEqual(sequence.register(.backward, at: 20.3), .seek(offset: -20, startsSequence: false))
        XCTAssertEqual(sequence.register(.toggle, at: 20.4), .wait(until: 20.4 + 0.3, showPreviousSingle: false))
        XCTAssertEqual(sequence.register(.toggle, at: 20.5), .togglePlayback)
        XCTAssertEqual(sequence.register(.forward, at: 20.6), .wait(until: 20.6 + 0.3, showPreviousSingle: false))
        sequence.finishSingle()
        XCTAssertEqual(sequence.register(.forward, at: 21), .wait(until: 21.3, showPreviousSingle: false))
    }

    func testInactivePlanCannotPlayAndUserPauseSurvivesReturn() {
        var state = PlaybackIntent()
        state.isActive = true
        XCTAssertTrue(state.mayPlay)
        state.isActive = false
        XCTAssertFalse(state.mayPlay)
        XCTAssertFalse(state.consumePlayMark(isPlaying: true))
        state.isActive = true
        state.wantsPlayback = false
        state.isActive = false
        state.isActive = true
        XCTAssertFalse(state.mayPlay)
    }

    func testScrubbingRestoresPlayingOrPausedIntent() {
        var state = PlaybackIntent()
        state.isActive = true
        state.scrubbing = true
        XCTAssertFalse(state.mayPlay)
        state.scrubbing = false
        XCTAssertTrue(state.mayPlay)
        state.wantsPlayback = false
        state.scrubbing = true
        state.scrubbing = false
        XCTAssertFalse(state.mayPlay)
    }

    func testVLCSeekWaitsForNewVideoAfterTheClockJumps() {
        var seek = VLCSeekConfirmation(target: 12_000, displayedBeforeJump: 30)
        XCTAssertFalse(seek.observe(position: 2, displayedPictures: 32, playing: true))
        XCTAssertFalse(seek.observe(position: 12, displayedPictures: 32, playing: true))
        XCTAssertTrue(seek.observe(position: 12.2, displayedPictures: 33, playing: true))
    }

    func testVLCPausedSeekAndOtherModesStillUseTheClock() {
        var paused = VLCSeekConfirmation(target: 12_000, displayedBeforeJump: 30)
        XCTAssertTrue(paused.observe(position: 12, displayedPictures: 30, playing: false))
        var legacy = VLCSeekConfirmation(target: 12_000, displayedBeforeJump: nil)
        XCTAssertTrue(legacy.observe(position: 12, displayedPictures: nil, playing: true))
    }

    func testCountOnlyOnFirstRealActivePlayback() {
        var state = PlaybackIntent()
        state.isActive = true
        XCTAssertFalse(state.consumePlayMark(isPlaying: false))
        XCTAssertTrue(state.consumePlayMark(isPlaying: true))
        XCTAssertFalse(state.consumePlayMark(isPlaying: true))
        state.isActive = false
        state.isActive = true
        XCTAssertFalse(state.consumePlayMark(isPlaying: true))
        state.newSession()
        XCTAssertTrue(state.consumePlayMark(isPlaying: true))
    }

    func testUndoCanOnlyConsumeOneRecordedAction() async {
        await MainActor.run {
            var count = 5
            count += 1
            let undo = SingleUseAction { count -= 1 }
            undo.take()?()
            undo.take()?()
            XCTAssertEqual(count, 5)
        }
    }

    func testPaginationBeyondSixtyWithDuplicateTriggersAndRetry() {
        var cursor = ImmersivePagination(seed: 42)
        XCTAssertTrue(cursor.begin())
        XCTAssertFalse(cursor.begin())
        cursor.finish(received: 60, total: 125)
        XCTAssertEqual(cursor.offset, 60)
        XCTAssertFalse(cursor.exhausted)
        XCTAssertTrue(cursor.begin())
        cursor.fail()
        XCTAssertEqual(cursor.offset, 60)
        XCTAssertTrue(cursor.begin())
        cursor.finish(received: 60, total: 125)
        XCTAssertEqual(cursor.offset, 120)
        XCTAssertTrue(cursor.begin())
        cursor.finish(received: 5, total: 125)
        XCTAssertTrue(cursor.exhausted)
        XCTAssertFalse(cursor.begin())
        XCTAssertEqual(cursor.seed, 42)
    }

    func testListDecodesExistingPortraitAndActorData() throws {
        let item = try JSONDecoder().decode(PeachItem.self, from: Data("""
        {"id":40787,"cover_frame":{"cx":0.771,"cy":0.108},
         "poster_box":{"x0":1150,"y0":0,"x1":2184,"y1":1468,"px":[2184,1468],"method":"fold"},
         "performer_entities":[{"id":9,"name":"Example","has_image":true}]}
        """.utf8))
        let region = try XCTUnwrap(item.posterBox?.normalized)
        XCTAssertEqual(region.x, 1150.0 / 2184, accuracy: 0.00001)
        XCTAssertEqual(region.width, 1034.0 / 2184, accuracy: 0.00001)
        XCTAssertEqual(item.performerRefs.first?.id, 9)
        XCTAssertEqual(item.replacing(oCount: 5).posterBox, item.posterBox)
    }

    func testTimelineTilesIncludePartialLastSheet() throws {
        let meta = try JSONDecoder().decode(TimelineMetadata.self, from: Data("{\"frames\":205,\"interval\":10,\"columns\":10,\"rows\":10,\"source\":\"peach\"}".utf8))
        XCTAssertEqual(meta.tile(at: 999)?.sheet, 0)
        XCTAssertEqual(meta.tile(at: 1000)?.sheet, 1)
        let tail = try XCTUnwrap(meta.tile(at: 10000))
        XCTAssertEqual(tail.sheet, 2)
        XCTAssertEqual(tail.region, ImageRegion(x: 0.4, y: 0, width: 0.1, height: 1))
        XCTAssertNil(meta.tile(at: -1))
    }

    func testExternalCuesAndCachedFallbackDecode() throws {
        let meta = try JSONDecoder().decode(TimelineMetadata.self, from: Data("""
        {"frames":2,"columns":1,"rows":1,"source":"webvtt","cues":[[0,10],[20,30]],
         "fallback":{"frames":100,"interval":10,"source":"peach"}}
        """.utf8))
        XCTAssertEqual(meta.tile(at: 5)?.sheet, 0)
        XCTAssertNil(meta.tile(at: 15))
        XCTAssertEqual(meta.tile(at: 30)?.sheet, 1)
        XCTAssertNotNil(meta.fallback?.value.tile(at: 15))
    }

    func testNineGridMatchesBrowserSegments() {
        XCTAssertEqual(TimelineTile.nineGrid(time: 0, duration: 900), ImageRegion(x: 0, y: 0, width: 1.0/3, height: 1.0/3))
        XCTAssertEqual(TimelineTile.nineGrid(time: 450, duration: 900), ImageRegion(x: 1.0/3, y: 1.0/3, width: 1.0/3, height: 1.0/3))
        XCTAssertEqual(TimelineTile.nineGrid(time: 900, duration: 900), ImageRegion(x: 2.0/3, y: 2.0/3, width: 1.0/3, height: 1.0/3))
    }
}
