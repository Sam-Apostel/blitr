// UIKit MapKit shells: `MKMapView` and friends exist so `UIViewRepresentable` wrappers compile.
// Like every UIView here, a wrapped MKMapView renders as the representable placeholder.

import Foundation

public protocol MKMapViewDelegate: NSObjectProtocol {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView?
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool)
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool)
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView)
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation)
    func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation)
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation)
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl)
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView)
    func mapView(_ mapView: MKMapView, clusterAnnotationForMemberAnnotations memberAnnotations: [MKAnnotation]) -> MKClusterAnnotation
}
extension MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? { nil }
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer { MKOverlayRenderer(overlay: overlay) }
    public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {}
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {}
    public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {}
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {}
    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {}
    public func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {}
    public func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {}
    public func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {}
    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {}
    public func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {}
    public func mapView(_ mapView: MKMapView, clusterAnnotationForMemberAnnotations memberAnnotations: [MKAnnotation]) -> MKClusterAnnotation {
        MKClusterAnnotation(memberAnnotations: memberAnnotations)
    }
}

open class MKUserLocation: NSObject, MKAnnotation, @unchecked Sendable {
    public var isUpdating: Bool { false }
    public var location: CLLocation? { nil }
    public var heading: CLHeading? { nil }
    public var coordinate: CLLocationCoordinate2D { kCLLocationCoordinate2DInvalid }
    public var title: String? = "My Location"
    public var subtitle: String?
}

open class MKClusterAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    public let memberAnnotations: [MKAnnotation]
    public var title: String?
    public var subtitle: String?
    public init(memberAnnotations: [MKAnnotation]) { self.memberAnnotations = memberAnnotations; super.init() }
    public var coordinate: CLLocationCoordinate2D { memberAnnotations.first?.coordinate ?? kCLLocationCoordinate2DInvalid }
}

public struct MKFeatureVisibility: Sendable, Equatable {
    let raw: Int
    public static let adaptive = MKFeatureVisibility(raw: 0)
    public static let hidden = MKFeatureVisibility(raw: 1)
    public static let visible = MKFeatureVisibility(raw: 2)
}

open class MKAnnotationView: UIView {
    public enum DragState: UInt, Sendable { case none, starting, dragging, canceling, ending }
    public enum CollisionMode: Int, Sendable { case rectangle, circle, none }
    open var annotation: MKAnnotation?
    open var reuseIdentifier: String?
    open var image: UIImage?
    open var centerOffset: CGPoint = .zero
    open var calloutOffset: CGPoint = .zero
    open var canShowCallout = false
    open var isSelected = false
    open var isEnabled = true
    open var isHighlighted = false
    open var isDraggable = false
    open var dragState: DragState = .none
    open var leftCalloutAccessoryView: UIView?
    open var rightCalloutAccessoryView: UIView?
    open var detailCalloutAccessoryView: UIView?
    open var clusteringIdentifier: String?
    open var displayPriority: Float = 1000
    open var collisionMode: CollisionMode = .rectangle
    public init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        self.annotation = annotation
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
    }
    open func prepareForReuse() {}
    open func prepareForDisplay() {}
    open func setSelected(_ selected: Bool, animated: Bool) { isSelected = selected }
}

open class MKMarkerAnnotationView: MKAnnotationView {
    open var markerTintColor: UIColor?
    open var glyphTintColor: UIColor?
    open var glyphText: String?
    open var glyphImage: UIImage?
    open var selectedGlyphImage: UIImage?
    open var titleVisibility: MKFeatureVisibility = .adaptive
    open var subtitleVisibility: MKFeatureVisibility = .adaptive
    open var animatesWhenAdded = false
}

open class MKPinAnnotationView: MKAnnotationView {
    open var pinTintColor: UIColor?
    open var animatesDrop = false
    open class func redPinColor() -> UIColor { .systemRed }
    open class func greenPinColor() -> UIColor { .systemGreen }
    open class func purplePinColor() -> UIColor { .systemPurple }
}

open class MKUserLocationView: MKAnnotationView {}

open class MKOverlayRenderer: NSObject, @unchecked Sendable {
    public let overlay: MKOverlay
    open var alpha: CGFloat = 1
    open var contentScaleFactor: CGFloat { 1 }
    public init(overlay: MKOverlay) { self.overlay = overlay; super.init() }
    open func setNeedsDisplay() {}
    open func point(for mapPoint: MKMapPoint) -> CGPoint { CGPoint(x: mapPoint.x, y: mapPoint.y) }
    open func mapPoint(for point: CGPoint) -> MKMapPoint { MKMapPoint(x: point.x, y: point.y) }
}

open class MKOverlayPathRenderer: MKOverlayRenderer, @unchecked Sendable {
    open var fillColor: UIColor?
    open var strokeColor: UIColor?
    open var lineWidth: CGFloat = 0
    open var lineJoin: CGLineJoin = .round
    open var lineCap: CGLineCap = .round
    open var miterLimit: CGFloat = 10
    open var lineDashPhase: CGFloat = 0
    open var lineDashPattern: [NSNumber]?
    open var shouldRasterize = false
    open func createPath() {}
    open func invalidatePath() {}
}

open class MKPolylineRenderer: MKOverlayPathRenderer, @unchecked Sendable {
    public var polyline: MKPolyline { overlay as! MKPolyline }
    open var strokeStart: CGFloat = 0
    open var strokeEnd: CGFloat = 1
    public init(polyline: MKPolyline) { super.init(overlay: polyline) }
}

open class MKPolygonRenderer: MKOverlayPathRenderer, @unchecked Sendable {
    public var polygon: MKPolygon { overlay as! MKPolygon }
    public init(polygon: MKPolygon) { super.init(overlay: polygon) }
}

open class MKCircleRenderer: MKOverlayPathRenderer, @unchecked Sendable {
    public var circle: MKCircle { overlay as! MKCircle }
    public init(circle: MKCircle) { super.init(overlay: circle) }
}

open class MKGradientPolylineRenderer: MKPolylineRenderer, @unchecked Sendable {
    open func setColors(_ colors: [UIColor], locations: [CGFloat]) {}
}

open class MKMapConfiguration: NSObject, @unchecked Sendable {
    public enum ElevationStyle: Int, Sendable { case flat, realistic }
    open var elevationStyle: ElevationStyle = .flat
}
open class MKStandardMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    public enum EmphasisStyle: Int, Sendable { case `default`, muted }
    open var emphasisStyle: EmphasisStyle = .default
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open var showsTraffic = false
    public override init() { super.init() }
    public init(elevationStyle: ElevationStyle) { super.init(); self.elevationStyle = elevationStyle }
    public init(elevationStyle: ElevationStyle, emphasisStyle: EmphasisStyle) {
        super.init(); self.elevationStyle = elevationStyle; self.emphasisStyle = emphasisStyle
    }
    public init(emphasisStyle: EmphasisStyle) { super.init(); self.emphasisStyle = emphasisStyle }
}
open class MKImageryMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    public override init() { super.init() }
    public init(elevationStyle: ElevationStyle) { super.init(); self.elevationStyle = elevationStyle }
}
open class MKHybridMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open var showsTraffic = false
    public override init() { super.init() }
    public init(elevationStyle: ElevationStyle) { super.init(); self.elevationStyle = elevationStyle }
}

open class MKMapView: UIView {
    open weak var delegate: MKMapViewDelegate?
    open var mapType: MKMapType = .standard
    open var preferredConfiguration: MKMapConfiguration = MKStandardMapConfiguration()
    open var region = MKCoordinateRegion()
    open var centerCoordinate: CLLocationCoordinate2D {
        get { region.center }
        set { region.center = newValue }
    }
    open var visibleMapRect: MKMapRect {
        get { region.mapRect }
        set { region = MKCoordinateRegion(newValue) }
    }
    open var camera = MKMapCamera()
    open var cameraBoundary: MKMapCameraBoundary?
    open var cameraZoomRange: MKMapCameraZoomRange?
    open var isZoomEnabled = true
    open var isScrollEnabled = true
    open var isRotateEnabled = true
    open var isPitchEnabled = true
    open var showsCompass = true
    open var showsScale = false
    open var showsTraffic = false
    open var showsBuildings = true
    open var showsUserLocation = false
    open var showsUserTrackingButton = false
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open var userTrackingMode: MKUserTrackingMode = .none
    open var userLocation = MKUserLocation()
    open var isUserLocationVisible: Bool { false }
    open private(set) var annotations: [MKAnnotation] = []
    open private(set) var overlays: [MKOverlay] = []
    open var selectedAnnotations: [MKAnnotation] = []
    open var layoutMargins: UIEdgeInsets = .zero

    public override init(frame: CGRect) { super.init(frame: frame) }
    public override init() { super.init() }

    open func setRegion(_ region: MKCoordinateRegion, animated: Bool) { self.region = region }
    open func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) { centerCoordinate = coordinate }
    open func setVisibleMapRect(_ mapRect: MKMapRect, animated: Bool) { visibleMapRect = mapRect }
    open func setVisibleMapRect(_ mapRect: MKMapRect, edgePadding insets: UIEdgeInsets, animated: Bool) { visibleMapRect = mapRect }
    open func setCamera(_ camera: MKMapCamera, animated: Bool) { self.camera = camera }
    open func setUserTrackingMode(_ mode: MKUserTrackingMode, animated: Bool) { userTrackingMode = mode }
    open func setCameraZoomRange(_ range: MKMapCameraZoomRange?, animated: Bool) { cameraZoomRange = range }
    open func setCameraBoundary(_ boundary: MKMapCameraBoundary?, animated: Bool) { cameraBoundary = boundary }
    open func regionThatFits(_ region: MKCoordinateRegion) -> MKCoordinateRegion { region }
    open func mapRectThatFits(_ mapRect: MKMapRect) -> MKMapRect { mapRect }
    open func showAnnotations(_ annotations: [MKAnnotation], animated: Bool) {
        let rect = MKMapRect.bounding(annotations.map { MKMapPoint($0.coordinate) })
        if !rect.isNull { visibleMapRect = rect }
    }

    open func addAnnotation(_ annotation: MKAnnotation) { annotations.append(annotation) }
    open func addAnnotations(_ annotations: [MKAnnotation]) { self.annotations += annotations }
    open func removeAnnotation(_ annotation: MKAnnotation) { annotations.removeAll { $0 === annotation } }
    open func removeAnnotations(_ annotations: [MKAnnotation]) {
        self.annotations.removeAll { a in annotations.contains { $0 === a } }
    }
    open func addOverlay(_ overlay: MKOverlay) { overlays.append(overlay) }
    open func addOverlay(_ overlay: MKOverlay, level: MKOverlayLevel) { overlays.append(overlay) }
    open func addOverlays(_ overlays: [MKOverlay]) { self.overlays += overlays }
    open func addOverlays(_ overlays: [MKOverlay], level: MKOverlayLevel) { self.overlays += overlays }
    open func removeOverlay(_ overlay: MKOverlay) { overlays.removeAll { $0 === overlay } }
    open func removeOverlays(_ overlays: [MKOverlay]) {
        self.overlays.removeAll { o in overlays.contains { $0 === o } }
    }
    open func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? { nil }
    open func view(for annotation: MKAnnotation) -> MKAnnotationView? { nil }
    open func selectAnnotation(_ annotation: MKAnnotation, animated: Bool) { selectedAnnotations = [annotation] }
    open func deselectAnnotation(_ annotation: MKAnnotation?, animated: Bool) { selectedAnnotations = [] }
    open func register(_ viewClass: AnyClass?, forAnnotationViewWithReuseIdentifier identifier: String) {}
    open func dequeueReusableAnnotationView(withIdentifier identifier: String) -> MKAnnotationView? { nil }
    open func dequeueReusableAnnotationView(withIdentifier identifier: String, for annotation: MKAnnotation) -> MKAnnotationView {
        MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
    }
    open func annotations(in mapRect: MKMapRect) -> Set<AnyHashable> {
        Set(annotations.filter { mapRect.contains(MKMapPoint($0.coordinate)) }.compactMap { $0 as? NSObject })
    }

    private var projection: MapProjection {
        let size = frame.size == .zero ? CGSize(width: 320, height: 320) : frame.size
        return MapProjection.fitting(region.mapRect, in: size)
    }
    open func convert(_ coordinate: CLLocationCoordinate2D, toPointTo view: UIView?) -> CGPoint { projection.point(coordinate) }
    open func convert(_ point: CGPoint, toCoordinateFrom view: UIView?) -> CLLocationCoordinate2D { projection.coordinate(point) }
    open func convert(_ region: MKCoordinateRegion, toRectTo view: UIView?) -> CGRect {
        let r = region.mapRect, p = projection
        let a = p.point(MKMapPoint(x: r.minX, y: r.minY)), b = p.point(MKMapPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    open func convert(_ rect: CGRect, toRegionFrom view: UIView?) -> MKCoordinateRegion {
        let p = projection
        let a = p.mapPoint(CGPoint(x: rect.minX, y: rect.minY)), b = p.mapPoint(CGPoint(x: rect.maxX, y: rect.maxY))
        return MKCoordinateRegion(MKMapRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
    }
}
