// Views driven by time rather than by a state change: PhaseAnimator, KeyframeAnimator, indefinite symbol
// effects and the activity spinner. They read `CaptureClock`; in a still render the clock is inactive and
// they show their first phase / initial value / resting look, exactly as before.

// MARK: - Start times of triggered animations

/// When the trigger of a `PhaseAnimator(trigger:)` / `KeyframeAnimator(trigger:)` last changed, per view.
@MainActor
enum ClockTriggers {
    private static var entries: [IdentityPath: (value: AnimationValue, start: Double?)] = [:]

    static func reset() { entries = [:] }

    /// The capture time the view's animation started at, or nil when its trigger has not changed yet.
    static func start(_ path: IdentityPath, trigger: AnimationValue, now: Double) -> Double? {
        guard let entry = entries[path] else {
            entries[path] = (trigger, nil)
            return nil
        }
        if !trigger.equals(entry.value.value) {
            entries[path] = (trigger, now)
            return now
        }
        return entry.start
    }
}

// MARK: - Phases

extension Animation {
    /// When SwiftUI considers the animation done for sequencing (a spring: within 1% of its target).
    @MainActor var logicalDuration: Double {
        var base: Double
        switch resolvedBase {
        case .systemDefault: base = 0
        case .curve(_, let d): base = max(0, d)
        case .spring(let m, let k, let c, let v0):
            base = SpringSolver(mass: m, stiffness: k, damping: c, initialVelocity: v0).settlingTime(epsilon: 0.01)
        case .custom(let box): base = box.duration
        }
        if let repeats, repeats > 0 { base *= Double(repeats) }
        return delayTime + base / speedFactor
    }
}

@MainActor
struct PhaseTimeline<Phase: Equatable> {
    let phases: [Phase]
    let trigger: AnimationValue?
    let animation: (Phase) -> Animation?

    func resolve(_ ctx: ResolveContext, into out: inout [Node], build: (Phase, ResolveContext, inout [Node]) -> Void) {
        guard let first = phases.first else { return }
        guard CaptureClock.isActive, phases.count > 1 else {
            build(first, ctx, &out)
            return
        }
        let now = CaptureClock.read()
        var local = now
        if let trigger {
            guard let start = ClockTriggers.start(ctx.path, trigger: trigger, now: now) else {
                build(first, ctx, &out)
                return
            }
            local = now - start
        }
        // Segment i goes from phase i to phase i+1 (the last one back to the first), with the animation
        // of the phase it goes to.
        let n = phases.count
        let durations = (0..<n).map { animation(phases[($0 + 1) % n])?.logicalDuration ?? 0 }
        let total = durations.reduce(0, +)
        guard total > 0 else { build(first, ctx, &out); return }
        if trigger == nil { local = local.truncatingRemainder(dividingBy: total) }
        guard local < total else { build(first, ctx, &out); return }
        var index = 0
        while index < n - 1, local >= durations[index] {
            local -= durations[index]
            index += 1
        }
        let from = phases[index], to = phases[(index + 1) % n]
        guard let curve = animation(to) else { build(to, ctx, &out); return }
        var fromNodes: [Node] = [], toNodes: [Node] = []
        build(from, ctx, &fromNodes)
        build(to, ctx, &toNodes)
        func single(_ nodes: [Node]) -> Node {
            nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: .center, spacing: nil, children: nodes)
        }
        out.append(TweenNode(from: single(fromNodes), to: single(toNodes), progress: curve.progress(at: local)))
    }
}

/// Two versions of a subtree and how far between them the picture is.
final class TweenNode: Node {
    let from: Node
    var to: Node { children[0] }
    let progress: Double

    init(from: Node, to: Node, progress: Double) {
        self.from = from
        self.progress = progress
        super.init(children: [to])
        traits = to.traits
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let a = from.sizeThatFits(proposal), b = to.sizeThatFits(proposal)
        let t = CGFloat(min(1, max(0, progress)))
        return CGSize(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let proposal = proposal(forSize: size)
        let a = from.sizeThatFits(proposal), b = to.sizeThatFits(proposal)
        from.place(at: CGPoint(x: (size.width - a.width) / 2, y: (size.height - a.height) / 2), size: a, ctx)
        to.place(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2), size: b, ctx)
    }

    override func spacing(_ edge: Edge) -> CGFloat? { to.spacing(edge) }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? { to.explicitAlignment(key, size: size) }

    override func drawContent(_ p: Painter) {
        let tween = Tweener(before: from, after: to, transaction: Transaction(animation: .linear))
        tween.fixedProgress = progress
        let outer = Tweener.active
        Tweener.active = tween
        to.draw(p)
        Tweener.active = outer
    }
}

// MARK: - Keyframes

struct KeyframeSegment<Value: Animatable> {
    enum Kind {
        case move
        case linear(UnitCurve)
        case cubic(start: Value?, end: Value?)
        case spring(Spring)
    }
    var to: Value
    var duration: Double
    var kind: Kind

    static func collect<K: KeyframeTrackContent>(_ content: K) -> [KeyframeSegment<Value>] where K.Value == Value {
        if let source = content as? KeyframeSegmentSource { return source.anySegments as? [KeyframeSegment<Value>] ?? [] }
        if K.Body.self == Never.self { return [] }
        return (content.body as? KeyframeSegmentSource)?.anySegments as? [KeyframeSegment<Value>] ?? []
    }

    private static func mix(_ a: Value, _ b: Value, _ t: Double) -> Value {
        var delta = b.animatableData - a.animatableData
        delta.scale(by: t)
        var result = b
        result.animatableData = a.animatableData + delta
        return result
    }

    /// The track's value at `time`, starting from `initial`.
    static func value(_ segments: [KeyframeSegment<Value>], initial: Value, time: Double) -> Value {
        var start = 0.0
        var from = initial
        for (i, segment) in segments.enumerated() {
            let end = start + segment.duration
            if time >= end {
                from = segment.to
                start = end
                continue
            }
            guard time >= start, segment.duration > 0 else { return from }
            let local = time - start, u = local / segment.duration
            switch segment.kind {
            case .move:
                return segment.to
            case .linear(let curve):
                return mix(from, segment.to, curve.value(at: u))
            case .spring(let spring):
                let solver = SpringSolver(mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: 0)
                return mix(from, segment.to, solver.progress(at: local))
            case .cubic(let startVelocity, let endVelocity):
                // A cubic Hermite span; without explicit velocities the tangents are Catmull-Rom's.
                typealias Vector = Value.AnimatableData
                func scaled(_ v: Vector, _ k: Double) -> Vector { var r = v; r.scale(by: k); return r }
                let p0 = from.animatableData, p1 = segment.to.animatableData
                var m0 = Vector.zero, m1 = Vector.zero
                if let startVelocity {
                    m0 = startVelocity.animatableData
                } else if i > 0 {
                    let before = i > 1 ? segments[i - 2].to : initial
                    let span = segments[i - 1].duration + segment.duration
                    if span > 0 { m0 = scaled(p1 - before.animatableData, 1 / span) }
                }
                if let endVelocity {
                    m1 = endVelocity.animatableData
                } else if i + 1 < segments.count {
                    let span = segment.duration + segments[i + 1].duration
                    if span > 0 { m1 = scaled(segments[i + 1].to.animatableData - p0, 1 / span) }
                }
                let u2 = u * u, u3 = u2 * u, d = segment.duration
                let h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2
                var result = segment.to
                result.animatableData = scaled(p0, h00) + scaled(m0, h10 * d) + scaled(p1, h01) + scaled(m1, h11 * d)
                return result
            }
        }
        return from
    }
}

protocol KeyframeSegmentSource { var anySegments: Any { get } }
extension _KeyframeGroup: KeyframeSegmentSource { var anySegments: Any { segments } }
extension MoveKeyframe: KeyframeSegmentSource { var anySegments: Any { [segment] } }
extension LinearKeyframe: KeyframeSegmentSource { var anySegments: Any { [segment] } }
extension CubicKeyframe: KeyframeSegmentSource { var anySegments: Any { [segment] } }
extension SpringKeyframe: KeyframeSegmentSource { var anySegments: Any { [segment] } }

/// One track of a keyframe timeline: writes its value at a time into the animated value.
struct KeyframeTrackBox<Root> {
    let duration: Double
    let apply: (inout Root, Root, Double) -> Void

    init<V: Animatable>(keyPath: WritableKeyPath<Root, V>, segments: [KeyframeSegment<V>]) {
        duration = segments.reduce(0) { $0 + $1.duration }
        apply = { root, initial, time in
            root[keyPath: keyPath] = KeyframeSegment<V>.value(segments, initial: initial[keyPath: keyPath], time: time)
        }
    }

    static func collect<K: Keyframes>(_ keyframes: K) -> [KeyframeTrackBox<Root>] where K.Value == Root {
        if let source = keyframes as? KeyframeTrackSource { return source.anyTracks as? [KeyframeTrackBox<Root>] ?? [] }
        if K.Body.self == Never.self { return [] }
        return (keyframes.body as? KeyframeTrackSource)?.anyTracks as? [KeyframeTrackBox<Root>] ?? []
    }
}

protocol KeyframeTrackSource { var anyTracks: Any { get } }
extension _KeyframesGroup: KeyframeTrackSource { var anyTracks: Any { tracks } }
extension KeyframeTrack: KeyframeTrackSource { var anyTracks: Any { [box] } }

/// The content of a keyframe animator at the capture clock's time.
struct _KeyframeClockView<Value, Path: Keyframes, Content: View>: View, PrimitiveView where Path.Value == Value {
    typealias Body = Never
    let initialValue: Value
    let repeating: Bool
    let trigger: AnimationValue?
    let keyframes: (Value) -> Path
    let content: (Value) -> Content

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        var value = initialValue
        if CaptureClock.isActive {
            let tracks = KeyframeTrackBox<Value>.collect(keyframes(initialValue))
            let duration = tracks.map(\.duration).max() ?? 0
            let now = CaptureClock.read()
            var time: Double?
            if let trigger {
                if let start = ClockTriggers.start(ctx.path, trigger: trigger, now: now), now - start < duration { time = now - start }
            } else if duration > 0 {
                time = repeating ? now.truncatingRemainder(dividingBy: duration) : min(now, duration)
            }
            if let time { for track in tracks { track.apply(&value, initialValue, time) } }
        }
        resolveView(content(value), ctx, into: &out)
    }
}

// MARK: - Symbol effects

/// How an indefinite symbol effect moves a symbol while it is active. Layered motion ("by layer",
/// variable color) cannot be drawn from single-layer symbols: variable color pulses instead.
enum SymbolEffectMotion {
    case pulse, breathe, rotate(clockwise: Bool), wiggle, variableColor

    init?<T: SymbolEffect>(_ effect: T) {
        switch effect {
        case is PulseSymbolEffect: self = .pulse
        case is BreatheSymbolEffect: self = .breathe
        case is RotateSymbolEffect: self = .rotate(clockwise: true)
        case is WiggleSymbolEffect: self = .wiggle
        case is VariableColorSymbolEffect: self = .variableColor
        default: return nil
        }
    }

    /// Named periods so the motion can be calibrated against recordings.
    static let pulsePeriod = 1.2, breathePeriod = 1.8, rotatePeriod = 2.0, wigglePeriod = 0.6
    static let pulseMinimumOpacity = 0.35, breatheScale = 1.12, wiggleAngle = 12.0

    @MainActor func params(at t: Double) -> EffectParams {
        func wave(_ period: Double) -> Double { 0.5 - 0.5 * cos(2 * Double.pi * t / period) }
        switch self {
        case .pulse, .variableColor:
            return .opacity(1 - (1 - SymbolEffectMotion.pulseMinimumOpacity) * wave(SymbolEffectMotion.pulsePeriod))
        case .breathe:
            let k = 1 + (SymbolEffectMotion.breatheScale - 1) * wave(SymbolEffectMotion.breathePeriod)
            return .scale(CGSize(width: k, height: k), .center)
        case .rotate(let clockwise):
            return .rotation(.degrees((clockwise ? 360 : -360) * t / SymbolEffectMotion.rotatePeriod), .center)
        case .wiggle:
            return .rotation(.degrees(SymbolEffectMotion.wiggleAngle * sin(2 * Double.pi * t / SymbolEffectMotion.wigglePeriod)), .center)
        }
    }
}

struct SymbolEffectClockModifier: ViewModifier, PrimitiveModifier {
    let kind: SymbolEffectMotion?
    let speed: Double
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        guard CaptureClock.isActive, let kind else {
            content.resolve(ctx, into: &out)
            return
        }
        let params = kind.params(at: CaptureClock.read() * speed)
        for child in content.nodes(ctx) {
            let node = EffectNode(child: child, effect: params.draw)
            CaptureInfo.of(node).effect = params
            out.append(node)
        }
    }
}

/// The activity indicator: its eight ticks step round once a second during a capture.
struct ClockSpinModifier: ViewModifier, PrimitiveModifier {
    static let period = 1.0
    static let steps = 8
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        guard CaptureClock.isActive else {
            content.resolve(ctx, into: &out)
            return
        }
        let step = Int((CaptureClock.read() / ClockSpinModifier.period * Double(ClockSpinModifier.steps)).rounded(.down)) % ClockSpinModifier.steps
        let params = EffectParams.rotation(.degrees(Double(step) * 360 / Double(ClockSpinModifier.steps)), .center)
        for child in content.nodes(ctx) {
            // Step 0 is the resting look: no node is added, so the frame matches a still render.
            out.append(step == 0 ? child : EffectNode(child: child, effect: params.draw))
        }
    }
}
