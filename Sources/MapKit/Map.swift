// SwiftUI's `Map` (iOS 17 API and the older coordinate-region API), its view modifiers,
// `MapReader`/`MapProxy` and the Look Around preview.
//
// There are no map tiles on Linux. A `Map` draws a placeholder surface (land colour and a faint
// graticule) and, projected with Web Mercator, everything the app put on it: overlays, markers,
// annotations, the user location dot, the map controls and the legal attribution.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

struct MapConfiguration {
    var position: MapCameraPosition
    var bounds: MapCameraBounds?
    var selection: AnyHashable?
    var collect: @MainActor () -> [MapElement]
}

public struct Map<Content: View>: View {
    let config: MapConfiguration
    init(config: MapConfiguration) { self.config = config }
    public var body: some View { MapSurface(config: config) }
}

/// The `Content` of a `Map` built from `MapContent`.
public struct MapContentView<SelectionValue: Hashable, Content: MapContent>: View {
    public var body: EmptyView { EmptyView() }
}

@MainActor
private func collector<C: MapContent>(_ content: C) -> @MainActor () -> [MapElement] {
    { var out: [MapElement] = []; collectMapContent(content, into: &out); return out }
}

extension Map {
    public init<C: MapContent>(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil,
                               interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil,
                               @MapContentBuilder content: () -> C) where Content == MapContentView<Never, C> {
        self.init(config: MapConfiguration(position: initialPosition, bounds: bounds, collect: collector(content())))
    }
    public init<C: MapContent>(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil,
                               interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil,
                               @MapContentBuilder content: () -> C) where Content == MapContentView<Never, C> {
        self.init(config: MapConfiguration(position: position.wrappedValue, bounds: bounds, collect: collector(content())))
    }
    public init<SelectionValue: Hashable, C: MapContent>(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil,
                                                         interactionModes: MapInteractionModes = .all, selection: Binding<SelectionValue?>,
                                                         scope: Namespace.ID? = nil, @MapContentBuilder content: () -> C)
    where Content == MapContentView<SelectionValue, C> {
        self.init(config: MapConfiguration(position: initialPosition, bounds: bounds, selection: selection.wrappedValue.map(AnyHashable.init),
                                           collect: collector(content())))
    }
    public init<SelectionValue: Hashable, C: MapContent>(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil,
                                                         interactionModes: MapInteractionModes = .all, selection: Binding<SelectionValue?>,
                                                         scope: Namespace.ID? = nil, @MapContentBuilder content: () -> C)
    where Content == MapContentView<SelectionValue, C> {
        self.init(config: MapConfiguration(position: position.wrappedValue, bounds: bounds, selection: selection.wrappedValue.map(AnyHashable.init),
                                           collect: collector(content())))
    }
    public init<SelectionValue: Hashable, C: MapContent>(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil,
                                                         interactionModes: MapInteractionModes = .all, selection: Binding<MapSelection<SelectionValue>?>,
                                                         scope: Namespace.ID? = nil, @MapContentBuilder content: () -> C)
    where Content == MapContentView<SelectionValue, C> {
        self.init(config: MapConfiguration(position: initialPosition, bounds: bounds,
                                           selection: selection.wrappedValue?.value.map(AnyHashable.init), collect: collector(content())))
    }
    public init<SelectionValue: Hashable, C: MapContent>(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil,
                                                         interactionModes: MapInteractionModes = .all, selection: Binding<MapSelection<SelectionValue>?>,
                                                         scope: Namespace.ID? = nil, @MapContentBuilder content: () -> C)
    where Content == MapContentView<SelectionValue, C> {
        self.init(config: MapConfiguration(position: position.wrappedValue, bounds: bounds,
                                           selection: selection.wrappedValue?.value.map(AnyHashable.init), collect: collector(content())))
    }
}

extension Map where Content == MapContentView<Never, EmptyMapContent> {
    public init(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil,
                interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil) {
        self.init(config: MapConfiguration(position: initialPosition, bounds: bounds, collect: { [] }))
    }
    public init(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil,
                interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil) {
        self.init(config: MapConfiguration(position: position.wrappedValue, bounds: bounds, collect: { [] }))
    }
}

// MARK: - Legacy API (iOS 14-16)

public protocol MapAnnotationProtocol {}
protocol LegacyMapAnnotation { var element: MapElement { get } }

@available(*, deprecated, message: "Use Marker along with Map initializers that take a MapContentBuilder instead.")
public struct MapMarker: MapAnnotationProtocol, LegacyMapAnnotation {
    let element: MapElement
    public init(coordinate: CLLocationCoordinate2D, tint: Color? = nil) {
        element = MapElement(kind: .marker(glyph: .pin), coordinate: coordinate, tintColor: tint)
    }
}

@available(*, deprecated, message: "Use Marker along with Map initializers that take a MapContentBuilder instead.")
public struct MapPin: MapAnnotationProtocol, LegacyMapAnnotation {
    let element: MapElement
    public init(coordinate: CLLocationCoordinate2D, tint: Color? = nil) {
        element = MapElement(kind: .legacyPin, coordinate: coordinate, tintColor: tint)
    }
}

@available(*, deprecated, message: "Use Annotation along with Map initializers that take a MapContentBuilder instead.")
public struct MapAnnotation<Content: View>: MapAnnotationProtocol, LegacyMapAnnotation {
    let element: MapElement
    public init(coordinate: CLLocationCoordinate2D, anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5), @ViewBuilder content: () -> Content) {
        element = MapElement(kind: .annotation(anchor: UnitPoint(x: anchorPoint.x, y: anchorPoint.y), content: AnyView(content())),
                             coordinate: coordinate, titles: .hidden)
    }
}

public struct _DefaultMapContent: View { public var body: EmptyView { EmptyView() } }
public struct _DefaultAnnotatedMapContent<Items>: View { public var body: EmptyView { EmptyView() } }

@MainActor
private func legacyCollector<Items: RandomAccessCollection, A: MapAnnotationProtocol>(
    _ items: Items, _ content: @escaping (Items.Element) -> A, showsUserLocation: Bool) -> @MainActor () -> [MapElement] {
    {
        var out = items.compactMap { (content($0) as? LegacyMapAnnotation)?.element }
        if showsUserLocation { out.append(MapElement(kind: .userLocation(anchor: .center, content: nil))) }
        return out
    }
}

extension Map where Content == _DefaultMapContent {
    @available(*, deprecated, message: "Use Map initializers that take a MapContentBuilder instead.")
    public init(coordinateRegion: Binding<MKCoordinateRegion>, interactionModes: MapInteractionModes = .all,
                showsUserLocation: Bool = false, userTrackingMode: Binding<MapUserTrackingMode>? = nil) {
        let user = showsUserLocation
        self.init(config: MapConfiguration(position: .region(coordinateRegion.wrappedValue), collect: {
            user ? [MapElement(kind: .userLocation(anchor: .center, content: nil))] : []
        }))
    }
    @available(*, deprecated, message: "Use Map initializers that take a MapContentBuilder instead.")
    public init(mapRect: Binding<MKMapRect>, interactionModes: MapInteractionModes = .all,
                showsUserLocation: Bool = false, userTrackingMode: Binding<MapUserTrackingMode>? = nil) {
        let user = showsUserLocation
        self.init(config: MapConfiguration(position: .rect(mapRect.wrappedValue), collect: {
            user ? [MapElement(kind: .userLocation(anchor: .center, content: nil))] : []
        }))
    }
}

extension Map {
    @available(*, deprecated, message: "Use Map initializers that take a MapContentBuilder instead.")
    public init<Items: RandomAccessCollection, Annotation: MapAnnotationProtocol>(
        coordinateRegion: Binding<MKCoordinateRegion>, interactionModes: MapInteractionModes = .all, showsUserLocation: Bool = false,
        userTrackingMode: Binding<MapUserTrackingMode>? = nil, annotationItems: Items,
        annotationContent: @escaping (Items.Element) -> Annotation) where Content == _DefaultAnnotatedMapContent<Items>, Items.Element: Identifiable {
        self.init(config: MapConfiguration(position: .region(coordinateRegion.wrappedValue),
                                           collect: legacyCollector(annotationItems, annotationContent, showsUserLocation: showsUserLocation)))
    }
    @available(*, deprecated, message: "Use Map initializers that take a MapContentBuilder instead.")
    public init<Items: RandomAccessCollection, Annotation: MapAnnotationProtocol>(
        mapRect: Binding<MKMapRect>, interactionModes: MapInteractionModes = .all, showsUserLocation: Bool = false,
        userTrackingMode: Binding<MapUserTrackingMode>? = nil, annotationItems: Items,
        annotationContent: @escaping (Items.Element) -> Annotation) where Content == _DefaultAnnotatedMapContent<Items>, Items.Element: Identifiable {
        self.init(config: MapConfiguration(position: .rect(mapRect.wrappedValue),
                                           collect: legacyCollector(annotationItems, annotationContent, showsUserLocation: showsUserLocation)))
    }
}

// MARK: - Environment

enum MapStyleKey: EnvironmentKey { static let defaultValue = MapStyle.standard }
enum MapControlsKey: EnvironmentKey { static let defaultValue: AnyView? = nil }
enum MapCameraChangeKey: EnvironmentKey { static let defaultValue: [(MapCameraUpdateContext) -> Void] = [] }
enum MapProxyStorageKey: EnvironmentKey { static let defaultValue: MapProxyStorage? = nil }

extension EnvironmentValues {
    var mapStyle: MapStyle {
        get { self[MapStyleKey.self] }
        set { self[MapStyleKey.self] = newValue }
    }
    var mapControls: AnyView? {
        get { self[MapControlsKey.self] }
        set { self[MapControlsKey.self] = newValue }
    }
    var mapCameraChangeActions: [(MapCameraUpdateContext) -> Void] {
        get { self[MapCameraChangeKey.self] }
        set { self[MapCameraChangeKey.self] = newValue }
    }
    var mapProxyStorage: MapProxyStorage? {
        get { self[MapProxyStorageKey.self] }
        set { self[MapProxyStorageKey.self] = newValue }
    }
}

extension View {
    public func mapStyle(_ mapStyle: MapStyle) -> some View { environment(\.mapStyle, mapStyle) }

    /// The controls are drawn where MapKit puts them: buttons top-trailing, scale top-leading.
    public func mapControls<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        environment(\.mapControls, AnyView(content()))
    }
    public func mapControlVisibility(_ visibility: Visibility) -> some View { environment(\.mapControlVisibility, visibility) }

    /// Called once with the camera the map settles on.
    public func onMapCameraChange(frequency: MapCameraChangeFrequency = .onEnd,
                                  _ action: @escaping (MapCameraUpdateContext) -> Void) -> some View {
        transformEnvironment(\.mapCameraChangeActions) { $0.append(action) }
    }
    public func onMapCameraChange(frequency: MapCameraChangeFrequency = .onEnd, _ action: @escaping () -> Void) -> some View {
        transformEnvironment(\.mapCameraChangeActions) { $0.append { _ in action() } }
    }

    // Selection, scopes and detail sheets need a tap; they have no effect on a still frame.
    public func mapScope(_ scope: Namespace.ID) -> some View { self }
    public func mapFeatureSelectionDisabled(_ isDisabled: (MapFeature) -> Bool) -> some View { self }
    public func mapFeatureSelectionAccessory(_ style: MapItemDetailSelectionAccessoryStyle? = nil) -> some View { self }
    public func mapFeatureSelectionContent<C: View>(@ViewBuilder content: @escaping (MapFeature) -> C) -> some View { self }
    public func mapItemDetailSheet(item: Binding<MKMapItem?>, displaysMap: Bool = true) -> some View { self }
    public func mapItemDetailSheet(isPresented: Binding<Bool>, item: MKMapItem?, displaysMap: Bool = true) -> some View { self }
    public func mapItemDetailPopover(item: Binding<MKMapItem?>, displaysMap: Bool = true) -> some View { self }
    public func mapItemDetailPopover(isPresented: Binding<Bool>, item: MKMapItem?, displaysMap: Bool = true) -> some View { self }
    public func mapItemDetailPopover(item: Binding<MKMapItem?>, displaysMap: Bool = true, attachmentAnchor: PopoverAttachmentAnchor) -> some View { self }
    public func lookAroundViewer(isPresented: Binding<Bool>, initialScene: MKLookAroundScene?, allowsNavigation: Bool = true,
                                 showsRoadLabels: Bool = true, pointsOfInterest: PointOfInterestCategories = .all,
                                 onDismiss: (() -> Void)? = nil) -> some View { self }
    public func lookAroundViewer(isPresented: Binding<Bool>, scene: Binding<MKLookAroundScene?>, allowsNavigation: Bool = true,
                                 showsRoadLabels: Bool = true, pointsOfInterest: PointOfInterestCategories = .all,
                                 onDismiss: (() -> Void)? = nil) -> some View { self }
}

// MARK: - MapReader / MapProxy

final class MapProxyStorage {
    var projection: MapProjection?
    var geometry: GeometryProxy?
}

public struct MapProxy {
    let storage: MapProxyStorage

    /// Where a coordinate is drawn, in the given coordinate space. `nil` before the map is laid out.
    public func convert(_ coordinate: CLLocationCoordinate2D, to space: some CoordinateSpaceProtocol) -> CGPoint? {
        guard let projection = storage.projection, let geometry = storage.geometry else { return nil }
        let p = projection.point(coordinate)
        let origin = geometry.frame(in: space).origin
        return CGPoint(x: p.x + origin.x, y: p.y + origin.y)
    }
    /// The coordinate under a point given in the given coordinate space.
    public func convert(_ point: CGPoint, from space: some CoordinateSpaceProtocol) -> CLLocationCoordinate2D? {
        guard let projection = storage.projection, let geometry = storage.geometry else { return nil }
        let origin = geometry.frame(in: space).origin
        return projection.coordinate(CGPoint(x: point.x - origin.x, y: point.y - origin.y))
    }
    public var camera: MapCamera? { storage.projection?.camera }
}

public struct MapReader<Content: View>: View {
    let content: (MapProxy) -> Content
    @State private var storage = MapProxyStorage()
    public init(@ViewBuilder _ content: @escaping (MapProxy) -> Content) { self.content = content }
    public var body: some View {
        content(MapProxy(storage: storage)).environment(\.mapProxyStorage, storage)
    }
}

// MARK: - Look Around

/// No Look Around imagery here: a neutral placeholder card.
public struct LookAroundPreview: View {
    @Environment(\.colorScheme) private var scheme
    public init(initialScene: MKLookAroundScene?, allowsNavigation: Bool = true, showsRoadLabels: Bool = true,
                pointsOfInterest: PointOfInterestCategories = .all, badgePosition: MKLookAroundBadgePosition = .topLeading) {}
    public init(scene: Binding<MKLookAroundScene?>, allowsNavigation: Bool = true, showsRoadLabels: Bool = true,
                pointsOfInterest: PointOfInterestCategories = .all, badgePosition: MKLookAroundBadgePosition = .topLeading) {}
    public var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(scheme == .dark ? Color(white: 0.2) : Color(white: 0.86))
            Text("Look Around")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.35), in: Capsule())
                .padding(8)
        }
        .onAppear { Runtime.current?.warn("LookAroundPreview: Look Around imagery is not available; a placeholder is drawn.") }
    }
}
