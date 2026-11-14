// MapKit's planar geometry: spherical Mercator with Apple's world size of 2^28 map points.
// Like Apple's, these value types have no Equatable/Hashable conformance in Swift.

import Foundation

public struct MKCoordinateSpan: @unchecked Sendable {
    public var latitudeDelta: CLLocationDegrees
    public var longitudeDelta: CLLocationDegrees
    public init() { latitudeDelta = 0; longitudeDelta = 0 }
    public init(latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) {
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

public struct MKCoordinateRegion: @unchecked Sendable {
    public var center: CLLocationCoordinate2D
    public var span: MKCoordinateSpan
    public init() { center = CLLocationCoordinate2D(); span = MKCoordinateSpan() }
    public init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        self.center = center
        self.span = span
    }
    public init(center centerCoordinate: CLLocationCoordinate2D, latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) {
        center = centerCoordinate
        // Degrees of latitude per metre is nearly constant; of longitude it shrinks with cos(latitude).
        let metresPerDegreeLat = 111_132.954 - 559.822 * cos(2 * centerCoordinate.latitude * .pi / 180)
            + 1.175 * cos(4 * centerCoordinate.latitude * .pi / 180)
        let metresPerDegreeLon = max(1e-9, .pi / 180 * 6_378_137 * cos(centerCoordinate.latitude * .pi / 180)
            / sqrt(1 - 0.00669437999014 * pow(sin(centerCoordinate.latitude * .pi / 180), 2)))
        span = MKCoordinateSpan(latitudeDelta: latitudinalMeters / metresPerDegreeLat, longitudeDelta: min(360, longitudinalMeters / metresPerDegreeLon))
    }
    public init(_ rect: MKMapRect) {
        let nw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
        let se = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        let mid = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        center = mid
        span = MKCoordinateSpan(latitudeDelta: nw.latitude - se.latitude, longitudeDelta: rect.width / MKMapSize.world.width * 360)
    }
}

public struct MKMapPoint: @unchecked Sendable {
    public var x: Double
    public var y: Double
    public init() { x = 0; y = 0 }
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ coordinate: CLLocationCoordinate2D) {
        let w = MKMapSize.world.width
        let lat = max(-85.05112878, min(85.05112878, coordinate.latitude))
        let s = sin(lat * .pi / 180)
        x = (coordinate.longitude + 180) / 360 * w
        y = (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * w
    }
    public var coordinate: CLLocationCoordinate2D {
        let w = MKMapSize.world.width
        let lon = x / w * 360 - 180
        let n = Double.pi - 2 * .pi * y / w
        let lat = atan(sinh(n)) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    /// Metres between two map points (along the Mercator straight line, as MapKit computes it).
    public func distance(to other: MKMapPoint) -> CLLocationDistance { MKMetersBetweenMapPoints(self, other) }
}

public struct MKMapSize: @unchecked Sendable {
    public var width: Double
    public var height: Double
    public init() { width = 0; height = 0 }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    /// 2^28 map points square: Apple's value.
    public static let world = MKMapSize(width: 268_435_456, height: 268_435_456)
}

public struct MKMapRect: @unchecked Sendable {
    public var origin: MKMapPoint
    public var size: MKMapSize
    public init() { origin = MKMapPoint(); size = MKMapSize() }
    public init(origin: MKMapPoint, size: MKMapSize) { self.origin = origin; self.size = size }
    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = MKMapPoint(x: x, y: y)
        size = MKMapSize(width: width, height: height)
    }
    public static let world = MKMapRect(origin: MKMapPoint(), size: .world)
    public static let null = MKMapRect(x: .infinity, y: .infinity, width: 0, height: 0)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var width: Double { size.width }
    public var height: Double { size.height }
    public var isNull: Bool { origin.x.isInfinite || origin.y.isInfinite }
    public var isEmpty: Bool { isNull || size.width == 0 || size.height == 0 }
    public var spans180thMeridian: Bool { maxX > MKMapSize.world.width }
    public var worldRect: MKMapRect { .world }

    public func contains(_ point: MKMapPoint) -> Bool {
        !isNull && point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
    public func contains(_ rect: MKMapRect) -> Bool {
        !isNull && !rect.isNull && rect.minX >= minX && rect.maxX <= maxX && rect.minY >= minY && rect.maxY <= maxY
    }
    public func intersects(_ rect: MKMapRect) -> Bool {
        !isNull && !rect.isNull && rect.minX < maxX && rect.maxX > minX && rect.minY < maxY && rect.maxY > minY
    }
    public func union(_ rect: MKMapRect) -> MKMapRect {
        if isNull { return rect }
        if rect.isNull { return self }
        let x0 = Swift.min(minX, rect.minX), y0 = Swift.min(minY, rect.minY)
        return MKMapRect(x: x0, y: y0, width: Swift.max(maxX, rect.maxX) - x0, height: Swift.max(maxY, rect.maxY) - y0)
    }
    public func intersection(_ rect: MKMapRect) -> MKMapRect {
        guard intersects(rect) else { return .null }
        let x0 = Swift.max(minX, rect.minX), y0 = Swift.max(minY, rect.minY)
        return MKMapRect(x: x0, y: y0, width: Swift.min(maxX, rect.maxX) - x0, height: Swift.min(maxY, rect.maxY) - y0)
    }
    public func insetBy(dx: Double, dy: Double) -> MKMapRect {
        MKMapRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
    public func offsetBy(dx: Double, dy: Double) -> MKMapRect { MKMapRect(x: minX + dx, y: minY + dy, width: width, height: height) }
    public func offset(by d: Double) -> MKMapRect { offsetBy(dx: d, dy: 0) }
    public func divided(atDistance distance: Double, from edge: CGRectEdge) -> (slice: MKMapRect, remainder: MKMapRect) {
        switch edge {
        case .minXEdge:
            let d = Swift.min(distance, width)
            return (MKMapRect(x: minX, y: minY, width: d, height: height), MKMapRect(x: minX + d, y: minY, width: width - d, height: height))
        case .maxXEdge:
            let d = Swift.min(distance, width)
            return (MKMapRect(x: maxX - d, y: minY, width: d, height: height), MKMapRect(x: minX, y: minY, width: width - d, height: height))
        case .minYEdge:
            let d = Swift.min(distance, height)
            return (MKMapRect(x: minX, y: minY, width: width, height: d), MKMapRect(x: minX, y: minY + d, width: width, height: height - d))
        case .maxYEdge:
            let d = Swift.min(distance, height)
            return (MKMapRect(x: minX, y: maxY - d, width: width, height: d), MKMapRect(x: minX, y: minY, width: width, height: height - d))
        }
    }
    /// The part of a rect that spans the 180th meridian, moved to the world's west side.
    public var remainder: MKMapRect {
        guard spans180thMeridian else { return .null }
        let world = MKMapSize.world.width
        return MKMapRect(x: 0, y: minY, width: maxX - world, height: height)
    }

    /// The rect around a set of map points (internal helper).
    static func bounding(_ points: [MKMapPoint]) -> MKMapRect {
        guard let first = points.first else { return .null }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for p in points.dropFirst() { x0 = Swift.min(x0, p.x); x1 = Swift.max(x1, p.x); y0 = Swift.min(y0, p.y); y1 = Swift.max(y1, p.y) }
        return MKMapRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

extension MKCoordinateRegion {
    /// The Mercator rect that covers the region (internal helper; Apple has no public equivalent).
    var mapRect: MKMapRect {
        let top = MKMapPoint(CLLocationCoordinate2D(latitude: min(90, center.latitude + span.latitudeDelta / 2), longitude: center.longitude))
        let bottom = MKMapPoint(CLLocationCoordinate2D(latitude: max(-90, center.latitude - span.latitudeDelta / 2), longitude: center.longitude))
        let mid = MKMapPoint(center)
        let w = span.longitudeDelta / 360 * MKMapSize.world.width
        return MKMapRect(x: mid.x - w / 2, y: top.y, width: w, height: bottom.y - top.y)
    }
}

/// Metres per map point at a latitude (Apple uses the WGS 84 equatorial radius).
public func MKMetersPerMapPointAtLatitude(_ latitude: CLLocationDegrees) -> CLLocationDistance {
    2 * .pi * 6_378_137 / MKMapSize.world.width * cos(latitude * .pi / 180)
}

public func MKMapPointsPerMeterAtLatitude(_ latitude: CLLocationDegrees) -> Double {
    1 / MKMetersPerMapPointAtLatitude(latitude)
}

public func MKMetersBetweenMapPoints(_ a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDistance {
    Geodesy.distance(a.coordinate, b.coordinate)
}

public typealias MKZoomScale = CGFloat

// MARK: - Camera

open class MKMapCamera: NSObject, NSCopying, @unchecked Sendable {
    public var centerCoordinate: CLLocationCoordinate2D
    public var centerCoordinateDistance: CLLocationDistance
    public var heading: CLLocationDirection
    public var pitch: CGFloat
    public var altitude: CLLocationDistance {
        get { centerCoordinateDistance * cos(Double(pitch) * .pi / 180) }
        set { centerCoordinateDistance = newValue / max(0.01, cos(Double(pitch) * .pi / 180)) }
    }
    public override init() {
        centerCoordinate = CLLocationCoordinate2D(); centerCoordinateDistance = 1000; heading = 0; pitch = 0
        super.init()
    }
    public init(lookingAtCenter centerCoordinate: CLLocationCoordinate2D, fromDistance distance: CLLocationDistance,
                pitch: CGFloat, heading: CLLocationDirection) {
        self.centerCoordinate = centerCoordinate; centerCoordinateDistance = distance; self.pitch = pitch; self.heading = heading
        super.init()
    }
    public init(lookingAtCenter centerCoordinate: CLLocationCoordinate2D, fromEyeCoordinate eyeCoordinate: CLLocationCoordinate2D,
                eyeAltitude: CLLocationDistance) {
        self.centerCoordinate = centerCoordinate
        let ground = Geodesy.distance(centerCoordinate, eyeCoordinate)
        centerCoordinateDistance = sqrt(ground * ground + eyeAltitude * eyeAltitude)
        pitch = CGFloat(atan2(ground, eyeAltitude) * 180 / .pi)
        heading = 0
        super.init()
    }
    public func copy(with zone: NSZone? = nil) -> Any {
        MKMapCamera(lookingAtCenter: centerCoordinate, fromDistance: centerCoordinateDistance, pitch: pitch, heading: heading)
    }
}

open class MKMapCameraBoundary: NSObject, @unchecked Sendable {
    public let region: MKCoordinateRegion
    public var mapRect: MKMapRect { region.mapRect }
    public init?(coordinateRegion region: MKCoordinateRegion) { self.region = region; super.init() }
    public init?(mapRect: MKMapRect) { region = MKCoordinateRegion(mapRect); super.init() }
}

open class MKMapCameraZoomRange: NSObject, @unchecked Sendable {
    public let minCenterCoordinateDistance: CLLocationDistance
    public let maxCenterCoordinateDistance: CLLocationDistance
    public static let zoomDefault: CLLocationDistance = -1
    public init?(minCenterCoordinateDistance minDistance: CLLocationDistance, maxCenterCoordinateDistance maxDistance: CLLocationDistance) {
        minCenterCoordinateDistance = minDistance; maxCenterCoordinateDistance = maxDistance; super.init()
    }
    public init?(minCenterCoordinateDistance minDistance: CLLocationDistance) {
        minCenterCoordinateDistance = minDistance; maxCenterCoordinateDistance = -1; super.init()
    }
    public init?(maxCenterCoordinateDistance maxDistance: CLLocationDistance) {
        minCenterCoordinateDistance = -1; maxCenterCoordinateDistance = maxDistance; super.init()
    }
}
