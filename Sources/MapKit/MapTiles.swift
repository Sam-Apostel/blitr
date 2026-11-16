// Offline map tiles (`--map-tiles <dir>`): a directory of `<z>/<x>/<y>.png` raster tiles in the usual web map
// scheme (256-pixel squares of the Web Mercator world, x from the 180th meridian eastward, y from the north),
// drawn under the app's overlays. The user supplies the tiles; none are bundled.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class MapTileSource {
    let directory: String
    /// Zoom levels present in the directory, ascending.
    let zooms: [Int]
    private var images: [String: Image?] = [:]
    private static var sources: [String: MapTileSource] = [:]
    static let extensions = ["png", "jpg", "jpeg", "webp"]

    /// The source for `--map-tiles`, or nil when the flag is not given.
    static var current: MapTileSource? {
        guard let directory = Runtime.current?.config.mapTileDirectory else { return nil }
        if let source = sources[directory] { return source }
        let source = MapTileSource(directory: directory)
        sources[directory] = source
        return source
    }

    init(directory: String) {
        self.directory = directory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        zooms = names.compactMap { Int($0) }.filter { (0...30).contains($0) }.sorted()
    }

    /// The tile image at zoom `z`, column `x`, row `y`, if the directory has it.
    func image(z: Int, x: Int, y: Int) -> Image? {
        let key = "\(z)/\(x)/\(y)"
        if let cached = images[key] { return cached }
        var found: Image?
        for ext in Self.extensions {
            let path = "\(directory)/\(key).\(ext)"
            if FileManager.default.fileExists(atPath: path), let image = UIImage(contentsOfFile: path) {
                found = Image(uiImage: image)
                break
            }
        }
        images[key] = found
        return found
    }

    /// The zoom whose tiles are drawn at a map scale (points per map point): the lowest at which a tile is at
    /// most 256 points wide, so a tile pixel never covers more than a point, capped at the deepest level
    /// the directory has (whose tiles are then enlarged).
    func zoom(forScale scale: Double) -> Int? {
        guard let deepest = zooms.last else { return nil }
        let wanted = Int(ceil(log2(MapProjection.world * scale / 256) - 1e-9))
        return min(max(wanted, zooms.first ?? 0), deepest)
    }
}

/// One tile as drawn: its image over `imageRect`, clipped to the tile's own square, both in the coordinates of
/// the tile's top-left corner, turned by the map's heading.
struct MapTile {
    var image: Image
    var corner: CGPoint
    var side: CGFloat
    var imageRect: CGRect
}

extension MapTileSource {
    /// The tiles that cover the view. A missing tile is drawn from the nearest lower zoom that has its area
    /// (that part of it, enlarged); `missing` counts those no zoom has, where the placeholder surface shows.
    func tiles(for projection: MapProjection) -> (tiles: [MapTile], missing: Int) {
        guard let z = zoom(forScale: projection.scale) else { return ([], 0) }
        let count = 1 << z
        let tileSize = MapProjection.world / Double(count)
        let rect = projection.visibleRect
        let rows = max(0, Int(floor(rect.minY / tileSize)))...min(count - 1, Int(floor(rect.maxY / tileSize)))
        let columns = Int(floor(rect.minX / tileSize))...Int(floor(rect.maxX / tileSize))
        // A pixel (at 3x) of overlap to the right and below hides seams between neighbours: each tile is drawn
        // that much larger, which moves its far edge by at most a third of a point.
        let overlap = (1.0 / 3) / projection.scale
        var tiles: [MapTile] = [], missing = 0
        for row in rows {
            for column in columns {
                let x = ((column % count) + count) % count
                var found: (image: Image, z: Int, column: Int, row: Int)?
                var level = z
                while level >= 0, found == nil {
                    let shift = z - level
                    if let image = image(z: level, x: x >> shift, y: row >> shift) {
                        found = (image, level, column >> shift, row >> shift)
                    }
                    level -= 1
                }
                guard let found else { missing += 1; continue }
                let ancestorSize = MapProjection.world / Double(1 << found.z)
                let origin = CGPoint(x: (Double(found.column) * ancestorSize - Double(column) * tileSize) * projection.scale,
                                     y: (Double(found.row) * ancestorSize - Double(row) * tileSize) * projection.scale)
                let ancestorSide = CGFloat((ancestorSize + overlap) * projection.scale)
                tiles.append(MapTile(image: found.image,
                                     corner: projection.screenPoint(x: Double(column) * tileSize, y: Double(row) * tileSize),
                                     side: CGFloat((tileSize + overlap) * projection.scale),
                                     imageRect: CGRect(origin: origin, size: CGSize(width: ancestorSide, height: ancestorSide))))
            }
        }
        return (tiles, missing)
    }
}

extension MapPainter {
    func drawTiles(_ tiles: [MapTile], in ctx: inout GraphicsContext) {
        for t in tiles {
            var tile = ctx
            tile.translateBy(x: t.corner.x, y: t.corner.y)
            tile.rotate(by: .degrees(-projection.heading))
            tile.clip(to: Path(CGRect(x: 0, y: 0, width: t.side, height: t.side)))
            tile.draw(t.image, in: t.imageRect)
        }
    }
}
