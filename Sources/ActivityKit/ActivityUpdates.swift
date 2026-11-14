// The asynchronous sequences of an Activity. Nothing starts, updates or ends a Live Activity here and no
// push token is issued, so every sequence finishes without an element.
import Foundation

/// An async sequence that is already finished.
public struct _FinishedActivitySequence<Element>: AsyncSequence {
    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async -> Element? { nil }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

extension Activity {
    public typealias ActivityUpdates = _FinishedActivitySequence<Activity<Attributes>>
    public typealias PushTokenUpdates = _FinishedActivitySequence<Data>
    public typealias ActivityStateUpdates = _FinishedActivitySequence<ActivityState>
    public typealias ContentUpdates = _FinishedActivitySequence<ActivityContent<Attributes.ContentState>>
    public typealias ContentStateUpdates = _FinishedActivitySequence<Attributes.ContentState>

    /// Activities started from elsewhere (push to start, another process): none.
    public static var activityUpdates: ActivityUpdates { ActivityUpdates() }
    /// The token for starting activities by push: never issued.
    public static var pushToStartTokenUpdates: PushTokenUpdates { PushTokenUpdates() }
    public static var pushToStartToken: Data? { nil }

    public var pushTokenUpdates: PushTokenUpdates { PushTokenUpdates() }
    public var activityStateUpdates: ActivityStateUpdates { ActivityStateUpdates() }
    public var contentUpdates: ContentUpdates { ContentUpdates() }
    @available(*, deprecated, renamed: "contentUpdates")
    public var contentStateUpdates: ContentStateUpdates { ContentStateUpdates() }
}
