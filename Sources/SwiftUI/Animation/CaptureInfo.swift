// Data recorded on nodes during an interaction capture, so the tweener (Tweener.swift) can match the
// nodes of two states and interpolate them. In a still render `CaptureInfo.isRecording` is false and
// no node carries any of this.

@MainActor
final class CaptureInfo {
    /// Set by an interaction capture before the first pass.
    static var isRecording = false

    /// Structural identity of the view that produced the node (the innermost primitive's resolve path).
    var path: IdentityPath?
    /// `.animation(_:value:)` / `.transaction` modifiers on this node, innermost first.
    var scopes: [AnimationScope] = []
    var transition: TransitionModel?
    var matched: [MatchedGeometry] = []
    /// Drawing parameters of an effect node that can be interpolated (opacity, scale, blur...).
    var effect: EffectParams?
    /// The animatable data of a shape node and how to rebuild its path from interpolated data.
    var shape: ShapeAnimation?
    /// `contentTransition(_:)` in effect (numeric text and symbol replacements cross-fade).
    var contentTransition: ContentTransition?
    /// A view whose look depends on the capture clock (spinner, symbol effect, TimelineView...).
    var clockDriven = false

    static func of(_ node: Node) -> CaptureInfo {
        if let info = node.capture { return info }
        let info = CaptureInfo()
        node.capture = info
        return info
    }

    static func stamp(_ nodes: [Node], from start: Int, _ path: IdentityPath) {
        guard start < nodes.count else { return }
        for i in start..<nodes.count where nodes[i].capture?.path == nil { of(nodes[i]).path = path }
    }
}

// MARK: - Animation scopes

/// An equatable value boxed so two states can be compared (`.animation(_:value:)`).
struct AnimationValue {
    let value: Any?
    let equals: (Any?) -> Bool
    init<V: Equatable>(_ v: V) {
        value = v
        equals = { ($0 as? V) == v }
    }
    private init() {
        value = nil
        equals = { _ in false }
    }
    /// The deprecated value-less forms: every change in the subtree animates.
    static let always = AnimationValue()
}

enum AnimationScope {
    case implicit(Animation?, AnimationValue)
    case transaction((inout Transaction) -> Void, AnimationValue)

    var value: AnimationValue {
        switch self {
        case .implicit(_, let v), .transaction(_, let v): return v
        }
    }
}

struct AnimationScopeModifier: ViewModifier, PrimitiveModifier {
    let scope: AnimationScope
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let start = out.count
        content.resolve(ctx, into: &out)
        guard CaptureInfo.isRecording else { return }
        for node in out[start...] { CaptureInfo.of(node).scopes.append(scope) }
    }
}

/// Records on every node of the content (used by `.transition`, `.matchedGeometryEffect`, ...).
struct CaptureRecordModifier: ViewModifier, PrimitiveModifier {
    let record: @MainActor (CaptureInfo, ResolveContext) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let start = out.count
        content.resolve(ctx, into: &out)
        guard CaptureInfo.isRecording else { return }
        for node in out[start...] { record(CaptureInfo.of(node), ctx) }
    }
}

extension View {
    func captureRecord(_ record: @escaping @MainActor (CaptureInfo, ResolveContext) -> Void) -> ModifiedContent<Self, CaptureRecordModifier> {
        modifier(CaptureRecordModifier(record: record))
    }
}

// MARK: - Matched geometry

struct MatchedGeometry {
    var id: AnyHashable
    var namespace: Namespace.ID
    var properties: MatchedGeometryProperties
    var anchor: UnitPoint
    var isSource: Bool
    var key: AnyHashable { AnyHashable([id, AnyHashable(namespace)]) }
}

// MARK: - Shapes

/// A shape's `animatableData` flattened to numbers, and a path builder that takes interpolated numbers back.
struct ShapeAnimation {
    var data: [Double]
    var typeID: ObjectIdentifier
    var path: ([Double], CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        data = AnimatableVector.flatten(shape.animatableData)
        typeID = ObjectIdentifier(S.self)
        path = { values, rect in
            var copy = shape
            if let restored = AnimatableVector.restore(values, like: shape.animatableData) { copy.animatableData = restored }
            return copy.path(in: rect)
        }
    }
}

/// Flattens `VectorArithmetic` values made of `Double` / `CGFloat` / `Float` / `AnimatablePair` (what every
/// built-in shape and effect uses) into numbers and back. Other types are not interpolated.
enum AnimatableVector {
    static func flatten(_ value: Any) -> [Double] {
        switch value {
        case let d as Double: return [d]
        case let c as CGFloat: return [Double(c)]
        case let f as Float: return [Double(f)]
        case is EmptyAnimatableData: return []
        case let pair as AnimatablePairProtocol: return flatten(pair.firstValue) + flatten(pair.secondValue)
        default: return []
        }
    }

    static func restore<V>(_ values: [Double], like template: V) -> V? {
        var index = 0
        let result = rebuild(template, values, &index)
        return index == values.count ? result as? V : nil
    }

    private static func rebuild(_ template: Any, _ values: [Double], _ index: inout Int) -> Any? {
        switch template {
        case is Double:
            guard index < values.count else { return nil }
            defer { index += 1 }
            return values[index]
        case is CGFloat:
            guard index < values.count else { return nil }
            defer { index += 1 }
            return CGFloat(values[index])
        case is Float:
            guard index < values.count else { return nil }
            defer { index += 1 }
            return Float(values[index])
        case is EmptyAnimatableData: return template
        case let pair as AnimatablePairProtocol:
            guard let a = rebuild(pair.firstValue, values, &index), let b = rebuild(pair.secondValue, values, &index) else { return nil }
            return pair.with(first: a, second: b)
        default: return nil
        }
    }
}

protocol AnimatablePairProtocol {
    var firstValue: Any { get }
    var secondValue: Any { get }
    func with(first: Any, second: Any) -> Any?
}

extension AnimatablePair: AnimatablePairProtocol {
    var firstValue: Any { first }
    var secondValue: Any { second }
    func with(first: Any, second: Any) -> Any? {
        guard let f = first as? First, let s = second as? Second else { return nil }
        return AnimatablePair(f, s)
    }
}

// MARK: - The capture clock

/// Time since the start of the capture, read by time-driven views (spinners, TimelineView(.animation),
/// PhaseAnimator, KeyframeAnimator, symbol effects, timer text). Zero and inactive in a still render.
/// It only advances by the capture's frame interval: no wall clock is involved.
enum CaptureClock {
    nonisolated(unsafe) static var isActive = false
    nonisolated(unsafe) static var time: Double = 0
    /// Set when a view read the clock during the last resolve: the capture re-resolves every frame.
    nonisolated(unsafe) static var wasRead = false

    static func read() -> Double {
        guard isActive else { return 0 }
        wasRead = true
        return time
    }

    /// "Now" of a capture when `--date` is not given: fixed, so the same input gives the same bytes.
    static let defaultDate = Date(timeIntervalSince1970: 1_749_462_060)  // 2025-06-09T09:41:00Z
}

extension Runtime {
    /// "Now" for views: the render's reference date, plus the capture clock during a capture.
    nonisolated static var now: Date {
        CaptureClock.isActive ? referenceDate.addingTimeInterval(CaptureClock.read()) : referenceDate
    }
}
