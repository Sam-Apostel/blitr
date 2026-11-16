import Foundation

// The hinge of a foldable (iOS 27.1, the iPhone Duo): `onHingeChange` tells a view whether the device is closed,
// partly open (bent like a book) or fully open. The state comes from the device profile's posture
// (`iphone-duo`, `iphone-duo-half-open`, `iphone-duo-open`); every other device has no hinge.

/// A foldable device's hinge.
public struct DeviceHinge: Hashable, Sendable {
    public var status: Status
    /// How far the device is open: 0 degrees closed, 180 flat.
    public var angle: Angle

    public struct Status: Hashable, Sendable {
        let raw: Int
        public static var closed: Status { Status(raw: 0) }
        public static var partiallyOpen: Status { Status(raw: 1) }
        public static var fullyOpen: Status { Status(raw: 2) }
    }

    public static func == (a: DeviceHinge, b: DeviceHinge) -> Bool { a.status == b.status && a.angle.degrees == b.angle.degrees }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(status)
        hasher.combine(angle.degrees)
    }
}

/// What `onHingeChange` reports: the hinge, or nil on a device without one.
public struct DeviceHingeContext: Equatable, Sendable {
    public var hinge: DeviceHinge?

    @MainActor static var current: DeviceHingeContext { DeviceHingeContext(hinge: _currentConfiguration().device.hinge) }
}

extension View {
    /// Calls `action` with the hinge's state. A still frame has one posture, so it is called once, when the view
    /// appears, with the same context as old and new value (as `onGeometryChange` reports its first value).
    public func onHingeChange(isEnabled: Bool = true,
                              _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void) -> some View {
        onAppear {
            guard isEnabled else { return }
            let context = DeviceHingeContext.current
            action(context, context)
        }
    }
}
