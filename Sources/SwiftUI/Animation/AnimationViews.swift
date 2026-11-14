// PhaseAnimator, KeyframeAnimator, symbol effects, content transitions and haptics.
//
// A still render shows the first phase / the initial value. During an interaction capture the capture
// clock drives them (TimeDriven.swift): phases interpolate through the tweener, keyframe tracks are
// evaluated, indefinite symbol effects move.

// MARK: - PhaseAnimator

public struct PhaseAnimator<Phase: Equatable, Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let phases: [Phase]
    let trigger: AnimationValue?
    let content: (Phase) -> Content
    let animation: (Phase) -> Animation?

    public init<Phases: Sequence>(_ phases: Phases, @ViewBuilder content: @escaping (Phase) -> Content,
                                  animation: @escaping (Phase) -> Animation? = { _ in .default }) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.trigger = nil
        self.content = content
        self.animation = animation
    }
    public init<Phases: Sequence, Trigger: Equatable>(_ phases: Phases, trigger: Trigger,
                                                      @ViewBuilder content: @escaping (Phase) -> Content,
                                                      animation: @escaping (Phase) -> Animation? = { _ in .default }) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.trigger = AnimationValue(trigger)
        self.content = content
        self.animation = animation
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        PhaseTimeline(phases: phases, trigger: trigger, animation: animation).resolve(ctx, into: &out) { phase, ctx, out in
            resolveView(content(phase), ctx, into: &out)
        }
    }
}

struct PhaseAnimatorModifier<Phase: Equatable, Result: View>: ViewModifier, PrimitiveModifier {
    let phases: [Phase]
    let trigger: AnimationValue?
    let content: (ModifierContent, Phase) -> Result
    let animation: (Phase) -> Animation?
    func resolve(content inner: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        PhaseTimeline(phases: phases, trigger: trigger, animation: animation).resolve(ctx, into: &out) { phase, ctx, out in
            resolveView(content(inner, phase), ctx, into: &out)
        }
    }
}

extension View {
    public func phaseAnimator<Phase: Equatable, Result: View>(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Result,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        modifier(PhaseAnimatorModifier(phases: Array(phases), trigger: nil, content: { inner, phase in
            content(PlaceholderContentView(_ViewModifier_Content<EmptyModifier>(content: inner)), phase)
        }, animation: animation))
    }
    public func phaseAnimator<Phase: Equatable, Result: View>(
        _ phases: some Sequence<Phase>, trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Result,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        modifier(PhaseAnimatorModifier(phases: Array(phases), trigger: AnimationValue(trigger), content: { inner, phase in
            content(PlaceholderContentView(_ViewModifier_Content<EmptyModifier>(content: inner)), phase)
        }, animation: animation))
    }
}

// MARK: - Keyframes

public protocol KeyframeTrackContent<Value> {
    associatedtype Value: Animatable
    associatedtype Body: KeyframeTrackContent
    @KeyframeTrackContentBuilder<Self.Value> var body: Self.Body { get }
}
extension KeyframeTrackContent where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive keyframe") }
}
extension Never: Animatable {}
extension Never: KeyframeTrackContent {}

@resultBuilder
public struct KeyframeTrackContentBuilder<Value: Animatable> {
    public static func buildExpression<K: KeyframeTrackContent>(_ keyframe: K) -> K where K.Value == Value { keyframe }
    public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> _KeyframeGroup<Value> where K.Value == Value {
        _KeyframeGroup(segments: KeyframeSegment<Value>.collect(first))
    }
    public static func buildPartialBlock<K: KeyframeTrackContent>(accumulated: _KeyframeGroup<Value>, next: K) -> _KeyframeGroup<Value> where K.Value == Value {
        _KeyframeGroup(segments: accumulated.segments + KeyframeSegment<Value>.collect(next))
    }
}

public struct _KeyframeGroup<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = Never
    var segments: [KeyframeSegment<Value>] = []
}

public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = Never
    let segment: KeyframeSegment<Value>
    public init(_ to: Value) { segment = KeyframeSegment(to: to, duration: 0, kind: .move) }
}
public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = Never
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        segment = KeyframeSegment(to: to, duration: duration, kind: .linear(timingCurve))
    }
}
public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = Never
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        segment = KeyframeSegment(to: to, duration: duration, kind: .cubic(start: startVelocity, end: endVelocity))
    }
}
public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = Never
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {
        let solver = SpringSolver(mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: 0)
        segment = KeyframeSegment(to: to, duration: duration ?? solver.settlingTime(epsilon: 0.01), kind: .spring(spring))
    }
}

public protocol Keyframes<Value> {
    associatedtype Value
    associatedtype Body: Keyframes
    @KeyframesBuilder<Self.Value> var body: Self.Body { get }
}
extension Keyframes where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive keyframes type") }
}
extension Never: Keyframes {}

@resultBuilder
public struct KeyframesBuilder<Value> {
    public static func buildExpression<K: Keyframes>(_ keyframes: K) -> K where K.Value == Value { keyframes }
    public static func buildPartialBlock<K: Keyframes>(first: K) -> _KeyframesGroup<Value> where K.Value == Value {
        _KeyframesGroup(tracks: KeyframeTrackBox<Value>.collect(first))
    }
    public static func buildPartialBlock<K: Keyframes>(accumulated: _KeyframesGroup<Value>, next: K) -> _KeyframesGroup<Value> where K.Value == Value {
        _KeyframesGroup(tracks: accumulated.tracks + KeyframeTrackBox<Value>.collect(next))
    }
}

public struct _KeyframesGroup<Value>: Keyframes {
    public typealias Body = Never
    var tracks: [KeyframeTrackBox<Value>] = []
}

public struct KeyframeTrack<Root, TrackValue: Animatable, Content: KeyframeTrackContent>: Keyframes where Content.Value == TrackValue {
    public typealias Value = Root
    public typealias Body = Never
    let box: KeyframeTrackBox<Root>
    public init(_ keyPath: WritableKeyPath<Root, TrackValue>,
                @KeyframeTrackContentBuilder<TrackValue> content: () -> Content) {
        box = KeyframeTrackBox(keyPath: keyPath, segments: KeyframeSegment<TrackValue>.collect(content()))
    }
    public init(@KeyframeTrackContentBuilder<TrackValue> content: () -> Content) where Root == TrackValue {
        box = KeyframeTrackBox(keyPath: \Root.self, segments: KeyframeSegment<TrackValue>.collect(content()))
    }
}

public struct KeyframeTimeline<Value> {
    public var initialValue: Value
    let tracks: [KeyframeTrackBox<Value>]
    public init<K: Keyframes>(initialValue: Value, @KeyframesBuilder<Value> content: () -> K) where K.Value == Value {
        self.initialValue = initialValue
        tracks = KeyframeTrackBox<Value>.collect(content())
    }
    public var duration: TimeInterval { tracks.map(\.duration).max() ?? 0 }
    public func value(time: Double) -> Value {
        var value = initialValue
        for track in tracks { track.apply(&value, initialValue, time) }
        return value
    }
}

public struct KeyframeAnimator<Value, KeyframePath: Keyframes, Content: View>: View where KeyframePath.Value == Value {
    let initialValue: Value
    let repeating: Bool
    let trigger: AnimationValue?
    let content: (Value) -> Content
    let keyframes: (Value) -> KeyframePath
    public init(initialValue: Value, repeating: Bool = true,
                @ViewBuilder content: @escaping (Value) -> Content,
                @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath) {
        self.initialValue = initialValue
        self.repeating = repeating
        self.trigger = nil
        self.content = content
        self.keyframes = keyframes
    }
    public init<Trigger: Equatable>(initialValue: Value, trigger: Trigger,
                                    @ViewBuilder content: @escaping (Value) -> Content,
                                    @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath) {
        self.initialValue = initialValue
        self.repeating = false
        self.trigger = AnimationValue(trigger)
        self.content = content
        self.keyframes = keyframes
    }
    public var body: some View {
        _KeyframeClockView(initialValue: initialValue, repeating: repeating, trigger: trigger, keyframes: keyframes, content: content)
    }
}

extension View {
    public func keyframeAnimator<Value, Result: View>(
        initialValue: Value, repeating: Bool = true,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> Result,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
    ) -> some View {
        let base = self
        return _KeyframeClockView(initialValue: initialValue, repeating: repeating, trigger: nil, keyframes: keyframes,
                                  content: { content(PlaceholderContentView(base), $0) })
    }
    public func keyframeAnimator<Value, Result: View>(
        initialValue: Value, trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> Result,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
    ) -> some View {
        let base = self
        return _KeyframeClockView(initialValue: initialValue, repeating: false, trigger: AnimationValue(trigger), keyframes: keyframes,
                                  content: { content(PlaceholderContentView(base), $0) })
    }
}

// MARK: - Symbol effects

public struct SymbolEffectOptions: Equatable, Sendable {
    var repeatCount: Int?
    var speedFactor: Double = 1
    var isNonRepeating = false
    public static let `default` = SymbolEffectOptions()
    public static let nonRepeating = SymbolEffectOptions(isNonRepeating: true)
    public static let repeating = SymbolEffectOptions()
    public static func `repeat`(_ count: Int) -> SymbolEffectOptions { SymbolEffectOptions(repeatCount: count) }
    public static func `repeat`(periodic count: Int? = nil, delay: Double? = nil) -> SymbolEffectOptions { SymbolEffectOptions(repeatCount: count) }
    public static func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions(speedFactor: speed) }
    public func `repeat`(_ count: Int) -> SymbolEffectOptions { var o = self; o.repeatCount = count; return o }
    public func speed(_ speed: Double) -> SymbolEffectOptions { var o = self; o.speedFactor = speed; return o }
}

public protocol SymbolEffect: Sendable {}
public protocol IndefiniteSymbolEffect: SymbolEffect {}
public protocol DiscreteSymbolEffect: SymbolEffect {}
public protocol TransitionSymbolEffect: SymbolEffect {}
public protocol ContentTransitionSymbolEffect: SymbolEffect {}

public struct BounceSymbolEffect: DiscreteSymbolEffect, SymbolEffect {
    public var up: BounceSymbolEffect { self }
    public var down: BounceSymbolEffect { self }
    public var byLayer: BounceSymbolEffect { self }
    public var wholeSymbol: BounceSymbolEffect { self }
}
public struct PulseSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var byLayer: PulseSymbolEffect { self }
    public var wholeSymbol: PulseSymbolEffect { self }
}
public struct VariableColorSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var cumulative: VariableColorSymbolEffect { self }
    public var iterative: VariableColorSymbolEffect { self }
    public var reversing: VariableColorSymbolEffect { self }
    public var nonReversing: VariableColorSymbolEffect { self }
    public var hideInactiveLayers: VariableColorSymbolEffect { self }
    public var dimInactiveLayers: VariableColorSymbolEffect { self }
}
public struct ScaleSymbolEffect: IndefiniteSymbolEffect, SymbolEffect {
    public var up: ScaleSymbolEffect { self }
    public var down: ScaleSymbolEffect { self }
    public var byLayer: ScaleSymbolEffect { self }
    public var wholeSymbol: ScaleSymbolEffect { self }
}
public struct AppearSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var byLayer: AppearSymbolEffect { self }
    public var wholeSymbol: AppearSymbolEffect { self }
}
public struct DisappearSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var byLayer: DisappearSymbolEffect { self }
    public var wholeSymbol: DisappearSymbolEffect { self }
}
public struct ReplaceSymbolEffect: DiscreteSymbolEffect, TransitionSymbolEffect, ContentTransitionSymbolEffect, SymbolEffect {
    public var downUp: ReplaceSymbolEffect { self }
    public var upUp: ReplaceSymbolEffect { self }
    public var offUp: ReplaceSymbolEffect { self }
    public var byLayer: ReplaceSymbolEffect { self }
    public var wholeSymbol: ReplaceSymbolEffect { self }
}
public struct WiggleSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var up: WiggleSymbolEffect { self }
    public var down: WiggleSymbolEffect { self }
    public var left: WiggleSymbolEffect { self }
    public var right: WiggleSymbolEffect { self }
    public var forward: WiggleSymbolEffect { self }
    public var backward: WiggleSymbolEffect { self }
    public var clockwise: WiggleSymbolEffect { self }
    public var counterClockwise: WiggleSymbolEffect { self }
    public var byLayer: WiggleSymbolEffect { self }
    public var wholeSymbol: WiggleSymbolEffect { self }
    public func custom(angle: Angle) -> WiggleSymbolEffect { self }
}
public struct RotateSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var clockwise: RotateSymbolEffect { self }
    public var counterClockwise: RotateSymbolEffect { self }
    public var byLayer: RotateSymbolEffect { self }
    public var wholeSymbol: RotateSymbolEffect { self }
}
public struct BreatheSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, SymbolEffect {
    public var plain: BreatheSymbolEffect { self }
    public var pulse: BreatheSymbolEffect { self }
    public var byLayer: BreatheSymbolEffect { self }
    public var wholeSymbol: BreatheSymbolEffect { self }
}
public struct AutomaticSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, TransitionSymbolEffect, ContentTransitionSymbolEffect, SymbolEffect {}

extension SymbolEffect where Self == BounceSymbolEffect { public static var bounce: BounceSymbolEffect { BounceSymbolEffect() } }
extension SymbolEffect where Self == PulseSymbolEffect { public static var pulse: PulseSymbolEffect { PulseSymbolEffect() } }
extension SymbolEffect where Self == VariableColorSymbolEffect { public static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() } }
extension SymbolEffect where Self == ScaleSymbolEffect { public static var scale: ScaleSymbolEffect { ScaleSymbolEffect() } }
extension SymbolEffect where Self == AppearSymbolEffect { public static var appear: AppearSymbolEffect { AppearSymbolEffect() } }
extension SymbolEffect where Self == DisappearSymbolEffect { public static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() } }
extension SymbolEffect where Self == ReplaceSymbolEffect { public static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() } }
extension SymbolEffect where Self == WiggleSymbolEffect { public static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() } }
extension SymbolEffect where Self == RotateSymbolEffect { public static var rotate: RotateSymbolEffect { RotateSymbolEffect() } }
extension SymbolEffect where Self == BreatheSymbolEffect { public static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() } }
extension SymbolEffect where Self == AutomaticSymbolEffect { public static var automatic: AutomaticSymbolEffect { AutomaticSymbolEffect() } }

extension View {
    public func symbolEffect<T: DiscreteSymbolEffect & SymbolEffect, V: Equatable>(
        _ effect: T, options: SymbolEffectOptions = .default, value: V) -> some View { self }
    public func symbolEffect<T: IndefiniteSymbolEffect & SymbolEffect>(
        _ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true) -> some View {
        modifier(SymbolEffectClockModifier(kind: isActive ? SymbolEffectMotion(effect) : nil, speed: options.speedFactor))
    }
    public func symbolEffect<T: TransitionSymbolEffect & SymbolEffect>(
        _ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true) -> some View { self }
    public func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View { self }
}

// MARK: - Content transitions

public struct ContentTransition: Equatable, Sendable {
    let id: Int
    public static let identity = ContentTransition(id: 0)
    public static let opacity = ContentTransition(id: 1)
    public static let interpolate = ContentTransition(id: 2)
    public static let numericText = ContentTransition(id: 3)
    public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition(id: 3) }
    public static func numericText(value: Double) -> ContentTransition { ContentTransition(id: 3) }
    public static var symbolEffect: ContentTransition { ContentTransition(id: 4) }
    public static func symbolEffect<T: ContentTransitionSymbolEffect & SymbolEffect>(
        _ effect: T, options: SymbolEffectOptions = .default) -> ContentTransition { ContentTransition(id: 4) }
}

extension View {
    public func contentTransition(_ transition: ContentTransition) -> some View {
        captureRecord { info, _ in info.contentTransition = transition }
    }
    public func contentTransition(_ transition: ContentTransition, isEnabled: Bool) -> some View {
        captureRecord { info, _ in if isEnabled { info.contentTransition = transition } }
    }
}

// MARK: - Haptics

public struct SensoryFeedback: Equatable, Sendable {
    let id: Int
    public struct Weight: Equatable, Sendable {
        let id: Int
        public static let light = Weight(id: 0)
        public static let medium = Weight(id: 1)
        public static let heavy = Weight(id: 2)
    }
    public struct Flexibility: Equatable, Sendable {
        let id: Int
        public static let rigid = Flexibility(id: 0)
        public static let solid = Flexibility(id: 1)
        public static let soft = Flexibility(id: 2)
    }
    public static let success = SensoryFeedback(id: 0)
    public static let warning = SensoryFeedback(id: 1)
    public static let error = SensoryFeedback(id: 2)
    public static let selection = SensoryFeedback(id: 3)
    public static let increase = SensoryFeedback(id: 4)
    public static let decrease = SensoryFeedback(id: 5)
    public static let start = SensoryFeedback(id: 6)
    public static let stop = SensoryFeedback(id: 7)
    public static let alignment = SensoryFeedback(id: 8)
    public static let levelChange = SensoryFeedback(id: 9)
    public static let pathComplete = SensoryFeedback(id: 10)
    public static let impact = SensoryFeedback(id: 11)
    public static func impact(weight: Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback { SensoryFeedback(id: 11) }
    public static func impact(flexibility: Flexibility, intensity: Double = 1.0) -> SensoryFeedback { SensoryFeedback(id: 11) }
}

extension View {
    public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View { self }
    public func sensoryFeedback<T: Equatable>(trigger: T, _ feedback: @escaping (_ oldValue: T, _ newValue: T) -> SensoryFeedback?) -> some View { self }
    public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                                              condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool) -> some View { self }
}
