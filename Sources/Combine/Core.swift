// A compact reimplementation of the Combine API surface for Linux.
// Delivery is synchronous: schedulers are accepted but never defer work, which is what a
// single-frame renderer wants (the state reached "eventually" is the state shown).
import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

public protocol Cancellable {
    func cancel()
}

extension Cancellable {
    public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable {
        collection.append((self as? AnyCancellable) ?? AnyCancellable(self))
    }
    public func store(in set: inout Set<AnyCancellable>) {
        set.insert((self as? AnyCancellable) ?? AnyCancellable(self))
    }
}

public final class AnyCancellable: Cancellable, Hashable {
    private var closure: (() -> Void)?
    public init(_ cancel: @escaping () -> Void) { closure = cancel }
    public init<C: Cancellable>(_ canceller: C) { closure = canceller.cancel }
    public func cancel() {
        let c = closure
        closure = nil
        c?()
    }
    deinit { cancel() }
    public static func == (a: AnyCancellable, b: AnyCancellable) -> Bool { a === b }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

public protocol Subscription: Cancellable {
    func request(_ demand: Subscribers.Demand)
}

public protocol Subscriber<Input, Failure> {
    associatedtype Input
    associatedtype Failure: Error
    func receive(subscription: Subscription)
    func receive(_ input: Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Failure>)
}

public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure
}

extension Publisher {
    public func subscribe<S: Subscriber>(_ subscriber: S) where S.Input == Output, S.Failure == Failure {
        receive(subscriber: subscriber)
    }
    public func subscribe<S: Subject>(_ subject: S) -> AnyCancellable where S.Output == Output, S.Failure == Failure {
        sink(receiveCompletion: { subject.send(completion: $0) }, receiveValue: { subject.send($0) })
    }
}

public enum Subscribers {
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }

    public struct Demand: Equatable, Hashable, Comparable, CustomStringConvertible {
        let raw: Int
        public static let unlimited = Demand(raw: .max)
        public static let none = Demand(raw: 0)
        public static func max(_ value: Int) -> Demand { Demand(raw: Swift.max(0, value)) }
        public var max: Int? { raw == .max ? nil : raw }
        public var description: String { raw == .max ? "unlimited" : "max(\(raw))" }
        public static func < (a: Demand, b: Demand) -> Bool { a.raw < b.raw }
        public static func + (a: Demand, b: Demand) -> Demand { a.raw == .max || b.raw == .max ? .unlimited : Demand(raw: a.raw + b.raw) }
        public static func + (a: Demand, b: Int) -> Demand { a + .max(b) }
        public static func - (a: Demand, b: Demand) -> Demand { a.raw == .max ? .unlimited : Demand(raw: Swift.max(0, a.raw - b.raw)) }
        public static func - (a: Demand, b: Int) -> Demand { a - .max(b) }
    }

    public final class Sink<Input, Failure: Error>: Subscriber, Cancellable {
        private var onValue: ((Input) -> Void)?
        private var onCompletion: ((Completion<Failure>) -> Void)?
        private var subscription: Subscription?
        public init(receiveCompletion: @escaping (Completion<Failure>) -> Void, receiveValue: @escaping (Input) -> Void) {
            onValue = receiveValue
            onCompletion = receiveCompletion
        }
        public func receive(subscription: Subscription) {
            self.subscription = subscription
            subscription.request(.unlimited)
        }
        public func receive(_ input: Input) -> Demand {
            onValue?(input)
            return .none
        }
        public func receive(completion: Completion<Failure>) {
            let c = onCompletion
            clear()
            c?(completion)
        }
        public func cancel() {
            let s = subscription
            clear()
            s?.cancel()
        }
        private func clear() { onValue = nil; onCompletion = nil; subscription = nil }
    }
}

extension Subscribers.Completion: Equatable where Failure: Equatable {}
extension Subscribers.Completion: Hashable where Failure: Hashable {}
extension Subscribers.Completion: Sendable where Failure: Sendable {}

// MARK: - Plumbing shared by every publisher

/// The subscription handed to a downstream subscriber.
final class _Link: Subscription {
    var done = false
    var onCancel: [() -> Void] = []
    func request(_ demand: Subscribers.Demand) {}
    func cancel() {
        done = true
        let actions = onCancel
        onCancel = []
        actions.forEach { $0() }
    }
}

/// The downstream side of a publisher: send values, finish once.
struct _Out<Value, Failure: Error> {
    let link: _Link
    let send: (Value) -> Void
    let finish: (Subscribers.Completion<Failure>) -> Void
}

func _source<S: Subscriber>(_ subscriber: S, _ body: (_Out<S.Input, S.Failure>) -> Void) {
    let link = _Link()
    let out = _Out<S.Input, S.Failure>(
        link: link,
        send: { v in if !link.done { _ = subscriber.receive(v) } },
        finish: { c in
            if !link.done {
                link.cancel()
                subscriber.receive(completion: c)
            }
        })
    subscriber.receive(subscription: link)
    body(out)
}

extension Publisher {
    /// Subscribes with closures; `out.link` cancels the subscription when the downstream does.
    func _listen<V, F: Error>(_ out: _Out<V, F>, failure: @escaping (Failure) -> Void,
                              value: @escaping (Output) -> Void, finished: @escaping () -> Void) {
        let sink = Subscribers.Sink<Output, Failure>(receiveCompletion: { c in
            switch c {
            case .finished: finished()
            case .failure(let e): failure(e)
            }
        }, receiveValue: value)
        out.link.onCancel.append { sink.cancel() }
        subscribe(sink)
    }

    /// Subscribes downstream with custom value handling and completion forwarding.
    func _pipe<S: Subscriber>(to down: S, value: @escaping (Output, _Out<S.Input, S.Failure>) -> Void,
                              completion: @escaping (Subscribers.Completion<Failure>, _Out<S.Input, S.Failure>) -> Void) {
        _source(down) { out in
            _listen(out, failure: { completion(.failure($0), out) }, value: { value($0, out) }, finished: { completion(.finished, out) })
        }
    }

    func _pipe<S: Subscriber>(to down: S, value: @escaping (Output, _Out<S.Input, S.Failure>) -> Void) where S.Failure == Failure {
        _pipe(to: down, value: value, completion: { c, out in out.finish(c) })
    }

    /// Sends everything this publisher produces to `out`.
    func _forward(to out: _Out<Output, Failure>) {
        _listen(out, failure: { out.finish(.failure($0)) }, value: out.send, finished: { out.finish(.finished) })
    }
}

// MARK: - Type erasure

class _AnyPublisherBase<Output, Failure: Error> {
    func subscribe<S: Subscriber>(_ s: S) where S.Input == Output, S.Failure == Failure { fatalError() }
}
final class _AnyPublisherBox<P: Publisher>: _AnyPublisherBase<P.Output, P.Failure> {
    let base: P
    init(_ base: P) { self.base = base }
    override func subscribe<S: Subscriber>(_ s: S) where S.Input == P.Output, S.Failure == P.Failure { base.receive(subscriber: s) }
}

public struct AnyPublisher<Output, Failure: Error>: Publisher {
    let box: _AnyPublisherBase<Output, Failure>
    public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        box = _AnyPublisherBox(publisher)
    }
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure { box.subscribe(subscriber) }
}

extension Publisher {
    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher(self) }
}

// MARK: - Terminal operators

extension Publisher {
    public func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                     receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let sink = Subscribers.Sink<Output, Failure>(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
        subscribe(sink)
        return AnyCancellable(sink)
    }
}

extension Publisher where Failure == Never {
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
    }
    public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Output>, on object: Root) -> AnyCancellable {
        sink(receiveValue: { object[keyPath: keyPath] = $0 })
    }
}
