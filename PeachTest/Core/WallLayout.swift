import Foundation

struct WallCell: Sendable {
    let x: Int, y: Int, columns: Int, rows: Int
}
struct WallPlacement: Identifiable, Equatable {
    let id: String
    var index: Int
    var rect: CGRect
}
struct WallCamera: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 0.68
    func zoomed(by factor: CGFloat, anchor: CGPoint) -> Self {
        let next = min(1.6, max(0.65, scale * factor))
        return Self(x: anchor.x - (anchor.x - x) * next / scale,
                    y: anchor.y - (anchor.y - y) * next / scale, scale: next)
    }
}

/// Peach 0.52.0 Folia geometry: 12 tiles per 12×8 block, mirrored templates,
/// three block columns for finite results, stable positions for exploration.
enum WallLayout {
    static let pitch: CGFloat = 103.36
    static let gap: CGFloat = 6.08
    static let blockWidth = 12 * pitch
    static let blockHeight = 8 * pitch
    static func mod(_ value: Int, _ divisor: Int) -> Int { (value % divisor + divisor) % divisor }
    static func choice(x: Int, y: Int) -> (Int, Int) {
        var hash = UInt32(truncatingIfNeeded: x) &* 2654435761 ^ UInt32(truncatingIfNeeded: y) &* 2246822507
        hash = (hash ^ (hash >> 15)) &* 739982445
        hash ^= hash >> 12
        return (mod(x + y * 2, WallTemplates.base.count), Int(hash % 4))
    }
    static func frame(x: Int, y: Int, slot: Int, focused: Int? = nil) -> CGRect {
        let (template, mirror) = choice(x: x, y: y)
        let cell = focused.map { WallTemplates.focused[template][$0][slot] } ?? WallTemplates.base[template][slot]
        let cx = mirror == 1 || mirror == 3 ? 12 - cell.x - cell.columns : cell.x
        let cy = mirror == 2 || mirror == 3 ? 8 - cell.y - cell.rows : cell.y
        return CGRect(x: CGFloat(x * 12 + cx) * pitch, y: CGFloat(y * 8 + cy) * pitch,
                      width: CGFloat(cell.columns) * pitch - gap, height: CGFloat(cell.rows) * pitch - gap)
    }
    static func visible(count: Int, finite: Bool, camera: WallCamera, viewport: CGSize, focus: String? = nil) -> [WallPlacement] {
        guard count > 0, viewport.width > 0, viewport.height > 0 else { return [] }
        let margin = 180 / camera.scale
        let area = CGRect(x: -camera.x / camera.scale - margin, y: -camera.y / camera.scale - margin,
                          width: viewport.width / camera.scale + margin * 2, height: viewport.height / camera.scale + margin * 2)
        let blockCount = (count + 11) / 12, columns = finite ? 3 : min(3, blockCount)
        let rows = (blockCount + columns - 1) / columns
        let selected = focus?.split(separator: ":").compactMap { Int($0) }
        var result: [WallPlacement] = []
        for y in Int(floor(area.minY / blockHeight))...Int(floor(area.maxY / blockHeight)) {
            for x in Int(floor(area.minX / blockWidth))...Int(floor(area.maxX / blockWidth)) {
                if finite && (x < 0 || y < 0 || x >= columns || y >= rows) { continue }
                let focused = selected?.count == 3 && selected?[0] == x && selected?[1] == y ? selected?[2] : nil
                for slot in 0..<12 {
                    let index = (mod(y, rows) * columns + mod(x, columns)) * 12 + slot
                    if finite && index >= count { continue }
                    let rect = frame(x: x, y: y, slot: slot, focused: focused)
                    if rect.intersects(area) {
                        result.append(WallPlacement(id: "\(x):\(y):\(slot)", index: index % count, rect: rect))
                    }
                }
            }
        }
        return result
    }
    static func bounded(_ camera: WallCamera, count: Int, viewport: CGSize, finite: Bool) -> WallCamera {
        guard finite, count > 0 else { return camera }
        var width: CGFloat = 0, height: CGFloat = 0
        for i in max(0, count - 36)..<count {
            let b = i / 12, r = frame(x: b % 3, y: b / 3, slot: i % 12)
            width = max(width, r.maxX); height = max(height, r.maxY)
        }
        if count >= 36 { width = 3 * blockWidth - gap }
        return WallCamera(x: min(16, max(min(16, viewport.width - width * camera.scale - 16), camera.x)),
                          y: min(16, max(min(16, viewport.height - height * camera.scale - 16), camera.y)), scale: camera.scale)
    }
}

struct WallExploration {
    private(set) var positions: [String: Int] = [:]
    private(set) var used: Set<Int> = []
    private var cursor = 0
    private var repeatCursor = 0
    mutating func assign(_ placements: [WallPlacement], count: Int, hasMore: Bool) -> [WallPlacement] {
        placements.map { value in
            var tile = value
            if let index = positions[tile.id] { tile.index = index; return tile }
            if used.count < count {
                while used.contains(cursor % count) { cursor += 1 }
                tile.index = cursor % count; cursor += 1; used.insert(tile.index)
            } else if hasMore { tile.index = -1; return tile }
            else { tile.index = repeatCursor % count; repeatCursor += 1 }
            positions[tile.id] = tile.index
            return tile
        }
    }
}
