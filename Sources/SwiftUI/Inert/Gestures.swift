// Gestures. A screenshot has no input, so gestures exist only so that app code compiles:
// the gesture types carry their configuration, the modifiers return the view unchanged.

public protocol Gesture<Value> {
    associatedtype Value
    associatedtype Body: Gesture
    var body: Self.Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

extension Gesture where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive gesture and has no body") }
}

public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all: GestureMask = [.gesture, .subviews]
}

// MARK: - Primitive gestures

public struct TapGesture: Gesture {
    public typealias Value = ()
    public typealias Body = Never
    public var count: Int
    public init(count: Int = 1) { self.count = count }
}

public struct SpatialTapGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var location: CGPoint
        public init(location: CGPoint) { self.location = location }
    }
    public typealias Body = Never
    public var count: Int
    public var coordinateSpace: CoordinateSpace
    @_disfavoredOverload
    public init(count: Int = 1, coordinateSpace: CoordinateSpace) {
        self.count = count
        self.coordinateSpace = coordinateSpace
    }
    public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }
}

public struct LongPressGesture: Gesture {
    public typealias Value = Bool
    public typealias Body = Never
    public var minimumDuration: Double
    public var maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }
    @available(*, deprecated)
    public init(minimumDuration: Double = 0.5, pressing: Bool) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = 10
    }
}

public struct DragGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var velocity: CGSize
        public var translation: CGSize {
            CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
        }
        public var predictedEndLocation: CGPoint {
            CGPoint(x: location.x + velocity.width * 0.25, y: location.y + velocity.height * 0.25)
        }
        public var predictedEndTranslation: CGSize {
            CGSize(width: translation.width + velocity.width * 0.25, height: translation.height + velocity.height * 0.25)
        }
        public init(time: Date = Date(), location: CGPoint = .zero, startLocation: CGPoint = .zero, velocity: CGSize = .zero) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.velocity = velocity
        }
    }
    public typealias Body = Never
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    @_disfavoredOverload
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }
}

public struct MagnifyGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
        public init(time: Date = Date(), magnification: CGFloat = 1, velocity: CGFloat = 0,
                    startAnchor: UnitPoint = .center, startLocation: CGPoint = .zero) {
            self.time = time
            self.magnification = magnification
            self.velocity = velocity
            self.startAnchor = startAnchor
            self.startLocation = startLocation
        }
    }
    public typealias Body = Never
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
}

public struct MagnificationGesture: Gesture {
    public typealias Value = CGFloat
    public typealias Body = Never
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
}

public struct RotateGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var rotation: Angle
        public var velocity: Angle
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
        public init(time: Date = Date(), rotation: Angle = .zero, velocity: Angle = .zero,
                    startAnchor: UnitPoint = .center, startLocation: CGPoint = .zero) {
            self.time = time
            self.rotation = rotation
            self.velocity = velocity
            self.startAnchor = startAnchor
            self.startLocation = startLocation
        }
    }
    public typealias Body = Never
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
}

public struct RotationGesture: Gesture {
    public typealias Value = Angle
    public typealias Body = Never
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
}

// MARK: - Composition

public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
    public enum Value {
        case first(First.Value)
        case second(First.Value, Second.Value?)
    }
    public typealias Body = Never
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}
extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SequenceGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
    public struct Value {
        public var first: First.Value?
        public var second: Second.Value?
    }
    public typealias Body = Never
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}
extension SimultaneousGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SimultaneousGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
    public enum Value {
        case first(First.Value)
        case second(Second.Value)
    }
    public typealias Body = Never
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}
extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension ExclusiveGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

public struct AnyGesture<Value>: Gesture {
    public typealias Body = Never
    public init<G: Gesture>(_ gesture: G) where G.Value == Value {}
}

// MARK: - Gesture modifiers

public struct _ChangedGesture<Base: Gesture>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    var base: Base
}
public struct _EndedGesture<Base: Gesture>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    var base: Base
}
public struct GestureStateGesture<Base: Gesture, State>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    var base: Base
}
public struct _MapGesture<Base: Gesture, Value>: Gesture {
    public typealias Body = Never
    var base: Base
}
public struct _ModifiersGesture<Base: Gesture>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    var base: Base
}

extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> {
        _EndedGesture(base: self)
    }
    public func updating<State>(_ state: GestureState<State>,
                                body: @escaping (Self.Value, inout State, inout Transaction) -> Void) -> GestureStateGesture<Self, State> {
        GestureStateGesture(base: self)
    }
    public func map<T>(_ body: @escaping (Self.Value) -> T) -> _MapGesture<Self, T> {
        _MapGesture(base: self)
    }
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> {
        SimultaneousGesture(self, other)
    }
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
        SequenceGesture(self, other)
    }
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> {
        ExclusiveGesture(self, other)
    }
    public func modifiers(_ modifiers: EventModifiers) -> _ModifiersGesture<Self> {
        _ModifiersGesture(base: self)
    }
}

extension Gesture where Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
        _ChangedGesture(base: self)
    }
}

// MARK: - View modifiers

/// Gestures that make a view a touch target (taps and long presses, also after `onEnded`, `updating`...).
protocol AXTapGesture {}
extension TapGesture: AXTapGesture {}
extension SpatialTapGesture: AXTapGesture {}
extension LongPressGesture: AXTapGesture {}
extension _ChangedGesture: AXTapGesture where Base: AXTapGesture {}
extension _EndedGesture: AXTapGesture where Base: AXTapGesture {}
extension GestureStateGesture: AXTapGesture where Base: AXTapGesture {}
extension _ModifiersGesture: AXTapGesture where Base: AXTapGesture {}

extension View {
    /// A tap target without a default action the tool could simulate (`.gesture` does not keep its handler).
    func axTappable(enabled: Bool = true, activate: (@MainActor () -> Void)? = nil) -> ModifiedContent<Self, AXModifier> {
        axInfo(context: { ctx in
            AccessibilityInfo {
                guard enabled else { return }
                $0.isElement = true
                $0.isTapTarget = true
                $0.isEnabled = ctx.env.isEnabled
                $0.activate = activate
            }
        })
    }

    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { axTappable(enabled: gesture is AXTapGesture) }
    public func gesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View { axTappable(enabled: isEnabled && gesture is AXTapGesture) }
    public func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { axTappable(enabled: gesture is AXTapGesture) }
    public func highPriorityGesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View { axTappable(enabled: isEnabled && gesture is AXTapGesture) }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { axTappable(enabled: gesture is AXTapGesture) }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View { axTappable(enabled: isEnabled && gesture is AXTapGesture) }

    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { axTappable(activate: { action() }) }
    @_disfavoredOverload
    public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace,
                             perform action: @escaping (CGPoint) -> Void) -> some View { axTappable() }
    public func onTapGesture(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local,
                             perform action: @escaping (CGPoint) -> Void) -> some View { axTappable() }

    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
        axTappable().interaction { _ in var h = InteractionHandlers(); h.longPress = { action() }; return h }
    }
    @_disfavoredOverload
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   pressing onPressingChanged: ((Bool) -> Void)? = nil,
                                   perform action: @escaping () -> Void) -> some View {
        axTappable().interaction { _ in var h = InteractionHandlers(); h.longPress = { action() }; return h }
    }

    public func allowsHitTesting(_ enabled: Bool) -> some View { self }
}
