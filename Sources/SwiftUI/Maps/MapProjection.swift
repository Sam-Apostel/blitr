// Web Mercator projection of a resolved map camera into a view's frame.

import Foundation

struct MapProjection {
    /// Map point at the center of the frame.
    var center: MKMapPoint
    /// Points (screen) per map point.
    var scale: Double
    var size: CGSize
    /// Degrees clockwise from north of the direction that points up.
    var heading: Double = 0
    var pitch: Double = 0

    static let world = MKMapSize.world.width
    /// Vertical field of view of MapKit's camera, used to relate a camera distance to a zoom.
    static let fieldOfView = 30.0
    static var distanceFactor: Double { 2 * tan(fieldOfView / 2 * .pi / 180) }

    func point(_ p: MKMapPoint) -> CGPoint {
        var dx = p.x - center.x
        if dx > Self.world / 2 { dx -= Self.world } else if dx < -Self.world / 2 { dx += Self.world }
        return screen(dx: dx, dy: p.y - center.y)
    }
    func point(_ c: CLLocationCoordinate2D) -> CGPoint { point(MKMapPoint(c)) }

    /// A connected run of map points: each one is unwrapped next to the previous, so lines that
    /// cross the 180th meridian take the short way.
    func points(_ run: [MKMapPoint]) -> [CGPoint] {
        guard let first = run.first else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(run.count)
        var dx = first.x - center.x
        if dx > Self.world / 2 { dx -= Self.world } else if dx < -Self.world / 2 { dx += Self.world }
        var previousX = first.x
        out.append(screen(dx: dx, dy: first.y - center.y))
        for p in run.dropFirst() {
            var step = p.x - previousX
            if step > Self.world / 2 { step -= Self.world } else if step < -Self.world / 2 { step += Self.world }
            dx += step
            previousX = p.x
            out.append(screen(dx: dx, dy: p.y - center.y))
        }
        return out
    }

    private func screen(dx: Double, dy: Double) -> CGPoint {
        let t = -heading * .pi / 180
        let rx = dx * cos(t) - dy * sin(t), ry = dx * sin(t) + dy * cos(t)
        return CGPoint(x: size.width / 2 + rx * scale, y: size.height / 2 + ry * scale)
    }

    func mapPoint(_ p: CGPoint) -> MKMapPoint {
        let rx = (Double(p.x) - size.width / 2) / scale, ry = (Double(p.y) - size.height / 2) / scale
        let t = heading * .pi / 180
        let dx = rx * cos(t) - ry * sin(t), dy = rx * sin(t) + ry * cos(t)
        var x = (center.x + dx).truncatingRemainder(dividingBy: Self.world)
        if x < 0 { x += Self.world }
        return MKMapPoint(x: x, y: center.y + dy)
    }
    func coordinate(_ p: CGPoint) -> CLLocationCoordinate2D { mapPoint(p).coordinate }

    var visibleRect: MKMapRect {
        let w = size.width / scale, h = size.height / scale
        let t = heading * .pi / 180
        let bw = abs(w * cos(t)) + abs(h * sin(t)), bh = abs(w * sin(t)) + abs(h * cos(t))
        return MKMapRect(x: center.x - bw / 2, y: center.y - bh / 2, width: bw, height: bh)
    }
    var region: MKCoordinateRegion { MKCoordinateRegion(visibleRect) }
    var metersPerPoint: Double { MKMetersPerMapPointAtLatitude(center.coordinate.latitude) / scale }
    var camera: MapCamera {
        let visibleHeight = Double(size.height) * metersPerPoint
        return MapCamera(centerCoordinate: center.coordinate, distance: visibleHeight / Self.distanceFactor, heading: heading, pitch: pitch)
    }
    var context: MapCameraUpdateContext {
        MapCameraUpdateContext(camera: camera, region: region, rect: visibleRect, scaleFactor: scale)
    }

    // MARK: Resolving a camera position

    struct Insets { var top: Double, left: Double, bottom: Double, right: Double }

    /// Fits a map rect into the frame (aspect fit), centered.
    static func fitting(_ rect: MKMapRect, in size: CGSize, insets: Insets = Insets(top: 0, left: 0, bottom: 0, right: 0)) -> MapProjection {
        let w = max(1, Double(size.width) - insets.left - insets.right), h = max(1, Double(size.height) - insets.top - insets.bottom)
        let scale = min(w / max(rect.width, 1e-6), h / max(rect.height, 1e-6))
        // Center the rect in the inset area: shift the frame center by half the inset difference.
        let cx = rect.midX - (insets.left - insets.right) / 2 / scale
        let cy = rect.midY - (insets.top - insets.bottom) / 2 / scale
        return MapProjection(center: MKMapPoint(x: cx, y: cy), scale: scale, size: size)
    }

    static func camera(_ camera: MapCamera, in size: CGSize) -> MapProjection {
        let visibleHeight = max(1, camera.distance) * distanceFactor
        let metersPerPoint = visibleHeight / max(1, Double(size.height))
        let scale = MKMetersPerMapPointAtLatitude(camera.centerCoordinate.latitude) / metersPerPoint
        return MapProjection(center: MKMapPoint(camera.centerCoordinate), scale: scale, size: size, heading: camera.heading, pitch: camera.pitch)
    }

    static func resolve(_ position: MapCameraPosition, elements: [MapElement], size: CGSize, bounds: MapCameraBounds?,
                        markerScale: Double, safeArea: EdgeInsets = EdgeInsets()) -> MapProjection {
        var projection: MapProjection
        switch position.kind {
        case .automatic: projection = automatic(elements, size: size, markerScale: markerScale, safeArea: safeArea)
        case .region(let r): projection = fitting(r.mapRect, in: size)
        case .rect(let r): projection = fitting(r, in: size)
        case .camera(let c): projection = camera(c, in: size)
        case .item(let item, _):
            projection = camera(MapCamera(centerCoordinate: item.mapCoordinate, distance: 1500), in: size)
        case .userLocation(_, let fallback):
            projection = resolve(fallback, elements: elements, size: size, bounds: nil, markerScale: markerScale, safeArea: safeArea)
        }
        if let bounds { projection.clamp(to: bounds) }
        projection.clampToWorld()
        return projection
    }

    /// `.automatic`: everything the app put on the map, with room for marker balloons and titles.
    static func automatic(_ elements: [MapElement], size: CGSize, markerScale: Double, safeArea: EdgeInsets = EdgeInsets()) -> MapProjection {
        let points = elements.flatMap(\.framingPoints)
        guard !points.isEmpty else {
            // Nothing to frame: the whole world, as wide as the view.
            let scale = Double(size.width) / world
            var p = MapProjection(center: MKMapPoint(CLLocationCoordinate2D(latitude: 25, longitude: 10)), scale: scale, size: size)
            p.clampToWorld()
            return p
        }
        var rect = unwrappedBounds(points)
        let hasMarkers = elements.contains { if case .marker = $0.kind { return true }; return false }
        let hasPins = elements.contains { !$0.isOverlay }
        let hasTitles = elements.contains { $0.hasTitle && $0.titles != .hidden && !$0.isOverlay }
        let base = max(16, min(Double(size.width), Double(size.height)) * 0.08)
        let insets = Insets(top: safeArea.top + base + (hasMarkers ? 40 * markerScale : hasPins ? 20 * markerScale : 0),
                            left: safeArea.leading + base + (hasPins ? 16 * markerScale : 0),
                            bottom: safeArea.bottom + base + (hasTitles ? 18 * markerScale : hasPins ? 16 * markerScale : 0),
                            right: safeArea.trailing + base + (hasPins ? 16 * markerScale : 0))
        // A single place (or a tight cluster) is shown at street level rather than infinitely close.
        let minimumSpan = 900 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
        if rect.width < minimumSpan && rect.height < minimumSpan {
            rect = MKMapRect(x: rect.midX - minimumSpan / 2, y: rect.midY - minimumSpan / 2, width: minimumSpan, height: minimumSpan)
        }
        return fitting(rect, in: size, insets: insets)
    }

    /// Bounding rect of points that may straddle the 180th meridian (picks the narrower wrap).
    static func unwrappedBounds(_ points: [MKMapPoint]) -> MKMapRect {
        let plain = MKMapRect.bounding(points)
        let shifted = MKMapRect.bounding(points.map { MKMapPoint(x: $0.x < world / 2 ? $0.x + world : $0.x, y: $0.y) })
        return shifted.width < plain.width ? shifted : plain
    }

    mutating func clamp(to bounds: MapCameraBounds) {
        let distance = camera.distance
        var target = distance
        if let minimum = bounds.minimumDistance { target = max(target, minimum) }
        if let maximum = bounds.maximumDistance { target = min(target, maximum) }
        if target != distance { scale *= distance / target }
        if let r = bounds.centerRect, !r.isNull {
            center.x = min(max(center.x, r.minX), r.maxX)
            center.y = min(max(center.y, r.minY), r.maxY)
        }
    }

    /// MapKit never zooms out past one world width, nor shows space above or below the poles.
    mutating func clampToWorld() {
        scale = max(scale, Double(size.width) / Self.world * 0.999)
        let halfHeight = Double(size.height) / scale / 2
        if halfHeight * 2 >= Self.world {
            center.y = Self.world / 2
        } else {
            center.y = min(max(center.y, halfHeight), Self.world - halfHeight)
        }
        center.x = center.x.truncatingRemainder(dividingBy: Self.world)
        if center.x < 0 { center.x += Self.world }
    }
}
