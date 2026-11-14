// Camera, position, bounds, style and interaction types of SwiftUI's `Map` (iOS 17+).

import Foundation

public struct MapCamera: Equatable, @unchecked Sendable {
    public var centerCoordinate: CLLocationCoordinate2D
    public var distance: Double
    public var heading: Double
    public var pitch: Double
    public init(centerCoordinate: CLLocationCoordinate2D, distance: Double, heading: Double = 0, pitch: Double = 0) {
        self.centerCoordinate = centerCoordinate
        self.distance = distance
        self.heading = heading
        self.pitch = pitch
    }
    public init(_ mapCamera: MKMapCamera) {
        self.init(centerCoordinate: mapCamera.centerCoordinate, distance: mapCamera.centerCoordinateDistance,
                  heading: mapCamera.heading, pitch: Double(mapCamera.pitch))
    }
    public static func == (l: MapCamera, r: MapCamera) -> Bool {
        l.centerCoordinate.latitude == r.centerCoordinate.latitude && l.centerCoordinate.longitude == r.centerCoordinate.longitude
            && l.distance == r.distance && l.heading == r.heading && l.pitch == r.pitch
    }
}

public struct MapCameraPosition: Equatable, @unchecked Sendable {
    indirect enum Kind {
        case automatic
        case region(MKCoordinateRegion)
        case rect(MKMapRect)
        case camera(MapCamera)
        case item(MKMapItem, allowPitch: Bool)
        case userLocation(followsHeading: Bool, fallback: MapCameraPosition)
    }
    let kind: Kind

    public static var automatic: MapCameraPosition { MapCameraPosition(kind: .automatic) }
    public static func region(_ region: MKCoordinateRegion) -> MapCameraPosition { MapCameraPosition(kind: .region(region)) }
    public static func rect(_ rect: MKMapRect) -> MapCameraPosition { MapCameraPosition(kind: .rect(rect)) }
    public static func camera(_ camera: MapCamera) -> MapCameraPosition { MapCameraPosition(kind: .camera(camera)) }
    public static func item(_ mapItem: MKMapItem, allowPitch: Bool = false) -> MapCameraPosition {
        MapCameraPosition(kind: .item(mapItem, allowPitch: allowPitch))
    }
    public static func userLocation(followsHeading: Bool = false, fallback: MapCameraPosition) -> MapCameraPosition {
        MapCameraPosition(kind: .userLocation(followsHeading: followsHeading, fallback: fallback))
    }

    public var positionedByUser: Bool { false }
    public var region: MKCoordinateRegion? { if case .region(let r) = kind { return r }; return nil }
    public var rect: MKMapRect? { if case .rect(let r) = kind { return r }; return nil }
    public var camera: MapCamera? { if case .camera(let c) = kind { return c }; return nil }
    public var item: MKMapItem? { if case .item(let i, _) = kind { return i }; return nil }
    public var allowsAutomaticPitch: Bool { if case .item(_, let p) = kind { return p }; return false }
    public var followsUserLocation: Bool { if case .userLocation = kind { return true }; return false }
    public var followsUserHeading: Bool { if case .userLocation(let h, _) = kind { return h }; return false }
    public var fallbackPosition: MapCameraPosition? { if case .userLocation(_, let f) = kind { return f }; return nil }

    public static func == (l: MapCameraPosition, r: MapCameraPosition) -> Bool {
        switch (l.kind, r.kind) {
        case (.automatic, .automatic): return true
        case (.region(let a), .region(let b)):
            return a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
                && a.span.latitudeDelta == b.span.latitudeDelta && a.span.longitudeDelta == b.span.longitudeDelta
        case (.rect(let a), .rect(let b)): return a.minX == b.minX && a.minY == b.minY && a.width == b.width && a.height == b.height
        case (.camera(let a), .camera(let b)): return a == b
        case (.item(let a, let p), .item(let b, let q)): return a === b && p == q
        case (.userLocation(let h, let f), .userLocation(let i, let g)): return h == i && f == g
        default: return false
        }
    }
}

public struct MapCameraBounds: @unchecked Sendable {
    let centerRect: MKMapRect?
    let minimumDistance: Double?
    let maximumDistance: Double?
    public init(centerCoordinateBounds: MKMapRect, minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        centerRect = centerCoordinateBounds; self.minimumDistance = minimumDistance; self.maximumDistance = maximumDistance
    }
    public init(centerCoordinateBounds: MKCoordinateRegion, minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        centerRect = centerCoordinateBounds.mapRect; self.minimumDistance = minimumDistance; self.maximumDistance = maximumDistance
    }
    public init(minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        centerRect = nil; self.minimumDistance = minimumDistance; self.maximumDistance = maximumDistance
    }
}

public struct MapInteractionModes: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let pan = MapInteractionModes(rawValue: 1 << 0)
    public static let zoom = MapInteractionModes(rawValue: 1 << 1)
    public static let rotate = MapInteractionModes(rawValue: 1 << 2)
    public static let pitch = MapInteractionModes(rawValue: 1 << 3)
    public static let all: MapInteractionModes = [.pan, .zoom, .rotate, .pitch]
}

public enum MapCameraChangeFrequency: Sendable { case onEnd, continuous }

public struct MapCameraUpdateContext: @unchecked Sendable {
    public let camera: MapCamera
    public let region: MKCoordinateRegion
    public let rect: MKMapRect
    public let scaleFactor: Double
}

/// iOS 18 selection of either the app's tagged content or a map feature.
public struct MapSelection<Value: Hashable>: Hashable {
    public let value: Value?
    public let feature: MapFeature?
    public init(_ value: Value) { self.value = value; feature = nil }
    public init(_ feature: MapFeature) { value = nil; self.feature = feature }
}

public struct MapFeature: Hashable, @unchecked Sendable {
    public enum FeatureKind: Hashable, Sendable { case pointOfInterest, territory, physicalFeature }
    public let title: String?
    public let coordinate: CLLocationCoordinate2D
    public let kind: FeatureKind
    public let pointOfInterestCategory: MKPointOfInterestCategory?
    public let backgroundColor: Color?
    public static func == (l: MapFeature, r: MapFeature) -> Bool {
        l.title == r.title && l.coordinate.latitude == r.coordinate.latitude && l.coordinate.longitude == r.coordinate.longitude
    }
    public func hash(into h: inout Hasher) { h.combine(title); h.combine(coordinate.latitude); h.combine(coordinate.longitude) }
}

// MARK: - Style

public struct MapStyle: @unchecked Sendable {
    enum Base { case standard, imagery, hybrid }
    let base: Base
    let emphasis: StandardEmphasis
    let elevation: Elevation

    public struct Elevation: Hashable, Sendable {
        let raw: Int
        public static let automatic = Elevation(raw: 0)
        public static let flat = Elevation(raw: 1)
        public static let realistic = Elevation(raw: 2)
    }
    public struct StandardEmphasis: Hashable, Sendable {
        let muted: Bool
        public static let automatic = StandardEmphasis(muted: false)
        public static let muted = StandardEmphasis(muted: true)
    }

    public static var standard: MapStyle { MapStyle(base: .standard, emphasis: .automatic, elevation: .automatic) }
    public static func standard(elevation: Elevation = .automatic, emphasis: StandardEmphasis = .automatic,
                                pointsOfInterest: PointOfInterestCategories = .all, showsTraffic: Bool = false) -> MapStyle {
        MapStyle(base: .standard, emphasis: emphasis, elevation: elevation)
    }
    public static var imagery: MapStyle { MapStyle(base: .imagery, emphasis: .automatic, elevation: .automatic) }
    public static func imagery(elevation: Elevation = .automatic) -> MapStyle { MapStyle(base: .imagery, emphasis: .automatic, elevation: elevation) }
    public static var hybrid: MapStyle { MapStyle(base: .hybrid, emphasis: .automatic, elevation: .automatic) }
    public static func hybrid(elevation: Elevation = .automatic, pointsOfInterest: PointOfInterestCategories = .all,
                              showsTraffic: Bool = false) -> MapStyle {
        MapStyle(base: .hybrid, emphasis: .automatic, elevation: elevation)
    }

}

/// Which points of interest the map shows. Points of interest come from map data, which is not
/// drawn here, so this has no visible effect.
public struct PointOfInterestCategories: @unchecked Sendable {
    let included: [MKPointOfInterestCategory]?
    let excluded: [MKPointOfInterestCategory]?
    public static var all: PointOfInterestCategories { PointOfInterestCategories(included: nil, excluded: []) }
    public static var excludingAll: PointOfInterestCategories { PointOfInterestCategories(included: [], excluded: nil) }
    public static func including<S: Sequence>(_ categories: S) -> PointOfInterestCategories where S.Element == MKPointOfInterestCategory {
        PointOfInterestCategories(included: Array(categories), excluded: nil)
    }
    public static func including(_ categories: MKPointOfInterestCategory...) -> PointOfInterestCategories {
        PointOfInterestCategories(included: categories, excluded: nil)
    }
    public static func excluding<S: Sequence>(_ categories: S) -> PointOfInterestCategories where S.Element == MKPointOfInterestCategory {
        PointOfInterestCategories(included: nil, excluded: Array(categories))
    }
    public static func excluding(_ categories: MKPointOfInterestCategory...) -> PointOfInterestCategories {
        PointOfInterestCategories(included: nil, excluded: categories)
    }
}

public struct MapItemDetailSelectionAccessoryStyle: Sendable {
    let raw: Int
    public static let automatic = MapItemDetailSelectionAccessoryStyle(raw: 0)
    public static let callout = MapItemDetailSelectionAccessoryStyle(raw: 1)
    public static let caption = MapItemDetailSelectionAccessoryStyle(raw: 2)
    public static let sheet = MapItemDetailSelectionAccessoryStyle(raw: 3)
    public struct CalloutStyle: Sendable {
        let raw: Int
        public static let automatic = CalloutStyle(raw: 0)
        public static let full = CalloutStyle(raw: 1)
        public static let compact = CalloutStyle(raw: 2)
    }
    public static func callout(_ style: CalloutStyle) -> MapItemDetailSelectionAccessoryStyle { .callout }
}

public enum MapUserTrackingMode: Hashable, Sendable { case none, follow }

public enum MKMapType: UInt, Sendable { case standard = 0, satellite, hybrid, satelliteFlyover, hybridFlyover, mutedStandard }
public enum MKUserTrackingMode: Int, Sendable { case none = 0, follow, followWithHeading }
