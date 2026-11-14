// SwiftUI MapKit content (iOS 17): `MapContent`, its builder, markers, annotations, overlays
// and content modifiers. Content is flattened into `MapElement`s, which `Map` projects and draws.

import Foundation

@MainActor @preconcurrency
public protocol MapContent {
    associatedtype Body: MapContent
    @MapContentBuilder @MainActor @preconcurrency var body: Body { get }
}

extension Never: MapContent {}

extension MapContent where Body == Never {
    public var body: Never { fatalError("\(Self.self) is primitive map content") }
}

/// Content that produces elements itself instead of through `body`.
protocol PrimitiveMapContent {
    @MainActor func collect(into out: inout [MapElement])
}

@MainActor
func collectMapContent<C: MapContent>(_ content: C, into out: inout [MapElement]) {
    if let primitive = content as? PrimitiveMapContent {
        primitive.collect(into: &out)
    } else {
        collectMapContent(content.body, into: &out)
    }
}

// MARK: - Elements

enum MarkerGlyph {
    case pin
    case system(String)
    case image(String)
    case monogram(Text)
    case label(AnyView)
}

enum MapElementKind {
    case marker(glyph: MarkerGlyph)
    case annotation(anchor: UnitPoint, content: AnyView)
    case legacyPin
    case userLocation(anchor: UnitPoint, content: AnyView?)
    case polyline([MKMapPoint])
    case polygon([MKMapPoint], holes: [[MKMapPoint]])
    case circle(center: CLLocationCoordinate2D, radius: CLLocationDistance)
}

struct MapElement {
    var kind: MapElementKind
    var coordinate: CLLocationCoordinate2D?
    var title: Text?
    var titleView: AnyView?
    var hasTitle = false
    var tintColor: Color?
    var tintStyle: AnyShapeStyle?
    var stroke: AnyShapeStyle?
    var strokeStyle: StrokeStyle?
    var fill: AnyShapeStyle?
    var titles: Visibility = .automatic
    var subtitles: Visibility = .automatic
    var tag: AnyHashable?
    var overlayLevel: MKOverlayLevel = .aboveRoads

    var isOverlay: Bool {
        switch kind {
        case .polyline, .polygon, .circle: return true
        default: return false
        }
    }
    /// Map points that must be visible when the camera fits the content.
    var framingPoints: [MKMapPoint] {
        switch kind {
        case .polyline(let pts): return pts
        case .polygon(let pts, _): return pts
        case .circle(let center, let radius):
            let r = MKCircle(center: center, radius: radius).boundingMapRect
            return [MKMapPoint(x: r.minX, y: r.minY), MKMapPoint(x: r.maxX, y: r.maxY)]
        case .userLocation: return []
        default: return coordinate.map { [MKMapPoint($0)] } ?? []
        }
    }
}

func titleText<S: StringProtocol>(_ s: S) -> (Text?, Bool) { s.isEmpty ? (nil, false) : (Text(String(s)), true) }
func titleText(_ key: LocalizedStringKey) -> (Text?, Bool) {
    let text = Text(key)
    return (text, !text.plainString.isEmpty)
}

public enum MKOverlayLevel: Int, Sendable { case aboveRoads = 0, aboveLabels = 1 }

// MARK: - Builder

@resultBuilder
public struct MapContentBuilder {
    public static func buildExpression<Content: MapContent>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyMapContent { EmptyMapContent() }
    public static func buildBlock<Content: MapContent>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: MapContent>(_ content: repeat each Content) -> TupleMapContent<(repeat each Content)> {
        TupleMapContent { out in
            for child in repeat each content { collectMapContent(child, into: &out) }
        }
    }
    public static func buildIf<Content: MapContent>(_ content: Content?) -> _OptionalMapContent<Content> { _OptionalMapContent(content: content) }
    public static func buildOptional<Content: MapContent>(_ content: Content?) -> _OptionalMapContent<Content> { _OptionalMapContent(content: content) }
    public static func buildEither<T: MapContent, F: MapContent>(first: T) -> _ConditionalMapContent<T, F> { _ConditionalMapContent(storage: .first(first)) }
    public static func buildEither<T: MapContent, F: MapContent>(second: F) -> _ConditionalMapContent<T, F> { _ConditionalMapContent(storage: .second(second)) }
    public static func buildLimitedAvailability<Content: MapContent>(_ content: Content) -> _LimitedAvailabilityMapContent {
        _LimitedAvailabilityMapContent { out in collectMapContent(content, into: &out) }
    }
    public static func buildArray<Content: MapContent>(_ content: [Content]) -> _ArrayMapContent<Content> { _ArrayMapContent(items: content) }
}

public struct EmptyMapContent: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    public init() {}
    func collect(into out: inout [MapElement]) {}
}

public struct TupleMapContent<T>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let collector: @MainActor (inout [MapElement]) -> Void
    init(_ collector: @escaping @MainActor (inout [MapElement]) -> Void) { self.collector = collector }
    func collect(into out: inout [MapElement]) { collector(&out) }
}

public struct _OptionalMapContent<Content: MapContent>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let content: Content?
    func collect(into out: inout [MapElement]) { if let content { collectMapContent(content, into: &out) } }
}

public struct _ConditionalMapContent<TrueContent: MapContent, FalseContent: MapContent>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    func collect(into out: inout [MapElement]) {
        switch storage {
        case .first(let c): collectMapContent(c, into: &out)
        case .second(let c): collectMapContent(c, into: &out)
        }
    }
}

public struct _LimitedAvailabilityMapContent: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let collector: @MainActor (inout [MapElement]) -> Void
    func collect(into out: inout [MapElement]) { collector(&out) }
}

public struct _ArrayMapContent<Content: MapContent>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let items: [Content]
    func collect(into out: inout [MapElement]) { for item in items { collectMapContent(item, into: &out) } }
}

extension ForEach: MapContent, PrimitiveMapContent where Content: MapContent {
    public typealias Body = Never
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @MapContentBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
    func collect(into out: inout [MapElement]) {
        for element in data { collectMapContent(content(element), into: &out) }
    }
}

extension ForEach where Content: MapContent, ID == Data.Element.ID, Data.Element: Identifiable {
    public init(_ data: Data, @MapContentBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Content: MapContent, Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @MapContentBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension Group: MapContent, PrimitiveMapContent where Content: MapContent {
    public typealias Body = Never
    public init(@MapContentBuilder content: () -> Content) { self.content = content() }
    func collect(into out: inout [MapElement]) { collectMapContent(content, into: &out) }
}

// MARK: - Modifiers

public struct _ModifiedMapContent<Content: MapContent>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let content: Content
    let apply: (inout MapElement) -> Void
    func collect(into out: inout [MapElement]) {
        var inner: [MapElement] = []
        collectMapContent(content, into: &inner)
        for var element in inner {
            apply(&element)
            out.append(element)
        }
    }
}

extension MapContent {
    func modified(_ apply: @escaping (inout MapElement) -> Void) -> _ModifiedMapContent<Self> {
        _ModifiedMapContent(content: self, apply: apply)
    }

    public func stroke<S: ShapeStyle>(_ stroke: S, lineWidth: CGFloat = 1) -> some MapContent {
        modified { e in
            if e.stroke == nil { e.stroke = AnyShapeStyle(stroke) }
            if e.strokeStyle == nil { e.strokeStyle = StrokeStyle(lineWidth: lineWidth) }
        }
    }
    public func stroke<S: ShapeStyle>(_ stroke: S, style: StrokeStyle) -> some MapContent {
        modified { e in
            if e.stroke == nil { e.stroke = AnyShapeStyle(stroke) }
            if e.strokeStyle == nil { e.strokeStyle = style }
        }
    }
    public func strokeStyle(style: StrokeStyle) -> some MapContent {
        modified { e in if e.strokeStyle == nil { e.strokeStyle = style } }
    }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some MapContent {
        modified { e in
            if e.fill == nil { e.fill = AnyShapeStyle(style) }
        }
    }
    public func tint(_ tint: Color?) -> some MapContent {
        modified { e in if e.tintColor == nil && e.tintStyle == nil { e.tintColor = tint } }
    }
    public func tint<S: ShapeStyle>(_ tint: S) -> some MapContent {
        modified { e in
            guard e.tintColor == nil && e.tintStyle == nil else { return }
            if let color = tint as? Color { e.tintColor = color } else { e.tintStyle = AnyShapeStyle(tint) }
        }
    }
    public func annotationTitles(_ visibility: Visibility) -> some MapContent {
        modified { e in if e.titles == .automatic { e.titles = visibility } }
    }
    public func annotationSubtitles(_ visibility: Visibility) -> some MapContent {
        modified { e in if e.subtitles == .automatic { e.subtitles = visibility } }
    }
    public func mapOverlayLevel(level: MKOverlayLevel) -> some MapContent {
        modified { e in e.overlayLevel = level }
    }
    public func tag<V: Hashable>(_ tag: V) -> some MapContent {
        modified { e in if e.tag == nil { e.tag = AnyHashable(tag) } }
    }
    public func tag<V: Hashable>(_ tag: V, includeOptional: Bool) -> some MapContent {
        modified { e in if e.tag == nil { e.tag = AnyHashable(tag) } }
    }
    /// Selection of map features by the app has no visual effect in a still frame.
    public func mapItemDetailSelectionAccessory(_ style: MapItemDetailSelectionAccessoryStyle? = nil) -> some MapContent { self }
    public func selectionDisabled(_ disabled: Bool = true) -> some MapContent { self }
}

// MARK: - Marker

/// A balloon marker. Drawn with Apple's shape: a tinted gradient balloon (red by default) with a
/// white glyph, the title below it.
public struct Marker<Label: View>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    var element: MapElement

    init(coordinate: CLLocationCoordinate2D, title: (Text?, Bool), glyph: MarkerGlyph) {
        element = MapElement(kind: .marker(glyph: glyph), coordinate: coordinate, title: title.0, hasTitle: title.1)
    }
    public init(coordinate: CLLocationCoordinate2D, @ViewBuilder label: () -> Label) {
        element = MapElement(kind: .marker(glyph: .pin), coordinate: coordinate, titleView: AnyView(label()), hasTitle: true)
    }
    func collect(into out: inout [MapElement]) { out.append(element) }
}

extension Marker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(titleKey), glyph: .pin)
    }
    public init<S: StringProtocol>(_ title: S, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(title), glyph: .pin)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(titleKey), glyph: .system(systemImage))
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(title), glyph: .system(systemImage))
    }
    public init(_ titleKey: LocalizedStringKey, image: String, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(titleKey), glyph: .image(image))
    }
    public init<S: StringProtocol>(_ title: S, image: String, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(title), glyph: .image(image))
    }
    public init(_ titleKey: LocalizedStringKey, monogram: Text, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(titleKey), glyph: .monogram(monogram))
    }
    public init<S: StringProtocol>(_ title: S, monogram: Text, coordinate: CLLocationCoordinate2D) {
        self.init(coordinate: coordinate, title: titleText(title), glyph: .monogram(monogram))
    }
    public init(item: MKMapItem) {
        self.init(coordinate: item.mapCoordinate, title: titleText(item.name ?? ""), glyph: .pin)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, item: MKMapItem) {
        self.init(coordinate: item.mapCoordinate, title: titleText(titleKey), glyph: .system(systemImage))
    }
}

// MARK: - Annotation

/// The app's own view at a coordinate, with the title below it unless `.annotationTitles(.hidden)`.
public struct Annotation<Label: View, Content: View>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    var element: MapElement

    init(coordinate: CLLocationCoordinate2D, anchor: UnitPoint, title: (Text?, Bool), content: AnyView) {
        element = MapElement(kind: .annotation(anchor: anchor, content: content), coordinate: coordinate, title: title.0, hasTitle: title.1)
    }
    public init(coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center, @ViewBuilder content: () -> Content,
                @ViewBuilder label: () -> Label) {
        element = MapElement(kind: .annotation(anchor: anchor, content: AnyView(content())), coordinate: coordinate,
                             titleView: AnyView(label()), hasTitle: true)
    }
    func collect(into out: inout [MapElement]) { out.append(element) }
}

extension Annotation where Label == Text {
    public init(_ titleKey: LocalizedStringKey, coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center,
                @ViewBuilder content: () -> Content) {
        self.init(coordinate: coordinate, anchor: anchor, title: titleText(titleKey), content: AnyView(content()))
    }
    public init<S: StringProtocol>(_ title: S, coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center,
                                   @ViewBuilder content: () -> Content) {
        self.init(coordinate: coordinate, anchor: anchor, title: titleText(title), content: AnyView(content()))
    }
    public init(item: MKMapItem, anchor: UnitPoint = .center, @ViewBuilder content: () -> Content) {
        self.init(coordinate: item.mapCoordinate, anchor: anchor, title: titleText(item.name ?? ""), content: AnyView(content()))
    }
}

// MARK: - User location

/// The user's position. There is no device position here: the dot is drawn at the camera's
/// center (or the fallback of `.userLocation(fallback:)`).
public struct UserAnnotation<Content: View>: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let anchor: UnitPoint
    let content: AnyView?
    public init(anchor: UnitPoint = .center, @ViewBuilder content: @escaping (UserLocation) -> Content) {
        self.anchor = anchor
        self.content = AnyView(content(UserLocation()))
    }
    func collect(into out: inout [MapElement]) {
        out.append(MapElement(kind: .userLocation(anchor: anchor, content: content)))
    }
}

extension UserAnnotation where Content == _DefaultUserAnnotationContent {
    public init(anchor: UnitPoint = .center) {
        self.anchor = anchor
        content = nil
    }
}

public struct _DefaultUserAnnotationContent: View {
    public var body: some View { UserLocationDot() }
}

public struct UserLocation: Sendable {
    public var location: CLLocation? { nil }
    public var heading: CLHeading? { nil }
}

// MARK: - Overlays

public struct MapPolyline: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    public struct ContourStyle: Equatable, Sendable {
        let geodesic: Bool
        public static let straight = ContourStyle(geodesic: false)
        public static let geodesic = ContourStyle(geodesic: true)
    }
    let points: [MKMapPoint]

    public init(_ polyline: MKPolyline) { points = polyline.mapPointList }
    public init(_ route: MKRoute) { points = route.polyline.mapPointList }
    public init(coordinates: [CLLocationCoordinate2D], contourStyle: ContourStyle = .straight) {
        points = (contourStyle.geodesic ? MKGeodesicPolyline.densify(coordinates) : coordinates).map(MKMapPoint.init)
    }
    public init(points: [MKMapPoint], contourStyle: ContourStyle = .straight) {
        self.points = contourStyle.geodesic ? MKGeodesicPolyline.densify(points.map(\.coordinate)).map(MKMapPoint.init) : points
    }
    func collect(into out: inout [MapElement]) { out.append(MapElement(kind: .polyline(points))) }
}

public struct MapPolygon: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let points: [MKMapPoint]
    let holes: [[MKMapPoint]]
    public init(_ polygon: MKPolygon) {
        points = polygon.mapPointList
        holes = (polygon.interiorPolygons ?? []).map(\.mapPointList)
    }
    public init(coordinates: [CLLocationCoordinate2D]) { points = coordinates.map(MKMapPoint.init); holes = [] }
    public init(points: [MKMapPoint]) { self.points = points; holes = [] }
    func collect(into out: inout [MapElement]) { out.append(MapElement(kind: .polygon(points, holes: holes))) }
}

public struct MapCircle: MapContent, PrimitiveMapContent {
    public typealias Body = Never
    public var body: Never { fatalError() }
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    public init(_ circle: MKCircle) { center = circle.coordinate; radius = circle.radius }
    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance) { self.center = center; self.radius = radius }
    func collect(into out: inout [MapElement]) {
        out.append(MapElement(kind: .circle(center: center, radius: radius), coordinate: center))
    }
}
