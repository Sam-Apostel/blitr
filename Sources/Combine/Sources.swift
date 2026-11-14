// Subjects, source publishers, ObservableObject and @Published.
import Foundation

public protocol Subject<Output, Failure>: AnyObject, Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
    func send(subscription: Subscription)
}

extension Subject where Output == Void {
    public func send() { send(()) }
}

public final class PassthroughSubject<Output, Failure: Error>: Subject {
    private var outs: [(id: Int, out: _Out<Output, Failure>)] = []
    private var nextID = 0
    private var finished: Subscribers.Completion<Failure>?
    public init() {}

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        if let finished {
            _source(subscriber) { $0.finish(finished) }
            return
        }
        _source(subscriber) { out in
            let id = nextID
            nextID += 1
            outs.append((id, out))
            out.link.onCancel.append { [weak self] in self?.outs.removeAll { $0.id == id } }
        }
    }
    public func send(_ value: Output) { for entry in outs { entry.out.send(value) } }
    public func send(completion: Subscribers.Completion<Failure>) {
        finished = completion
        let current = outs
        outs = []
        for entry in current { entry.out.finish(completion) }
    }
    public func send(subscription: Subscription) { subscription.request(.unlimited) }
}

public final class CurrentValueSubject<Output, Failure: Error>: Subject {
    private let subject = PassthroughSubject<Output, Failure>()
    private var current: Output
    public init(_ value: Output) { current = value }
    public var value: Output {
        get { current }
        set { send(newValue) }
    }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        let value = current
        let wrapper = _ReplayFirst(base: subscriber, first: value)
        subject.receive(subscriber: wrapper)
    }
    public func send(_ value: Output) {
        current = value
        subject.send(value)
    }
    public func send(completion: Subscribers.Completion<Failure>) { subject.send(completion: completion) }
    public func send(subscription: Subscription) { subscription.request(.unlimited) }
}

/// Delivers one value right after the subscription is established, then forwards everything.
private struct _ReplayFirst<S: Subscriber>: Subscriber {
    typealias Input = S.Input
    typealias Failure = S.Failure
    let base: S
    let first: S.Input
    func receive(subscription: Subscription) {
        base.receive(subscription: subscription)
        _ = base.receive(first)
    }
    func receive(_ input: S.Input) -> Subscribers.Demand { base.receive(input) }
    func receive(completion: Subscribers.Completion<S.Failure>) { base.receive(completion: completion) }
}

// MARK: - Sources

public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output
    public init(_ output: Output) { self.output = output }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        _source(subscriber) { out in out.send(output); out.finish(.finished) }
    }
}

public struct Empty<Output, Failure: Error>: Publisher {
    public let completeImmediately: Bool
    public init(completeImmediately: Bool = true) { self.completeImmediately = completeImmediately }
    public init(completeImmediately: Bool = true, outputType: Output.Type, failureType: Failure.Type) { self.completeImmediately = completeImmediately }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        _source(subscriber) { out in if completeImmediately { out.finish(.finished) } }
    }
}

public struct Fail<Output, Failure: Error>: Publisher {
    public let error: Failure
    public init(error: Failure) { self.error = error }
    public init(outputType: Output.Type, failure: Failure) { error = failure }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        _source(subscriber) { out in out.finish(.failure(error)) }
    }
}

public struct Deferred<DeferredPublisher: Publisher>: Publisher {
    public typealias Output = DeferredPublisher.Output
    public typealias Failure = DeferredPublisher.Failure
    let create: () -> DeferredPublisher
    public init(createPublisher: @escaping () -> DeferredPublisher) { create = createPublisher }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        create().receive(subscriber: subscriber)
    }
}

public final class Future<Output, Failure: Error>: Publisher {
    public typealias Promise = (Result<Output, Failure>) -> Void
    private var result: Result<Output, Failure>?
    private var waiting: [_Out<Output, Failure>] = []
    public init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
        attemptToFulfill { [weak self] result in
            guard let self, self.result == nil else { return }
            self.result = result
            let pending = self.waiting
            self.waiting = []
            for out in pending { Future.deliver(result, to: out) }
        }
    }
    private static func deliver(_ result: Result<Output, Failure>, to out: _Out<Output, Failure>) {
        switch result {
        case .success(let v): out.send(v); out.finish(.finished)
        case .failure(let e): out.finish(.failure(e))
        }
    }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        _source(subscriber) { out in
            if let result { Future.deliver(result, to: out) } else { waiting.append(out) }
        }
    }
}

extension Publishers {
    public struct Sequence<Elements: Swift.Sequence, Failure: Error>: Publisher {
        public typealias Output = Elements.Element
        public let sequence: Elements
        public init(sequence: Elements) { self.sequence = sequence }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                for element in sequence { out.send(element) }
                out.finish(.finished)
            }
        }
    }
}

extension Sequence {
    public var publisher: Publishers.Sequence<Self, Never> { Publishers.Sequence(sequence: self) }
}

extension Result {
    public var publisher: Result<Success, Failure>.Publisher { .init(self) }
    public struct Publisher: Combine.Publisher {
        public typealias Output = Success
        let result: Result<Success, Failure>
        public init(_ result: Result<Success, Failure>) { self.result = result }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Success, S.Failure == Failure {
            _source(subscriber) { out in
                switch result {
                case .success(let v): out.send(v); out.finish(.finished)
                case .failure(let e): out.finish(.failure(e))
                }
            }
        }
    }
}

// MARK: - ObservableObject / @Published

public final class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    private let subject = PassthroughSubject<Void, Never>()
    /// Called on every change of any object; the SwiftUI shim uses it to schedule another render pass.
    public nonisolated(unsafe) static var _didChange: (() -> Void)?
    public init() {}
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Void, S.Failure == Never { subject.receive(subscriber: subscriber) }
    public func send() {
        ObservableObjectPublisher._didChange?()
        subject.send()
    }
}

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher where ObjectWillChangePublisher.Failure == Never
    var objectWillChange: ObjectWillChangePublisher { get }
}

private final class _PublisherTable: @unchecked Sendable {
    struct Entry { weak var object: AnyObject?; let publisher: ObservableObjectPublisher }
    let lock = NSLock()
    var entries: [ObjectIdentifier: Entry] = [:]
    static let shared = _PublisherTable()
    func publisher(for object: AnyObject) -> ObservableObjectPublisher {
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        if let e = entries[id], e.object === object { return e.publisher }
        if entries.count > 512 { entries = entries.filter { $0.value.object != nil } }
        let p = ObservableObjectPublisher()
        entries[id] = Entry(object: object, publisher: p)
        return p
    }
}

extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    public var objectWillChange: ObservableObjectPublisher { _PublisherTable.shared.publisher(for: self) }
}

@propertyWrapper
public struct Published<Value> {
    final class Box {
        let subject: CurrentValueSubject<Value, Never>
        var keepAlive: [AnyCancellable] = []
        init(_ value: Value) { subject = CurrentValueSubject(value) }
    }
    let box: Box

    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }

    public var wrappedValue: Value {
        get { box.subject.value }
        nonmutating set { box.subject.send(newValue) }
    }

    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        let box: Box
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
            box.subject.receive(subscriber: subscriber)
        }
    }

    public var projectedValue: Published<Value>.Publisher {
        get { Publisher(box: box) }
        set {}
    }

    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value where EnclosingSelf.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { object[keyPath: storageKeyPath].box.subject.value }
        set {
            object.objectWillChange.send()
            object[keyPath: storageKeyPath].box.subject.send(newValue)
        }
    }
}

extension Publisher where Failure == Never {
    public func assign(to published: inout Published<Output>.Publisher) {
        let box = published.box
        box.keepAlive.append(sink { box.subject.send($0) })
    }
}
