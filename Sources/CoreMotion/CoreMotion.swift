// `import CoreMotion`: no motion hardware; updates never arrive.
@_exported import Foundation

public enum CMAuthorizationStatus: Int, Sendable { case notDetermined, restricted, denied, authorized }
open class CMLogItem: NSObject, @unchecked Sendable { open var timestamp: TimeInterval { 0 } }
public struct CMAttitudeReferenceFrame: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let xArbitraryZVertical = CMAttitudeReferenceFrame(rawValue: 1)
}
open class CMDeviceMotion: CMLogItem, @unchecked Sendable {}
open class CMAccelerometerData: CMLogItem, @unchecked Sendable {}
open class CMMotionManager: NSObject, @unchecked Sendable {
    open var deviceMotionUpdateInterval: TimeInterval = 0.01
    open var accelerometerUpdateInterval: TimeInterval = 0.01
    open var isDeviceMotionAvailable: Bool { false }
    open var isAccelerometerAvailable: Bool { false }
    open var isGyroAvailable: Bool { false }
    open var isDeviceMotionActive: Bool { false }
    open var deviceMotion: CMDeviceMotion? { nil }
    public override init() { super.init() }
    open func startDeviceMotionUpdates() {}
    open func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: @escaping (CMDeviceMotion?, Error?) -> Void) {}
    open func startAccelerometerUpdates(to queue: OperationQueue, withHandler handler: @escaping (CMAccelerometerData?, Error?) -> Void) {}
    open func stopDeviceMotionUpdates() {}
    open func stopAccelerometerUpdates() {}
}
open class CMPedometer: NSObject, @unchecked Sendable {
    public class func isStepCountingAvailable() -> Bool { false }
    public class func authorizationStatus() -> CMAuthorizationStatus { .notDetermined }
}
open class CMMotionActivityManager: NSObject, @unchecked Sendable {
    public class func isActivityAvailable() -> Bool { false }
}
