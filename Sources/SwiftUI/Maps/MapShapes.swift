// Annotations and overlays: real coordinates and bounding rects, so SwiftUI `Map` content built
// from them draws in the right place.

import Foundation

public protocol MKAnnotation: NSObjectProtocol {
    var coordinate: CLLocationCoordinate2D { get }
    var title: String? { get }
    var subtitle: String? { get }
}
extension MKAnnotation {
    public var title: String? { nil }
    public var subtitle: String? { nil }
}

public protocol MKOverlay: MKAnnotation {
    var boundingMapRect: MKMapRect { get }
    func intersects(_ mapRect: MKMapRect) -> Bool
    var canReplaceMapContent: Bool { get }
}
extension MKOverlay {
    public func intersects(_ mapRect: MKMapRect) -> Bool { boundingMapRect.intersects(mapRect) }
    public var canReplaceMapContent: Bool { false }
}

open class MKShape: NSObject, MKAnnotation, @unchecked Sendable {
    open var title: String?
    open var subtitle: String?
    open var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D() }
    public override init() { super.init() }
}

open class MKPointAnnotation: MKShape, @unchecked Sendable {
    private var stored = CLLocationCoordinate2D()
    open override var coordinate: CLLocationCoordinate2D {
        get { stored }
        set { stored = newValue }
    }
    public override init() { super.init() }
    public init(coordinate: CLLocationCoordinate2D) { stored = coordinate; super.init() }
    public init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?) {
        stored = coordinate
        super.init()
        self.title = title
        self.subtitle = subtitle
    }
}

open class MKMultiPoint: MKShape, @unchecked Sendable {
    let storage: [MKMapPoint]
    init(mapPoints: [MKMapPoint]) { storage = mapPoints; super.init() }
    public override init() { storage = []; super.init() }

    public var pointCount: Int { storage.count }
    /// Pointer into the shape's own copy of its points (valid for the shape's lifetime).
    public func points() -> UnsafeMutablePointer<MKMapPoint> {
        if let buffer { return buffer }
        let p = UnsafeMutablePointer<MKMapPoint>.allocate(capacity: max(1, storage.count))
        p.initialize(from: storage, count: storage.count)
        buffer = p
        return p
    }
    private var buffer: UnsafeMutablePointer<MKMapPoint>?
    deinit { buffer?.deallocate() }

    public func getCoordinates(_ coords: UnsafeMutablePointer<CLLocationCoordinate2D>, range: NSRange) {
        for i in 0..<range.length where range.location + i < storage.count {
            coords[i] = storage[range.location + i].coordinate
        }
    }
    public func location(atPointIndex index: Int) -> CGFloat {
        var total = 0.0
        for i in stride(from: 1, through: min(index, storage.count - 1), by: 1) {
            total += MKMetersBetweenMapPoints(storage[i - 1], storage[i])
        }
        return CGFloat(total)
    }
    public func locations(atPointIndexes indexes: IndexSet) -> [NSNumber] {
        indexes.map { NSNumber(value: Double(location(atPointIndex: $0))) }
    }
    /// The shape's coordinates (internal helper used by SwiftUI `Map` content).
    var coordinateList: [CLLocationCoordinate2D] { storage.map(\.coordinate) }
    var mapPointList: [MKMapPoint] { storage }

    open override var coordinate: CLLocationCoordinate2D {
        let r = MKMapRect.bounding(storage)
        return r.isNull ? kCLLocationCoordinate2DInvalid : MKMapPoint(x: r.midX, y: r.midY).coordinate
    }
    open var boundingMapRect: MKMapRect { MKMapRect.bounding(storage) }
}

open class MKPolyline: MKMultiPoint, MKOverlay, @unchecked Sendable {
    public override init() { super.init() }
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int) {
        self.init(mapPoints: Array(UnsafeBufferPointer(start: points, count: count)))
    }
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) {
        self.init(mapPoints: UnsafeBufferPointer(start: coords, count: count).map(MKMapPoint.init))
    }
    override init(mapPoints: [MKMapPoint]) { super.init(mapPoints: mapPoints) }
}

/// A polyline that follows the great circle between its points; `points()` returns the densified curve.
open class MKGeodesicPolyline: MKPolyline, @unchecked Sendable {
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int) {
        let coords = UnsafeBufferPointer(start: points, count: count).map(\.coordinate)
        self.init(mapPoints: MKGeodesicPolyline.densify(coords).map(MKMapPoint.init))
    }
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) {
        self.init(mapPoints: MKGeodesicPolyline.densify(Array(UnsafeBufferPointer(start: coords, count: count))).map(MKMapPoint.init))
    }
    override init(mapPoints: [MKMapPoint]) { super.init(mapPoints: mapPoints) }

    static func densify(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coords.count > 1 else { return coords }
        var out: [CLLocationCoordinate2D] = [coords[0]]
        for i in 1..<coords.count {
            let metres = Geodesy.haversine(coords[i - 1], coords[i])
            let steps = max(1, min(256, Int(metres / 50_000)))
            out += Geodesy.greatCircle(coords[i - 1], coords[i], steps: steps).dropFirst()
        }
        return out
    }
}

open class MKPolygon: MKMultiPoint, MKOverlay, @unchecked Sendable {
    public let interiorPolygons: [MKPolygon]?
    public override init() { interiorPolygons = nil; super.init() }
    init(mapPoints: [MKMapPoint], interiorPolygons: [MKPolygon]?) {
        self.interiorPolygons = interiorPolygons
        super.init(mapPoints: mapPoints)
    }
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int) {
        self.init(mapPoints: Array(UnsafeBufferPointer(start: points, count: count)), interiorPolygons: nil)
    }
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int, interiorPolygons: [MKPolygon]?) {
        self.init(mapPoints: Array(UnsafeBufferPointer(start: points, count: count)), interiorPolygons: interiorPolygons)
    }
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) {
        self.init(mapPoints: UnsafeBufferPointer(start: coords, count: count).map(MKMapPoint.init), interiorPolygons: nil)
    }
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int, interiorPolygons: [MKPolygon]?) {
        self.init(mapPoints: UnsafeBufferPointer(start: coords, count: count).map(MKMapPoint.init), interiorPolygons: interiorPolygons)
    }
}

open class MKCircle: MKShape, MKOverlay, @unchecked Sendable {
    public let radius: CLLocationDistance
    private let center: CLLocationCoordinate2D
    open override var coordinate: CLLocationCoordinate2D { center }
    public init(center coord: CLLocationCoordinate2D, radius: CLLocationDistance) {
        center = coord
        self.radius = radius
        super.init()
    }
    public init(mapRect: MKMapRect) {
        center = MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate
        radius = max(mapRect.width, mapRect.height) / 2 * MKMetersPerMapPointAtLatitude(center.latitude)
        super.init()
    }
    open var boundingMapRect: MKMapRect {
        let c = MKMapPoint(center)
        let r = radius * MKMapPointsPerMeterAtLatitude(center.latitude)
        return MKMapRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }
    /// The circle as a ring of coordinates (internal helper used to draw it).
    func ring(segments: Int = 96) -> [CLLocationCoordinate2D] {
        (0..<segments).map { Geodesy.destination(from: center, distance: radius, bearing: Double($0) / Double(segments) * 360) }
    }
}

open class MKMultiPolyline: MKShape, MKOverlay, @unchecked Sendable {
    public let polylines: [MKPolyline]
    public init(_ polylines: [MKPolyline]) { self.polylines = polylines; super.init() }
    open var boundingMapRect: MKMapRect { polylines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) } }
    open override var coordinate: CLLocationCoordinate2D {
        let r = boundingMapRect
        return r.isNull ? kCLLocationCoordinate2DInvalid : MKMapPoint(x: r.midX, y: r.midY).coordinate
    }
}

open class MKMultiPolygon: MKShape, MKOverlay, @unchecked Sendable {
    public let polygons: [MKPolygon]
    public init(_ polygons: [MKPolygon]) { self.polygons = polygons; super.init() }
    open var boundingMapRect: MKMapRect { polygons.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) } }
    open override var coordinate: CLLocationCoordinate2D {
        let r = boundingMapRect
        return r.isNull ? kCLLocationCoordinate2DInvalid : MKMapPoint(x: r.midX, y: r.midY).coordinate
    }
}
