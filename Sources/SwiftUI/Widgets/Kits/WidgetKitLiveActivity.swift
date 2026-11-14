
// Live Activities: ActivityConfiguration, the Dynamic Island and their view modifiers.

public struct ActivityViewContext<Attributes: ActivityAttributes> {
    public let attributes: Attributes
    public let state: Attributes.ContentState
    public let isStale: Bool
    public let activityID: String
    init(attributes: Attributes, state: Attributes.ContentState, isStale: Bool = false) {
        self.attributes = attributes
        self.state = state
        self.isStale = isStale
        activityID = "preview"
    }
}

struct _ActivityDescription {
    var attributesType: Any.Type
    /// (attributes, content state) -> (Lock Screen view, Dynamic Island); nil when the types do not match.
    var make: @MainActor (Any, Any) -> (AnyView, DynamicIsland)?
}

public struct ActivityConfiguration<Attributes: ActivityAttributes>: WidgetConfiguration, _WidgetDescribing {
    public typealias Body = Never
    let description: _WidgetDescription

    public init<Content: View>(for attributesType: Attributes.Type,
                               @ViewBuilder content: @escaping (ActivityViewContext<Attributes>) -> Content,
                               dynamicIsland: @escaping (ActivityViewContext<Attributes>) -> DynamicIsland) {
        let activity = _ActivityDescription(attributesType: Attributes.self) { attributes, state in
            guard let attributes = attributes as? Attributes, let state = state as? Attributes.ContentState else { return nil }
            let context = ActivityViewContext(attributes: attributes, state: state)
            return (AnyView(content(context)), dynamicIsland(context))
        }
        description = _WidgetDescription(kind: "\(Attributes.self)", activity: activity)
    }
    func _describe() -> _WidgetDescription? { description }
}

public struct ActivityFamily: Hashable, Sendable {
    let name: String
    public static let small = ActivityFamily(name: "small")
    public static let medium = ActivityFamily(name: "medium")
}

private enum ActivityFamilyKey: EnvironmentKey { static let defaultValue = ActivityFamily.medium }
private enum ActivityFullscreenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Always `.medium`: the iPhone presentations (watch and CarPlay `.small` are not rendered).
    public var activityFamily: ActivityFamily {
        get { self[ActivityFamilyKey.self] }
        set { self[ActivityFamilyKey.self] = newValue }
    }
    public var isActivityFullscreen: Bool {
        get { self[ActivityFullscreenKey.self] }
        set { self[ActivityFullscreenKey.self] = newValue }
    }
}

extension ActivityConfiguration {
    public func supplementalActivityFamilies(_ families: [ActivityFamily]) -> some WidgetConfiguration { modified { _ in } }
}

// MARK: - Dynamic Island

public struct DynamicIslandMode: Hashable, Sendable {
    let id: _ActivityPresentationID
    public static let compact = DynamicIslandMode(id: .compact)
    public static let expanded = DynamicIslandMode(id: .expanded)
    public static let minimal = DynamicIslandMode(id: .minimal)
}

public struct DynamicIslandExpandedRegionPosition: Hashable, Sendable {
    let id: _IslandRegionID
    public static let leading = DynamicIslandExpandedRegionPosition(id: .leading)
    public static let trailing = DynamicIslandExpandedRegionPosition(id: .trailing)
    public static let center = DynamicIslandExpandedRegionPosition(id: .center)
    public static let bottom = DynamicIslandExpandedRegionPosition(id: .bottom)
}

public struct DynamicIslandExpandedRegion<Content: View> {
    let region: _IslandRegion
    public init(_ position: DynamicIslandExpandedRegionPosition, priority: Double = 0, @ViewBuilder content: () -> Content) {
        region = _IslandRegion(id: position.id, priority: priority, content: AnyView(content()))
    }
}

public struct DynamicIslandExpandedContent<Content: View> {
    let regions: [_IslandRegion]
}

@resultBuilder
public enum DynamicIslandExpandedContentBuilder {
    public static func buildExpression<Content: View>(_ region: DynamicIslandExpandedRegion<Content>) -> DynamicIslandExpandedContent<AnyView> {
        DynamicIslandExpandedContent(regions: [region.region])
    }
    public static func buildBlock(_ parts: DynamicIslandExpandedContent<AnyView>...) -> DynamicIslandExpandedContent<AnyView> {
        DynamicIslandExpandedContent(regions: parts.flatMap(\.regions))
    }
    public static func buildOptional(_ part: DynamicIslandExpandedContent<AnyView>?) -> DynamicIslandExpandedContent<AnyView> {
        part ?? DynamicIslandExpandedContent(regions: [])
    }
    public static func buildEither(first: DynamicIslandExpandedContent<AnyView>) -> DynamicIslandExpandedContent<AnyView> { first }
    public static func buildEither(second: DynamicIslandExpandedContent<AnyView>) -> DynamicIslandExpandedContent<AnyView> { second }
    public static func buildLimitedAvailability(_ part: DynamicIslandExpandedContent<AnyView>) -> DynamicIslandExpandedContent<AnyView> { part }
}

public struct DynamicIsland {
    let expanded: [_IslandRegion]
    let compactLeading: AnyView
    let compactTrailing: AnyView
    let minimal: AnyView
    var keyline: Color?
    var margins: [_ActivityPresentationID: _IslandMargins] = [:]

    public init<Expanded: View, CompactLeading: View, CompactTrailing: View, Minimal: View>(
        @DynamicIslandExpandedContentBuilder expanded: () -> DynamicIslandExpandedContent<Expanded>,
        @ViewBuilder compactLeading: () -> CompactLeading,
        @ViewBuilder compactTrailing: () -> CompactTrailing,
        @ViewBuilder minimal: () -> Minimal) {
        self.expanded = expanded().regions
        self.compactLeading = AnyView(compactLeading())
        self.compactTrailing = AnyView(compactTrailing())
        self.minimal = AnyView(minimal())
    }

    public func keylineTint(_ color: Color?) -> DynamicIsland {
        var copy = self
        copy.keyline = color
        return copy
    }
    public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for mode: DynamicIslandMode) -> DynamicIsland {
        var copy = self
        copy.margins[mode.id, default: _IslandMargins()].add(edges, length)
        return copy
    }
    public func widgetURL(_ url: URL?) -> DynamicIsland { self }
}

public struct DynamicIslandExpandedRegionVerticalPlacement: Hashable, Sendable {
    let below: Bool
    public static let belowIfTooWide = DynamicIslandExpandedRegionVerticalPlacement(below: true)
}

extension View {
    public func dynamicIsland(verticalPlacement: DynamicIslandExpandedRegionVerticalPlacement) -> some View {
        _dynamicIslandBelowIfTooWide()
    }
    /// The Lock Screen banner's background; nil keeps the system's.
    public func activityBackgroundTint(_ color: Color?) -> some View { _activityBackgroundTint(color) }
    /// The color of the system's buttons beside the Lock Screen banner, which are not drawn here.
    public func activitySystemActionForegroundColor(_ color: Color?) -> some View { self }
}
