// `import CoreHaptics`: no haptic hardware. Engines start and play nothing.
@_exported import Foundation

public protocol CHHapticDeviceCapability {
    var supportsHaptics: Bool { get }
    var supportsAudio: Bool { get }
}
struct NoHaptics: CHHapticDeviceCapability {
    var supportsHaptics: Bool { false }
    var supportsAudio: Bool { false }
}
public struct CHHapticEvent: Sendable {
    public struct EventType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let hapticTransient = EventType(rawValue: "HapticTransient")
        public static let hapticContinuous = EventType(rawValue: "HapticContinuous")
    }
    public struct ParameterID: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let hapticIntensity = ParameterID(rawValue: "HapticIntensity")
        public static let hapticSharpness = ParameterID(rawValue: "HapticSharpness")
    }
    public init(eventType type: EventType, parameters: [CHHapticEventParameter], relativeTime time: TimeInterval, duration: TimeInterval = 0) {}
}
public struct CHHapticEventParameter: Sendable {
    public init(parameterID: CHHapticEvent.ParameterID, value: Float) {}
}
public final class CHHapticPattern: @unchecked Sendable {
    public init(events: [CHHapticEvent], parameters: [Any]) throws {}
}
public protocol CHHapticPatternPlayer: AnyObject {
    func start(atTime time: TimeInterval) throws
    func stop(atTime time: TimeInterval) throws
}
final class SilentPlayer: CHHapticPatternPlayer {
    func start(atTime time: TimeInterval) throws {}
    func stop(atTime time: TimeInterval) throws {}
}
public let CHHapticTimeImmediate: TimeInterval = 0
open class CHHapticEngine: NSObject, @unchecked Sendable {
    public class func capabilitiesForHardware() -> CHHapticDeviceCapability { NoHaptics() }
    open var stoppedHandler: ((Int) -> Void)?
    open var resetHandler: (() -> Void)?
    open var isAutoShutdownEnabled = false
    public override init() { super.init() }
    open func start() throws {}
    open func start() async throws {}
    open func stop(completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func makePlayer(with pattern: CHHapticPattern) throws -> CHHapticPatternPlayer { SilentPlayer() }
}
