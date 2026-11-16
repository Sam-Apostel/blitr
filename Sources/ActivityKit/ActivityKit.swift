// A shim of Apple's ActivityKit. Live Activities cannot be started here: `Activity.request`
// throws and `Activity.activities` is empty. Their UI is rendered from WidgetKit's
// `ActivityConfiguration` through `#Preview(_:as:using:)` (see docs/WIDGETS.md).

@_exported import Foundation
import BlitrFoundation

public protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Decodable, Encodable, Hashable
}

public struct ActivityContent<State: Decodable & Encodable & Hashable>: Equatable, Hashable {
    public var state: State
    public var staleDate: Date?
    public var relevanceScore: Double
    public init(state: State, staleDate: Date?, relevanceScore: Double = 0) {
        self.state = state
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

public enum ActivityState: Equatable, Hashable, Sendable {
    case active, ended, dismissed, stale, pending
}

public enum ActivityAuthorizationError: Error, Equatable, Sendable {
    case attributesTooLarge, denied, globalMaximumExceeded, malformedActivityIdentifier, missingProcessIdentifier
    case persistenceFailure, reconnectNotPermitted, targetMaximumExceeded, unsupported, unsupportedTarget, visibility
    case unentitled
}

public struct ActivityAuthorizationInfo {
    public init() {}
    public var areActivitiesEnabled: Bool { false }
    public var frequentPushesEnabled: Bool { false }
}

public struct ActivityUIDismissalPolicy: Equatable, Sendable {
    let kind: Int
    let date: Date?
    public static let `default` = ActivityUIDismissalPolicy(kind: 0, date: nil)
    public static let immediate = ActivityUIDismissalPolicy(kind: 1, date: nil)
    public static func after(_ date: Date) -> ActivityUIDismissalPolicy { ActivityUIDismissalPolicy(kind: 2, date: date) }
}

public struct PushType: Equatable, Sendable {
    let name: String
    public static let token = PushType(name: "token")
    public static func channel(_ channelID: String) -> PushType { PushType(name: "channel:" + channelID) }
}

public struct AlertConfiguration: Sendable {
    public struct AlertSound: Sendable {
        public static let `default` = AlertSound()
        public static func named(_ name: String) -> AlertSound { AlertSound() }
    }
    public init(title: LocalizedStringResource, body: LocalizedStringResource, sound: AlertSound) {}
}

public final class Activity<Attributes: ActivityAttributes>: Identifiable {
    public let id: String
    public let attributes: Attributes
    public private(set) var content: ActivityContent<Attributes.ContentState>
    public private(set) var activityState: ActivityState = .active
    public var pushToken: Data? { nil }

    init(attributes: Attributes, content: ActivityContent<Attributes.ContentState>) {
        id = UUID().uuidString
        self.attributes = attributes
        self.content = content
    }

    /// There is no system to host a Live Activity here.
    public static var activities: [Activity<Attributes>] { [] }

    public static func request(attributes: Attributes, content: ActivityContent<Attributes.ContentState>,
                               pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    public func update(_ content: ActivityContent<Attributes.ContentState>) async { self.content = content }
    public func update(_ content: ActivityContent<Attributes.ContentState>, alertConfiguration: AlertConfiguration?) async { self.content = content }
    public func end(_ content: ActivityContent<Attributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        if let content { self.content = content }
        activityState = .ended
    }
}
