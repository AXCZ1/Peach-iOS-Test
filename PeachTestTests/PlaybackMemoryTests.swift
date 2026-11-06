import XCTest
@testable import PeachTestCore

final class PlaybackMemoryTests: XCTestCase {
    func testPositionRoundTripAndClear() {
        let memory = PlayerMemory.shared
        let id = 987_654
        memory.clear(id)
        XCTAssertNil(memory.position(for: id))
        memory.save(123.5, for: id)
        XCTAssertEqual(memory.position(for: id) ?? 0, 123.5, accuracy: 0.001)
        memory.clear(id)
        XCTAssertNil(memory.position(for: id))
    }

    func testNegativeOrNonFinitePositionsAreIgnored() {
        let memory = PlayerMemory.shared
        let id = 987_655
        memory.clear(id)
        memory.save(-4, for: id)
        XCTAssertNil(memory.position(for: id))
        memory.save(.nan, for: id)
        XCTAssertNil(memory.position(for: id))
        memory.clear(id)
    }

    func testDailySeedIsStableWithinADayAndInRange() {
        let first = LibraryFilter.dailySeed
        let second = LibraryFilter.dailySeed
        XCTAssertEqual(first, second)
        XCTAssertTrue((1...9972).contains(first))
    }
}
