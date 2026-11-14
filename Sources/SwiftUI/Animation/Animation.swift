// Animation, Transaction, withAnimation and withTransaction.
//
// A still render never runs an animation: these values are only read when an interaction capture
// (`--steps`, `--animated`, `--duration`; see docs/INTERACTION.md) asks for in-between frames. Then
// `progress(at:)` gives the fraction of the way from the old to the new value after `t` seconds
// (springs overshoot past 1), and `duration` how long the capture has to run for it to settle.
//
// Apple's parameters are used throughout (see `AnimationDefaults` for the ones that are not public).

// MARK: - Animation

public struct Animation: Hashable, Sendable {
    indirect enum Base: Hashable, Sendable {
        /// `.default`: resolved for the rendered OS version when it is evaluated.
        case systemDefault
        case curve(UnitCurve, duration: Double)
        /// A damped harmonic oscillator, simulated in closed form (mass 1 implied by the ratios).
        case spring(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double)
        case custom(CustomAnimationBox)
    }
    var base: Base
    var delayTime: Double = 0
    var speedFactor: Double = 1
    /// nil: no repeat; 0: forever.
    var repeats: Int?
    var autoreverses = true

    init(_ base: Base) { self.base = base }
    init() { self.base = .systemDefault }

    public static let `default` = Animation(.systemDefault)

    public static let linear = Animation.linear(duration: AnimationDefaults.curveDuration)
    public static let easeIn = Animation.easeIn(duration: AnimationDefaults.curveDuration)
    public static let easeOut = Animation.easeOut(duration: AnimationDefaults.curveDuration)
    public static let easeInOut = Animation.easeInOut(duration: AnimationDefaults.curveDuration)
    public static let spring = Animation.spring(response: 0.5, dampingFraction: 0.825)
    public static let bouncy = Animation.bouncy(duration: 0.5)
    public static let smooth = Animation.smooth(duration: 0.5)
    public static let snappy = Animation.snappy(duration: 0.5)
    public static let interactiveSpring = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.86)

    public static func linear(duration: Double) -> Animation { Animation(.curve(.linear, duration: duration)) }
    public static func easeIn(duration: Double) -> Animation { Animation(.curve(.easeIn, duration: duration)) }
    public static func easeOut(duration: Double) -> Animation { Animation(.curve(.easeOut, duration: duration)) }
    public static func easeInOut(duration: Double) -> Animation { Animation(.curve(.easeInOut, duration: duration)) }
    public static func timingCurve(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35) -> Animation {
        Animation(.curve(UnitCurve(kind: .bezier(c0x, c0y, c1x, c1y)), duration: duration))
    }

    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        Animation.spring(Spring(response: response, dampingRatio: dampingFraction))
    }
    public static func spring(duration: Double = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
        Animation.spring(Spring(duration: duration, bounce: bounce))
    }
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation {
        Animation.spring(Spring(response: response, dampingRatio: dampingFraction))
    }
    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Animation {
        Animation(.spring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity))
    }
    public static func interpolatingSpring(duration: Double = 0.5, bounce: Double = 0, initialVelocity: Double = 0) -> Animation {
        let s = Spring(duration: duration, bounce: bounce)
        return Animation(.spring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: initialVelocity))
    }
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        Animation.spring(Spring.bouncy(duration: duration, extraBounce: extraBounce))
    }
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        Animation.spring(Spring.smooth(duration: duration, extraBounce: extraBounce))
    }
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        Animation.spring(Spring.snappy(duration: duration, extraBounce: extraBounce))
    }

    public func delay(_ delay: Double) -> Animation { var a = self; a.delayTime += delay; return a }
    public func speed(_ speed: Double) -> Animation { var a = self; a.speedFactor *= max(speed, 0.0001); return a }
    public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation {
        var a = self; a.repeats = max(1, count); a.autoreverses = autoreverses; return a
    }
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        var a = self; a.repeats = 0; a.autoreverses = autoreverses; return a
    }
}

extension Animation: CustomStringConvertible {
    public var description: String {
        var s: String
        switch base {
        case .systemDefault: s = "default"
        case .curve(let c, let d): s = "\(c.name)(\(AnimationDefaults.format(d))s)"
        case .spring(let m, let k, let c, _):
            let z = c / (2 * (k * m).squareRoot()), response = 2 * Double.pi / (k / m).squareRoot()
            s = "spring(response: \(AnimationDefaults.format(response)), damping: \(AnimationDefaults.format(z)))"
        case .custom(let box): s = "custom(\(box.name))"
        }
        if delayTime > 0 { s += ".delay(\(AnimationDefaults.format(delayTime)))" }
        if speedFactor != 1 { s += ".speed(\(AnimationDefaults.format(speedFactor)))" }
        if let r = repeats { s += r == 0 ? ".repeatForever" : ".repeatCount(\(r))" }
        return s
    }
}

extension UnitCurve {
    var name: String {
        switch kind {
        case .bezier(0, 0, 1, 1): return "linear"
        case .bezier(0.42, 0, 1, 1): return "easeIn"
        case .bezier(0, 0, 0.58, 1): return "easeOut"
        case .bezier(0.42, 0, 0.58, 1): return "easeInOut"
        case .bezier: return "timingCurve"
        default: return "circular"
        }
    }
}

// MARK: - Calibration

/// The values Apple does not document, in one place.
enum AnimationDefaults {
    /// `.linear`, `.easeIn`, ... without a duration, and `timingCurve`'s default.
    static let curveDuration = 0.35
    /// `Animation.default` on iOS 17 and later (and the aligned tvOS, watchOS, macOS releases) is the
    /// `.smooth` spring; before that it was `easeInOut(duration: 0.35)`. Every rendered look is 17+.
    static func resolvedDefault(osVersion: Int) -> Animation.Base {
        if osVersion >= 17 {
            let s = Spring.smooth(duration: 0.5)
            return .spring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: 0)
        }
        return .curve(.easeInOut, duration: 0.35)
    }
    /// A spring is considered settled once it stays within this fraction of the distance travelled.
    static let springEpsilon = 0.001
    /// Longest span one animation may run in a capture (repeatForever captures one cycle).
    static let maximumDuration = 10.0

    static func format(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}

// MARK: - Evaluation

extension Animation {
    @MainActor var resolvedBase: Base {
        if case .systemDefault = base { return AnimationDefaults.resolvedDefault(osVersion: RenderedPlatform.current) }
        return base
    }

    /// Length of one pass of the base animation (no delay, speed or repeat), in seconds.
    @MainActor var baseDuration: Double {
        switch resolvedBase {
        case .systemDefault: return 0
        case .curve(_, let d): return max(0, d)
        case .spring(let m, let k, let c, let v0):
            return SpringSolver(mass: m, stiffness: k, damping: c, initialVelocity: v0).settlingTime(epsilon: AnimationDefaults.springEpsilon)
        case .custom(let box): return box.duration
        }
    }

    /// How long a capture has to run for this animation to finish (one cycle of `repeatForever`).
    @MainActor var duration: Double {
        let one = baseDuration
        let cycles: Double
        switch repeats {
        case nil: cycles = 1
        case 0?: cycles = autoreverses ? 2 : 1
        case let n?: cycles = Double(n)
        }
        return min(AnimationDefaults.maximumDuration, delayTime + one * cycles / speedFactor)
    }

    /// Fraction of the change applied after `t` seconds (0 before the delay; may overshoot 1 for springs).
    @MainActor func progress(at t: Double) -> Double {
        let local = (t - delayTime) * speedFactor
        guard local > 0 else { return 0 }
        let one = baseDuration
        func base(_ x: Double) -> Double {
            switch resolvedBase {
            case .systemDefault: return 1
            case .curve(let curve, let d): return d <= 0 ? 1 : curve.value(at: x / d)
            case .spring(let m, let k, let c, let v0):
                return SpringSolver(mass: m, stiffness: k, damping: c, initialVelocity: v0).progress(at: x)
            case .custom(let box): return box.progress(at: x)
            }
        }
        guard let repeats else { return local >= one ? 1 : base(local) }
        guard one > 0 else { return 1 }
        let total = repeats == 0 ? (autoreverses ? 2 : 1) * one : Double(repeats) * one
        // After the last repeat the value jumps to the end state, as in SwiftUI.
        if repeats != 0, local >= total { return 1 }
        let cycle = Int(local / one)
        let within = local - Double(cycle) * one
        return autoreverses && cycle % 2 == 1 ? 1 - base(within) : base(within)
    }

    /// True when the end state is reached at `duration` (false for a repeatForever cycle that returns to the start).
    var endsAtTarget: Bool { !(repeats == 0 && autoreverses) }
}

/// Closed-form step response of a damped spring from 0 to 1, with an initial velocity in units per second.
struct SpringSolver {
    var mass: Double, stiffness: Double, damping: Double, initialVelocity: Double

    var omega: Double { (stiffness / max(mass, 1e-9)).squareRoot() }
    var zeta: Double { damping / (2 * (stiffness * max(mass, 1e-9)).squareRoot()) }

    /// Displacement from the target (1 at t = 0).
    func displacement(at t: Double) -> Double {
        let w0 = omega, z = zeta, v0 = initialVelocity
        if z < 1 - 1e-9 {
            let wd = w0 * (1 - z * z).squareRoot()
            let b = (z * w0 - v0) / wd
            return exp(-z * w0 * t) * (cos(wd * t) + b * sin(wd * t))
        } else if z <= 1 + 1e-9 {
            return exp(-w0 * t) * (1 + (w0 - v0) * t)
        } else {
            let root = (z * z - 1).squareRoot()
            let r1 = -w0 * (z - root), r2 = -w0 * (z + root)
            let c1 = (-v0 - r2) / (r1 - r2)
            return c1 * exp(r1 * t) + (1 - c1) * exp(r2 * t)
        }
    }

    func progress(at t: Double) -> Double { t <= 0 ? 0 : 1 - displacement(at: t) }

    /// The first time after which the displacement stays below `epsilon` (scanned at 1 ms).
    func settlingTime(epsilon: Double) -> Double {
        let step = 0.001
        var t = 0.0, lastOutside = 0.0
        // The envelope bounds the oscillation, so scanning until it drops below epsilon is enough.
        while t < AnimationDefaults.maximumDuration {
            if abs(displacement(at: t)) > epsilon { lastOutside = t }
            if envelope(at: t) < epsilon { break }
            t += step
        }
        return min(AnimationDefaults.maximumDuration, lastOutside + step)
    }

    private func envelope(at t: Double) -> Double {
        let w0 = omega, z = zeta
        if z < 1 - 1e-9 {
            let wd = w0 * (1 - z * z).squareRoot()
            let b = (z * w0 - initialVelocity) / wd
            return exp(-z * w0 * t) * (1 + b * b).squareRoot()
        }
        return abs(displacement(at: t)) * (t < 0.05 ? 10 : 1)
    }
}

/// A `CustomAnimation` sampled on a unit value.
final class CustomAnimationBox: Hashable, @unchecked Sendable {
    let base: AnyHashable
    let name: String
    let sample: (Double) -> Double?
    init<A: CustomAnimation>(_ animation: A) {
        base = AnyHashable(animation)
        name = "\(A.self)"
        sample = { t in
            var context = AnimationContext<Double>()
            return animation.animate(value: 1.0, time: t, context: &context)
        }
    }
    static func == (a: CustomAnimationBox, b: CustomAnimationBox) -> Bool { a.base == b.base }
    func hash(into hasher: inout Hasher) { hasher.combine(base) }

    var duration: Double {
        var t = 0.0
        while t < AnimationDefaults.maximumDuration, sample(t) != nil { t += 1.0 / 240 }
        return t
    }
    func progress(at t: Double) -> Double { sample(t) ?? 1 }
}

// MARK: - Transaction

public struct Transaction {
    public var animation: Animation?
    public var disablesAnimations = false
    public var isContinuous = false
    var values: [ObjectIdentifier: Any] = [:]
    public init() {}
    public init(animation: Animation?) { self.animation = animation }
}

public struct AnimationCompletionCriteria: Hashable, Sendable {
    let raw: Int
    public static let logicallyComplete = AnimationCompletionCriteria(raw: 0)
    public static let removed = AnimationCompletionCriteria(raw: 1)
}

/// The transaction of the state change being made, and the ones recorded since the capture last asked.
enum TransactionRecorder {
    /// Only an interaction capture records; a still render behaves exactly as before.
    nonisolated(unsafe) static var isRecording = false
    nonisolated(unsafe) static var current: Transaction?
    nonisolated(unsafe) static var recorded: [Transaction] = []
    nonisolated(unsafe) static var completions: [() -> Void] = []

    static func take() -> (transactions: [Transaction], completions: [() -> Void]) {
        defer { recorded = []; completions = [] }
        return (recorded, completions)
    }
}

public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withTransaction(Transaction(animation: animation), body)
}

public func withAnimation<Result>(_ animation: Animation? = .default, completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result {
    let result = try withTransaction(Transaction(animation: animation), body)
    if TransactionRecorder.isRecording { TransactionRecorder.completions.append(completion) }
    return result
}

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    guard TransactionRecorder.isRecording else { return try body() }
    let saved = TransactionRecorder.current
    TransactionRecorder.current = transaction
    defer { TransactionRecorder.current = saved }
    TransactionRecorder.recorded.append(transaction)
    return try body()
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var t = Transaction()
    t[keyPath: keyPath] = value
    return try withTransaction(t, body)
}

extension Binding {
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        let getter = self.getter, setter = self.setter
        var copy = Binding(get: getter, set: { value in withTransaction(transaction) { setter(value) } })
        copy.transaction = transaction
        return copy
    }
    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        transaction(Transaction(animation: animation))
    }
}
