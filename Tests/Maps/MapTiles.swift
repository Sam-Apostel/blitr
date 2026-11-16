import MapKit
import SwiftUI

// Maps for Tests/Maps/tiles.sh, which draws them on generated tiles (--map-tiles) that carry a red dot at
// `tileCenter` and a blue dot at `tileOffset`, and checks where the dots land.

let tileCenter = CLLocationCoordinate2D(latitude: 50.85, longitude: 4.35)
let tileOffset = CLLocationCoordinate2D(latitude: 51.10, longitude: 4.70)

/// A map rect `width` map points wide and as tall, centred on `tileCenter`.
func tileRect(width: Double) -> MKMapRect {
    let p = MKMapPoint(tileCenter)
    return MKMapRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)
}

#Preview("Rect") {
    // About 4 degrees across: zoom 7 tiles.
    Map(initialPosition: .rect(tileRect(width: MKMapSize.world.width / 90)))
}

#Preview("Deep") {
    // About 1.4 degrees across: deeper than the deepest tiles (zoom 8), which are enlarged.
    Map(initialPosition: .rect(tileRect(width: MKMapSize.world.width / 256)))
}

#Preview("Heading") {
    Map(initialPosition: .camera(MapCamera(centerCoordinate: tileCenter, distance: 400_000, heading: 30)))
}
