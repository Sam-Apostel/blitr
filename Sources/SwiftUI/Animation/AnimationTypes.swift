// Animation vocabulary: Animatable conformances, UnitCurve, Spring, the custom-animation protocol and the
// `.animation` / `.transaction` modifiers. A still render shows the settled frame; an interaction capture
// (docs/INTERACTION.md) reads these to interpolate between states. `Animation` and `Transaction` live in
// Animation.swift.

// MARK: - Animatable conformances

extension Double: Animatable {
    public var animatableData: Double {
        get { self }
        set { self = newValue }
    }
}
extension Float: Animatable {
    public var animatableData: Float {
        get { self }
        set { self = newValue }
    }
}
extension CGFloat: Animatable {
    public var animatableData: CGFloat {
        get { self }
        set { self = newValue }
    }
}
extension CGPoint: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}
extension CGSize: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
}
extension CGRect: Animatable {
    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(origin.x, origin.y), AnimatablePair(size.width, size.height)) }
        set {
            origin = CGPoint(x: newValue.first.first, y: newValue.first.second)
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
}
extension Angle: Animatable {
    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}
extension UnitPoint: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}
extension AnimatablePair: Animatable {
    public var animatableData: AnimatablePair<First, Second> {
        get { self }
        set { self = newValue }
    }
}

public protocol AnimatableModifier: Animatable, ViewModifier {}

// MARK: - Animation additions

extension Animation {
    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0) -> Animation {
        Animation(.spring(mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: 0))
    }
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0) -> Animation {
        Animation(.spring(mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: initialVelocity))
    }
    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation { Animation(.curve(curve, duration: duration)) }
    public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0, blendDuration: TimeInterval = 0.25) -> Animation {
        Animation.spring(Spring(duration: duration, bounce: 0.14 + extraBounce))
    }
    public init<A: CustomAnimation>(_ base: A) { self.init(.custom(CustomAnimationBox(base))) }
}

public protocol AnimationStateKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct AnimationState<Value: VectorArithmetic> {
    var storage: [ObjectIdentifier: Any] = [:]
    public init() {}
    public subscript<K: AnimationStateKey>(key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

public struct AnimationContext<Value: VectorArithmetic> {
    public var state: AnimationState<Value>
    public var isLogicallyComplete: Bool
    public var environment: EnvironmentValues { _environment }
    var _environment = EnvironmentValues()
    public init() {
        state = AnimationState()
        isLogicallyComplete = false
    }
    public func withState<T>(_ state: AnimationState<T>) -> AnimationContext<T> {
        var context = AnimationContext<T>()
        context.state = state
        context.isLogicallyComplete = isLogicallyComplete
        context._environment = _environment
        return context
    }
}

public protocol CustomAnimation: Hashable {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V?
    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V?
    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool
}
extension CustomAnimation {
    public func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? { nil }
    public func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool { false }
}

// MARK: - UnitCurve

public struct UnitCurve: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case bezier(Double, Double, Double, Double)
        case circularIn, circularOut, circularInOut
    }
    let kind: Kind

    public static let linear = UnitCurve(kind: .bezier(0, 0, 1, 1))
    public static let easeIn = UnitCurve(kind: .bezier(0.42, 0, 1, 1))
    public static let easeOut = UnitCurve(kind: .bezier(0, 0, 0.58, 1))
    public static let easeInOut = UnitCurve(kind: .bezier(0.42, 0, 0.58, 1))
    public static let circularEaseIn = UnitCurve(kind: .circularIn)
    public static let circularEaseOut = UnitCurve(kind: .circularOut)
    public static let circularEaseInOut = UnitCurve(kind: .circularInOut)

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(kind: .bezier(Double(startControlPoint.x), Double(startControlPoint.y),
                                Double(endControlPoint.x), Double(endControlPoint.y)))
    }

    public func value(at progress: Double) -> Double {
        let t = min(1, max(0, progress))
        switch kind {
        case let .bezier(x1, y1, x2, y2):
            func coordinate(_ s: Double, _ a: Double, _ b: Double) -> Double {
                let u = 1 - s
                return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
            }
            // Solve x(s) = t by bisection, then evaluate y(s).
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if coordinate(mid, x1, x2) < t { lo = mid } else { hi = mid }
            }
            return coordinate((lo + hi) / 2, y1, y2)
        case .circularIn:
            return 1 - (1 - t * t).squareRoot()
        case .circularOut:
            return (1 - (t - 1) * (t - 1)).squareRoot()
        case .circularInOut:
            return t < 0.5 ? (1 - (1 - 4 * t * t).squareRoot()) / 2 : ((1 - (-2 * t + 2) * (-2 * t + 2)).squareRoot() + 1) / 2
        }
    }

    public func velocity(at progress: Double) -> Double {
        let h = 1e-4
        let a = max(0, progress - h), b = min(1, progress + h)
        return b > a ? (value(at: b) - value(at: a)) / (b - a) : 0
    }

    public var inverse: UnitCurve {
        switch kind {
        case let .bezier(x1, y1, x2, y2): return UnitCurve(kind: .bezier(y1, x1, y2, x2))
        case .circularIn: return .circularEaseOut
        case .circularOut: return .circularEaseIn
        case .circularInOut: return .circularEaseInOut
        }
    }
}

// MARK: - Spring

public struct Spring: Hashable, Sendable {
    public var mass: Double
    public var stiffness: Double
    public var damping: Double

    public init(mass: Double = 1.0, stiffness: Double, damping: Double, allowOverDamping: Bool = false) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = allowOverDamping ? damping : min(damping, 2 * (stiffness * mass).squareRoot())
    }
    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        let omega = 2 * Double.pi / max(duration, 0.0001)
        mass = 1
        stiffness = omega * omega
        damping = bounce >= 0 ? 2 * omega * (1 - bounce) : 2 * omega / (1 + bounce)
    }
    public init(response: Double, dampingRatio: Double) {
        let omega = 2 * Double.pi / max(response, 0.0001)
        mass = 1
        stiffness = omega * omega
        damping = 2 * omega * dampingRatio
    }
    public init(settlingDuration: TimeInterval, dampingRatio: Double, epsilon: Double = 0.001) {
        let omega = -log(epsilon) / (max(dampingRatio, 0.01) * max(settlingDuration, 0.0001))
        mass = 1
        stiffness = omega * omega
        damping = 2 * omega * dampingRatio
    }

    public static var smooth: Spring { Spring(duration: 0.5, bounce: 0) }
    public static var snappy: Spring { Spring(duration: 0.5, bounce: 0.15) }
    public static var bouncy: Spring { Spring(duration: 0.5, bounce: 0.3) }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Spring {
        Spring(duration: duration, bounce: extraBounce)
    }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Spring {
        Spring(duration: duration, bounce: 0.15 + extraBounce)
    }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Spring {
        Spring(duration: duration, bounce: 0.3 + extraBounce)
    }

    var naturalFrequency: Double { (stiffness / mass).squareRoot() }
    public var response: Double { 2 * Double.pi / naturalFrequency }
    public var dampingRatio: Double { damping / (2 * (stiffness * mass).squareRoot()) }
    public var duration: TimeInterval { response }
    public var bounce: Double {
        let ratio = dampingRatio
        return ratio <= 1 ? 1 - ratio : 1 / ratio - 1
    }
    public var settlingDuration: TimeInterval { settlingDuration(target: 1.0, epsilon: 0.001) }

    /// Fraction of the way from 0 to 1 after `time` for a step response (zero initial velocity).
    func progress(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        let w0 = naturalFrequency, z = dampingRatio
        let x: Double
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            x = exp(-z * w0 * time) * (cos(wd * time) + z * w0 / wd * sin(wd * time))
        } else if z == 1 {
            x = exp(-w0 * time) * (1 + w0 * time)
        } else {
            let root = (z * z - 1).squareRoot()
            let s1 = -w0 * (z - root), s2 = -w0 * (z + root)
            x = (s2 * exp(s1 * time) - s1 * exp(s2 * time)) / (s2 - s1)
        }
        return 1 - x
    }

    public func value<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        var result = target
        result.scale(by: progress(at: time))
        return result
    }
    public func velocity<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        let h = 1e-3
        var result = target
        result.scale(by: (progress(at: time + h) - progress(at: max(0, time - h))) / (time > 0 ? 2 * h : h))
        return result
    }
    public func force<V: VectorArithmetic>(target: V, position: V, velocity: V) -> V {
        var spring = target - position
        spring.scale(by: stiffness)
        var drag = velocity
        drag.scale(by: damping)
        return spring - drag
    }
    public func settlingDuration<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, epsilon: Double) -> TimeInterval {
        let z = dampingRatio
        guard z > 0 else { return .infinity }
        return -log(epsilon) / (min(z, 1) * naturalFrequency)
    }
    public func update<V: VectorArithmetic>(value: inout V, velocity: inout V, target: V, deltaTime: TimeInterval) {
        var accel = force(target: target, position: value, velocity: velocity)
        accel.scale(by: 1 / mass)
        var dv = accel
        dv.scale(by: deltaTime)
        velocity += dv
        var dx = velocity
        dx.scale(by: deltaTime)
        value += dx
    }
}

// MARK: - Animation modifiers

/// What `.animation(_:body:)` and friends hand to their closure: the modified view itself.
public struct PlaceholderContentView<Value>: View, PrimitiveView {
    public typealias Body = Never
    let content: AnyView
    init<V: View>(_ content: V) { self.content = AnyView(content) }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { content.resolve(ctx, into: &out) }
}

public protocol TransactionKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

extension Transaction {
    public subscript<K: TransactionKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }
    public var tracksVelocity: Bool {
        get { false }
        set {}
    }
}

// The modifiers record what they say on the nodes they produce (Animation/AnimationScope.swift); the
// capture reads it when it interpolates. Nothing changes in a still render.
extension View {
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AnimationScopeModifier(scope: .implicit(animation, AnimationValue(value))))
    }
    @available(iOS, deprecated: 15.0)
    public func animation(_ animation: Animation?) -> some View {
        modifier(AnimationScopeModifier(scope: .implicit(animation, AnimationValue.always)))
    }
    public func animation<V: View>(_ animation: Animation?, @ViewBuilder body: (PlaceholderContentView<Self>) -> V) -> some View {
        body(PlaceholderContentView(self)).modifier(AnimationScopeModifier(scope: .implicit(animation, AnimationValue.always)))
    }

    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(AnimationScopeModifier(scope: .transaction(transform, AnimationValue.always)))
    }
    public func transaction<V: Equatable>(value: V, _ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(AnimationScopeModifier(scope: .transaction(transform, AnimationValue(value))))
    }
    @available(iOS, deprecated: 15.0)
    public func transaction(_ transaction: Transaction) -> some View {
        modifier(AnimationScopeModifier(scope: .transaction({ $0 = transaction }, AnimationValue.always)))
    }
    public func transaction<V: View>(_ transform: @escaping (inout Transaction) -> Void,
                                     @ViewBuilder body: (PlaceholderContentView<Self>) -> V) -> some View {
        body(PlaceholderContentView(self)).modifier(AnimationScopeModifier(scope: .transaction(transform, AnimationValue.always)))
    }
}
