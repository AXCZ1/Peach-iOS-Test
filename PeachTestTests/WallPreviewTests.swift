import Foundation
import XCTest
@testable import PeachTestCore

final class WallPreviewTests: XCTestCase {
    func testUpstreamTemplatesAndEveryFocusReflowDoNotOverlap() {
        for x in -2...2 { for y in -2...2 {
            for focus in [Int?.none] + (0..<12).map({ Optional($0) }) {
                let frames = (0..<12).map { WallLayout.frame(x: x, y: y, slot: $0, focused: focus) }
                for i in frames.indices {
                    XCTAssertGreaterThan(frames[i].width, 0)
                    XCTAssertGreaterThan(frames[i].height, 0)
                    XCTAssertGreaterThanOrEqual(frames[i].minX, CGFloat(x) * WallLayout.blockWidth - 0.01)
                    XCTAssertLessThanOrEqual(frames[i].maxX, CGFloat(x + 1) * WallLayout.blockWidth + 0.01)
                    for j in frames.indices where j > i { XCTAssertFalse(frames[i].intersects(frames[j]), "overlap at \(x):\(y) focus \(String(describing: focus)) slots \(i),\(j)") }
                }
            }
        } }
    }
    func testFiniteWallOnlyReturnsExistingUniqueItems() {
        let tiles = WallLayout.visible(count: 54, finite: true, camera: WallCamera(scale: 0.68), viewport: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(tiles.count, 54)
        XCTAssertEqual(Set(tiles.map(\.index)), Set(0..<54))
        XCTAssertTrue(tiles.allSatisfy { $0.rect.minX >= 0 && $0.rect.minY >= 0 })
    }
    func testExplorationRetainsLocationsAsNewPagesArrive() {
        var exploration = WallExploration()
        let visible = WallLayout.visible(count: 12, finite: false, camera: WallCamera(), viewport: CGSize(width: 1400, height: 1600))
        let first = exploration.assign(visible, count: 12, hasMore: true)
        XCTAssertEqual(Set(first.filter { $0.index >= 0 }.map(\.index)).count, 12)
        XCTAssertTrue(first.contains { $0.index == -1 })
        let next = exploration.assign(visible, count: 60, hasMore: false)
        for old in first where old.index >= 0 { XCTAssertEqual(next.first { $0.id == old.id }?.index, old.index) }
        XCTAssertTrue(next.allSatisfy { $0.index >= 0 && $0.index < 60 })
    }
    func testZoomKeepsTheTouchedWorldPointFixed() {
        let camera = WallCamera(x: -123, y: 88, scale: 0.8)
        let anchor = CGPoint(x: 120, y: 260)
        let next = camera.zoomed(by: 1.3, anchor: anchor)
        XCTAssertEqual((anchor.x - camera.x) / camera.scale, (anchor.x - next.x) / next.scale, accuracy: 0.0001)
        XCTAssertEqual((anchor.y - camera.y) / camera.scale, (anchor.y - next.y) / next.scale, accuracy: 0.0001)
    }
    func testDwellChoosesOneVisibleCardAndRejectsSliver() {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 500)
        XCTAssertEqual(DwellSelection.candidate(bounds: [1:CGRect(x: 0, y: -400, width: 400, height: 500), 2:CGRect(x: 0, y: 100, width: 400, height: 500)], viewport: viewport), 2)
        XCTAssertNil(DwellSelection.candidate(bounds: [1:CGRect(x: 0, y: 490, width: 400, height: 500)], viewport: viewport))
    }
    func testThirtyFramesUseFractionalIntervalAndPartialSheet() throws {
        let data = Data("{\"frames\":30,\"interval\":298.2791277667,\"columns\":10,\"rows\":10,\"source\":\"peach\",\"timestamps\":[89.48]}".utf8)
        let metadata = try JSONDecoder().decode(TimelineMetadata.self, from: data)
        XCTAssertEqual(metadata.frame(at: 8948.37), 29)
        let tile = try XCTUnwrap(metadata.tile(at: 8948.37))
        XCTAssertEqual(tile.sheet, 0)
        XCTAssertEqual(tile.region.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(tile.region.y, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(tile.region.height, 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(metadata.timestamps?.first, 89.48)
    }
}
