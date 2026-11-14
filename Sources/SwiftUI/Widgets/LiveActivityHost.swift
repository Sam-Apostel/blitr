// The engine side of Live Activities: the Lock Screen banner and the Dynamic Island
// presentations. The public API (ActivityConfiguration, DynamicIsland, ...) is in WidgetKit.
//
// Sizes from Apple's Human Interface Guidelines, "Live Activities" > Specifications
// (https://developer.apple.com/design/human-interface-guidelines/live-activities, revision of
// October 13, 2026), for the 393x852 and 430x932 iPhone classes:
//   compact leading / trailing   52.33x36.67 (393)   62.33x36.67 (430)
//   minimal                      36.67-45 x 36.67
//   expanded                     371 x 84-160 (393)  408 x 84-160 (430)
//   Lock Screen                  371 x 84-160 (393)  408 x 84-160 (430); iPad 425 or 500 wide
// Other widths follow the same rule (screen width minus 22pt; side regions grow with the screen).
// Corner radii and default content margins are not published; the values below are estimates.

public enum _ActivityPresentationID: String, Sendable {
    case lockScreen, compact, expanded, minimal
}

public enum _IslandRegionID: Sendable { case leading, trailing, center, bottom }

public struct _IslandRegion {
    let id: _IslandRegionID
    let priority: Double
    let content: AnyView
    public init(id: _IslandRegionID, priority: Double, content: AnyView) {
        self.id = id
        self.priority = priority
        self.content = content
    }
}

/// `contentMargins(_:_:for:)` on a DynamicIsland: edges and a length (nil: the system default).
public struct _IslandMargins {
    var overrides: [(Edge.Set, CGFloat?)] = []
    public init() {}
    public mutating func add(_ edges: Edge.Set, _ length: CGFloat?) { overrides.append((edges, length)) }
    func apply(to base: EdgeInsets) -> EdgeInsets {
        var result = base
        for (edges, length) in overrides {
            if edges.contains(.top) { result.top = length ?? base.top }
            if edges.contains(.bottom) { result.bottom = length ?? base.bottom }
            if edges.contains(.leading) { result.leading = length ?? base.leading }
            if edges.contains(.trailing) { result.trailing = length ?? base.trailing }
        }
        return result
    }
}

enum IslandBelowIfTooWideKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

enum ActivityBackgroundTintKey: PreferenceKey {
    static let defaultValue: Color? = nil
    static func reduce(value: inout Color?, nextValue: () -> Color?) { value = value ?? nextValue() }
}

extension View {
    /// WidgetKit's `activityBackgroundTint(_:)`.
    public func _activityBackgroundTint(_ color: Color?) -> some View { preference(key: ActivityBackgroundTintKey.self, value: color) }
    /// WidgetKit's `dynamicIsland(verticalPlacement: .belowIfTooWide)`.
    public func _dynamicIslandBelowIfTooWide() -> some View { preference(key: IslandBelowIfTooWideKey.self, value: true) }
}

/// Draws one presentation of a Live Activity.
public struct _LiveActivityCanvas: View, PrimitiveView {
    public typealias Body = Never
    let presentation: _ActivityPresentationID
    let lockScreen: @MainActor () -> AnyView
    let backgroundTint: Color?
    let expanded: @MainActor () -> [_IslandRegion]
    let compactLeading: @MainActor () -> AnyView
    let compactTrailing: @MainActor () -> AnyView
    let minimal: @MainActor () -> AnyView
    let keylineTint: Color?
    let margins: [_ActivityPresentationID: _IslandMargins]

    public init(presentation: _ActivityPresentationID, lockScreen: @escaping @MainActor () -> AnyView, backgroundTint: Color?,
                expanded: @escaping @MainActor () -> [_IslandRegion], compactLeading: @escaping @MainActor () -> AnyView,
                compactTrailing: @escaping @MainActor () -> AnyView, minimal: @escaping @MainActor () -> AnyView,
                keylineTint: Color?, margins: [_ActivityPresentationID: _IslandMargins]) {
        self.presentation = presentation
        self.lockScreen = lockScreen
        self.backgroundTint = backgroundTint
        self.expanded = expanded
        self.compactLeading = compactLeading
        self.compactTrailing = compactTrailing
        self.minimal = minimal
        self.keylineTint = keylineTint
        self.margins = margins
    }

    struct Island {
        var top: CGFloat
        var pill: CGSize
        var expandedWidth: CGFloat
        var compactSide: CGFloat
        var expandedRadius: CGFloat
    }

    static func island(for device: DeviceProfile, warn: (String) -> Void) -> Island {
        var device = device
        if case .dynamicIsland = device.housing {} else {
            warn("\(device.name) has no Dynamic Island; the island is drawn at iPhone 16 size")
            device = DeviceProfile.all["iphone-16"]!
        }
        guard case .dynamicIsland(let pill, let top) = device.housing else { fatalError() }
        let width = device.portraitSize.width
        // 52.33 at 393pt, 62.33 at 430pt: interpolated for other widths.
        let side = 52.33 + (width - 393) * (10.0 / 37.0)
        // Concentric with the display corner (estimate).
        let radius = max(device.cornerRadius - top, 30)
        return Island(top: top, pill: pill, expandedWidth: width - 22, compactSide: side, expandedRadius: radius)
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let device = ctx.runtime.config.device
        let backdrop = Color(WidgetMetrics.backdrop(ctx.env.colorScheme))
        let scheme = ctx.env.colorScheme

        if presentation == .lockScreen {
            let width: CGFloat
            switch device.idiom {
            case .pad: width = device.portraitSize.width >= 1024 ? 500 : 425
            case .phone: width = device.portraitSize.width - 22
            case .tv:
                ctx.runtime.warn("Live Activities are not shown on \(device.name)")
                width = 371
            }
            let contentNode = resolveSingle(lockScreen(), ctx.child("lock-screen"))
            let natural = contentNode.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            if natural > 160 { ctx.runtime.warn("The Lock Screen presentation is \(Int(natural))pt tall; the system truncates it to 160pt") }
            let height = min(max(natural, 84), 160)
            let fill = backgroundTint ?? contentNode.preferences[ActivityBackgroundTintKey.self] ?? Color(scheme == .dark ? RGBA(0.11, 0.11, 0.12, 0.78) : RGBA(0.97, 0.97, 0.97, 0.82))
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            let banner = ResolvedNodeView(node: contentNode)
                .frame(width: width, height: height)
                .background(shape.fill(fill))
                .clipShape(shape)
            let screenWidth = device.idiom == .phone ? device.portraitSize.width : width + 32
            resolveView(banner.padding(.vertical, 11).frame(width: screenWidth).background(backdrop), ctx, into: &out)
            return
        }

        let island = Self.island(for: device, warn: ctx.runtime.warn)
        // The island's content always uses the dark appearance.
        let islandCtx = ctx.with { $0.colorScheme = .dark }
        // The keyline is drawn in the dark appearance only, where the island meets a dark background.
        let keylineTint = ctx.env.colorScheme == .dark ? self.keylineTint : nil
        let keyline: AnyView = keylineTint.map { tint in AnyView(Color.clear.overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))) } ?? AnyView(EmptyView())
        let shape: AnyView
        switch presentation {
        case .expanded:
            let m = (margins[.expanded] ?? _IslandMargins()).apply(to: EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
            let regions = expanded()
            var nodes: [Node] = [], roles: [_IslandRegionID] = []
            for (i, region) in regions.enumerated() {
                if roles.contains(region.id) {
                    ctx.runtime.warn("DynamicIsland has more than one \(region.id) region; the first one is shown")
                    continue
                }
                nodes.append(resolveSingle(region.content, islandCtx.child("region-\(i)")))
                roles.append(region.id)
            }
            let node = IslandExpandedNode(children: nodes, roles: roles, margins: m, pill: island.pill, width: island.expandedWidth,
                                          warn: ctx.runtime.warn)
            let radius = island.expandedRadius
            shape = AnyView(ResolvedNodeView(node: node)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(keylineTint.map { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke($0.opacity(0.6), lineWidth: 1) }))
        case .compact:
            let m = (margins[.compact] ?? _IslandMargins()).apply(to: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            let height = island.pill.height
            shape = AnyView(HStack(spacing: 0) {
                compactLeading().padding(.leading, m.leading).padding(.top, m.top).padding(.bottom, m.bottom)
                    .frame(width: island.compactSide, height: height, alignment: .leading)
                Color.clear.frame(width: island.pill.width, height: height)
                compactTrailing().padding(.trailing, m.trailing).padding(.top, m.top).padding(.bottom, m.bottom)
                    .frame(width: island.compactSide, height: height, alignment: .trailing)
            }
            .environment(\.colorScheme, .dark)
            .background(Capsule().fill(Color.black))
            .clipShape(Capsule())
            .overlay(keyline))
        case .minimal:
            let m = (margins[.minimal] ?? _IslandMargins()).apply(to: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            let height = island.pill.height
            let content = minimal().padding(m).environment(\.colorScheme, .dark)
            // With two activities running, one is attached to the camera and the other is the detached
            // minimal bubble; the attached one is drawn as the empty pill.
            let bubble = content.frame(minWidth: height, maxWidth: 45, minHeight: height, maxHeight: height)
                .fixedSize(horizontal: true, vertical: false)
                .background(Capsule().fill(Color.black))
                .clipShape(Capsule())
                .overlay(keyline)
            shape = AnyView(Capsule().fill(Color.black).frame(width: island.pill.width, height: height)
                .overlay(alignment: .leading) { bubble.offset(x: island.pill.width + 6) })
        case .lockScreen:
            return
        }
        let screenWidth = device.portraitSize.width
        let canvas = shape
            .padding(.top, island.top)
            .padding(.bottom, max(island.top, 12))
            .frame(width: screenWidth)
            .background(backdrop)
        resolveView(canvas, ctx, into: &out)
    }
}

/// The expanded island: leading and trailing regions beside the camera, the center region below
/// it between them, and the bottom region across the full width under everything.
final class IslandExpandedNode: Node {
    let roles: [_IslandRegionID]
    let margins: EdgeInsets
    let pill: CGSize
    let width: CGFloat
    let warn: (String) -> Void
    private var frames: [CGRect] = []
    private var warned = false

    init(children: [Node], roles: [_IslandRegionID], margins: EdgeInsets, pill: CGSize, width: CGFloat, warn: @escaping (String) -> Void) {
        self.roles = roles
        self.margins = margins
        self.pill = pill
        self.width = width
        self.warn = warn
        super.init(children: children)
    }

    private func compute() -> CGFloat {
        let inner = width - margins.leading - margins.trailing
        let sideLimit = (inner - pill.width) / 2 - 4
        let belowTop = pill.height + 6
        frames = Array(repeating: .zero, count: children.count)
        var leadingMax = margins.leading, trailingMin = width - margins.trailing
        var bottomOfTop: CGFloat = belowTop
        func index(_ role: _IslandRegionID) -> Int? { roles.firstIndex(of: role) }

        for role in [_IslandRegionID.leading, .trailing] {
            guard let i = index(role) else { continue }
            let child = children[i]
            let below = child.preferences[IslandBelowIfTooWideKey.self]
                && child.sizeThatFits(ProposedViewSize(width: nil, height: nil)).width > sideLimit
            let limit = below ? inner / 2 - 4 : sideLimit
            let s = child.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            let y = below ? belowTop : margins.top
            let x = role == .leading ? margins.leading : width - margins.trailing - s.width
            frames[i] = CGRect(x: x, y: y, width: s.width, height: s.height)
            if role == .leading { leadingMax = x + s.width + 8 } else { trailingMin = x - 8 }
            bottomOfTop = max(bottomOfTop, y + s.height)
        }
        if let i = index(.center) {
            let span = max(0, trailingMin - leadingMax)
            let s = children[i].sizeThatFits(ProposedViewSize(width: span, height: nil))
            let x = min(max((width - s.width) / 2, leadingMax), max(leadingMax, trailingMin - s.width))
            frames[i] = CGRect(x: x, y: belowTop, width: s.width, height: s.height)
            bottomOfTop = max(bottomOfTop, belowTop + s.height)
        }
        var contentBottom = bottomOfTop
        if let i = index(.bottom) {
            let s = children[i].sizeThatFits(ProposedViewSize(width: inner, height: nil))
            let y = bottomOfTop + 6
            frames[i] = CGRect(x: margins.leading + (inner - min(s.width, inner)) / 2, y: y, width: min(s.width, inner), height: s.height)
            contentBottom = y + s.height
        }
        let natural = contentBottom + margins.bottom
        if natural > 160, !warned {
            warned = true
            warn("The expanded Dynamic Island content is \(Int(natural))pt tall; the system limits it to 160pt")
        }
        return min(max(natural, 84), 160)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { CGSize(width: width, height: compute()) }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        _ = compute()
        for (child, frame) in zip(children, frames) { child.place(at: frame.origin, size: frame.size, ctx) }
    }
}
