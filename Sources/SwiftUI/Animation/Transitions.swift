// Transitions describe how a view enters and leaves the hierarchy. A still render only shows views in
// their settled (identity) state, so every transition renders its content unchanged. An interaction
// capture reads the `TransitionModel` recorded by `.transition(_:)` (TransitionModel.swift).

public enum TransitionPhase: Hashable, Sendable {
    case willAppear, identity, didDisappear
    public var isIdentity: Bool { self == .identity }
    public var value: Double {
        switch self {
        case .willAppear: return -1
        case .identity: return 0
        case .didDisappear: return 1
        }
    }
}

public struct TransitionProperties: Sendable {
    public var hasMotion: Bool
    public init(hasMotion: Bool = true) { self.hasMotion = hasMotion }
}

public protocol Transition: Sendable {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content, phase: TransitionPhase) -> Self.Body
    static var properties: TransitionProperties { get }
    typealias Content = PlaceholderContentView<Self>
}

extension Transition {
    public static var properties: TransitionProperties { TransitionProperties() }

    public func combined<T: Transition>(with other: T) -> some Transition {
        CombinedTransition(first: self, second: other)
    }
}

// MARK: - Built-in transitions

public struct OpacityTransition: Transition {
    public init() {}
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct SlideTransition: Transition {
    public init() {}
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct ScaleTransition: Transition {
    public var scale: Double
    public var anchor: UnitPoint
    public init(_ scale: Double, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct MoveTransition: Transition {
    public var edge: Edge
    public init(edge: Edge) { self.edge = edge }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct OffsetTransition: Transition {
    public var offset: CGSize
    public init(_ offset: CGSize) { self.offset = offset }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct PushTransition: Transition {
    public var edge: Edge
    public init(edge: Edge) { self.edge = edge }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct IdentityTransition: Transition {
    public init() {}
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
    public static var properties: TransitionProperties { TransitionProperties(hasMotion: false) }
}
public struct BlurReplaceTransition: Transition {
    public struct Configuration: Equatable, Sendable {
        let id: Int
        public static let downUp = Configuration(id: 0)
        public static let upUp = Configuration(id: 1)
    }
    public var configuration: Configuration
    public init(configuration: Configuration) { self.configuration = configuration }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
public struct AsymmetricTransition<Insertion: Transition, Removal: Transition>: Transition {
    public var insertion: Insertion
    public var removal: Removal
    public init(insertion: Insertion, removal: Removal) {
        self.insertion = insertion
        self.removal = removal
    }
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}
struct CombinedTransition<First: Transition, Second: Transition>: Transition {
    var first: First
    var second: Second
    func body(content: Content, phase: TransitionPhase) -> some View { content }
}

extension OpacityTransition: TransitionModelProvider { var model: TransitionModel { .opacity } }
extension SlideTransition: TransitionModelProvider { var model: TransitionModel { .slide } }
extension ScaleTransition: TransitionModelProvider { var model: TransitionModel { .scale(scale, anchor) } }
extension MoveTransition: TransitionModelProvider { var model: TransitionModel { .move(edge) } }
extension OffsetTransition: TransitionModelProvider { var model: TransitionModel { .offset(offset) } }
extension PushTransition: TransitionModelProvider { var model: TransitionModel { .push(edge) } }
extension IdentityTransition: TransitionModelProvider { var model: TransitionModel { .identity } }
extension BlurReplaceTransition: TransitionModelProvider { var model: TransitionModel { .blurReplace(upUp: configuration == .upUp) } }
extension AsymmetricTransition: TransitionModelProvider {
    var model: TransitionModel { .asymmetric(TransitionModel.of(insertion), TransitionModel.of(removal)) }
}
extension CombinedTransition: TransitionModelProvider {
    var model: TransitionModel { .combined(TransitionModel.of(first), TransitionModel.of(second)) }
}

extension Transition where Self == OpacityTransition {
    public static var opacity: OpacityTransition { OpacityTransition() }
}
extension Transition where Self == SlideTransition {
    public static var slide: SlideTransition { SlideTransition() }
}
extension Transition where Self == ScaleTransition {
    public static var scale: ScaleTransition { ScaleTransition(0) }
    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> ScaleTransition { ScaleTransition(scale, anchor: anchor) }
}
extension Transition where Self == MoveTransition {
    public static func move(edge: Edge) -> MoveTransition { MoveTransition(edge: edge) }
}
extension Transition where Self == OffsetTransition {
    public static func offset(_ offset: CGSize) -> OffsetTransition { OffsetTransition(offset) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetTransition { OffsetTransition(CGSize(width: x, height: y)) }
}
extension Transition where Self == PushTransition {
    public static func push(from edge: Edge) -> PushTransition { PushTransition(edge: edge) }
}
extension Transition where Self == IdentityTransition {
    public static var identity: IdentityTransition { IdentityTransition() }
}
extension Transition where Self == BlurReplaceTransition {
    public static var blurReplace: BlurReplaceTransition { BlurReplaceTransition(configuration: .downUp) }
    public static func blurReplace(_ configuration: BlurReplaceTransition.Configuration) -> BlurReplaceTransition {
        BlurReplaceTransition(configuration: configuration)
    }
}

// MARK: - AnyTransition

public struct AnyTransition: Sendable {
    let model: TransitionModel
    public init<T: Transition>(_ transition: T) { model = TransitionModel.of(transition) }
    init(model: TransitionModel) { self.model = model }

    public static let identity = AnyTransition(model: .identity)
    public static let opacity = AnyTransition(model: .opacity)
    public static let slide = AnyTransition(model: .slide)
    public static let scale = AnyTransition(model: .scale(0, .center))
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition(model: .scale(Double(scale), anchor)) }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition(model: .move(edge)) }
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition(model: .offset(offset)) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition(model: .offset(CGSize(width: x, height: y))) }
    public static func push(from edge: Edge) -> AnyTransition { AnyTransition(model: .push(edge)) }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(model: .asymmetric(insertion.model, removal.model))
    }
    public static func modifier<E: ViewModifier>(active: E, identity: E) -> AnyTransition {
        AnyTransition(model: .custom("AnyTransition.modifier(active: \(E.self), identity:)"))
    }
    public static var blurReplace: AnyTransition { AnyTransition(model: .blurReplace(upUp: false)) }
    public static func blurReplace(_ configuration: BlurReplaceTransition.Configuration) -> AnyTransition {
        AnyTransition(model: .blurReplace(upUp: configuration == .upUp))
    }
    public static var symbolEffect: AnyTransition { AnyTransition(model: .opacity) }
    public static func symbolEffect<T: TransitionSymbolEffect & SymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default) -> AnyTransition {
        AnyTransition(model: .opacity)
    }
    public func combined(with other: AnyTransition) -> AnyTransition { AnyTransition(model: .combined(model, other.model)) }
    public func animation(_ animation: Animation?) -> AnyTransition { AnyTransition(model: .animated(model, animation)) }
}

extension View {
    public func transition(_ t: AnyTransition) -> some View {
        captureRecord { info, _ in info.transition = t.model }
    }
    @_disfavoredOverload
    public func transition<T: Transition>(_ transition: T) -> some View {
        let model = TransitionModel.of(transition)
        return captureRecord { info, _ in info.transition = model }
    }
}

// MARK: - matched geometry and navigation transitions

public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let position = MatchedGeometryProperties(rawValue: 1)
    public static let size = MatchedGeometryProperties(rawValue: 2)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

public protocol NavigationTransition {}
public struct AutomaticNavigationTransition: NavigationTransition {}
public struct ZoomNavigationTransition: NavigationTransition {}
extension NavigationTransition where Self == AutomaticNavigationTransition {
    public static var automatic: AutomaticNavigationTransition { AutomaticNavigationTransition() }
}
extension NavigationTransition where Self == ZoomNavigationTransition {
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> ZoomNavigationTransition { ZoomNavigationTransition() }
}

public protocol MatchedTransitionSourceConfiguration {}
public struct EmptyMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration {
    public init() {}
}
struct InertMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration {}
extension MatchedTransitionSourceConfiguration {
    public func background<S: ShapeStyle>(_ style: S) -> some MatchedTransitionSourceConfiguration { InertMatchedTransitionSourceConfiguration() }
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some MatchedTransitionSourceConfiguration {
        InertMatchedTransitionSourceConfiguration()
    }
    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some MatchedTransitionSourceConfiguration {
        InertMatchedTransitionSourceConfiguration()
    }
}

extension View {
    public func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID,
                                                    properties: MatchedGeometryProperties = .frame,
                                                    anchor: UnitPoint = .center, isSource: Bool = true) -> some View {
        captureRecord { info, _ in
            info.matched.append(MatchedGeometry(id: AnyHashable(id), namespace: namespace, properties: properties, anchor: anchor, isSource: isSource))
        }
    }
    public func matchedGeometryGroup(id: some Hashable, in namespace: Namespace.ID,
                                     properties: MatchedGeometryProperties = .frame,
                                     anchor: UnitPoint = .center, isSource: Bool = true) -> some View { self }
    public func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View { self }
    public func matchedTransitionSource<C: MatchedTransitionSourceConfiguration>(
        id: some Hashable, in namespace: Namespace.ID,
        configuration: (EmptyMatchedTransitionSourceConfiguration) -> C) -> some View { self }
    public func navigationTransition<T: NavigationTransition>(_ style: T) -> some View { self }
}
