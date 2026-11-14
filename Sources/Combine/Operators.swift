// Operators. Each is a small struct so chains keep their Apple-compatible generic shape.
import Foundation

public enum Publishers {}

extension Publishers {
    public struct Map<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let transform: (Upstream.Output) -> Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber) { v, out in out.send(transform(v)) }
        }
    }

    public struct TryMap<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Error
        let upstream: Upstream
        let transform: (Upstream.Output) throws -> Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Error {
            upstream._pipe(to: subscriber, value: { v, out in
                do { out.send(try transform(v)) } catch { out.finish(.failure(error)) }
            }, completion: { c, out in
                switch c {
                case .finished: out.finish(.finished)
                case .failure(let e): out.finish(.failure(e))
                }
            })
        }
    }

    public struct MapError<Upstream: Publisher, Failure: Error>: Publisher {
        public typealias Output = Upstream.Output
        let upstream: Upstream
        let transform: (Upstream.Failure) -> Failure
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber, value: { v, out in out.send(v) }, completion: { c, out in
                switch c {
                case .finished: out.finish(.finished)
                case .failure(let e): out.finish(.failure(transform(e)))
                }
            })
        }
    }

    public struct SetFailureType<Upstream: Publisher, Failure: Error>: Publisher where Upstream.Failure == Never {
        public typealias Output = Upstream.Output
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber, value: { v, out in out.send(v) }, completion: { _, out in out.finish(.finished) })
        }
    }

    public struct Filter<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let isIncluded: (Output) -> Bool
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber) { v, out in if isIncluded(v) { out.send(v) } }
        }
    }

    public struct CompactMap<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let transform: (Upstream.Output) -> Output?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber) { v, out in if let m = transform(v) { out.send(m) } }
        }
    }

    public struct RemoveDuplicates<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let predicate: (Output, Output) -> Bool
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var last: Output?
            upstream._pipe(to: subscriber) { v, out in
                if let l = last, predicate(l, v) { return }
                last = v
                out.send(v)
            }
        }
    }

    public struct Scan<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let initial: Output
        let next: (Output, Upstream.Output) -> Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var acc = initial
            upstream._pipe(to: subscriber) { v, out in acc = next(acc, v); out.send(acc) }
        }
    }

    public struct Reduce<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let initial: Output
        let next: (Output, Upstream.Output) -> Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var acc = initial
            upstream._pipe(to: subscriber, value: { v, _ in acc = next(acc, v) }, completion: { c, out in
                if case .finished = c { out.send(acc) }
                out.finish(c)
            })
        }
    }

    public struct Collect<Upstream: Publisher>: Publisher {
        public typealias Output = [Upstream.Output]
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let count: Int?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var items: [Upstream.Output] = []
            upstream._pipe(to: subscriber, value: { v, out in
                items.append(v)
                if let count, items.count >= count { out.send(items); items = [] }
            }, completion: { c, out in
                if case .finished = c, count == nil || !items.isEmpty { out.send(items) }
                out.finish(c)
            })
        }
    }

    public struct Count<Upstream: Publisher>: Publisher {
        public typealias Output = Int
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Failure {
            var n = 0
            upstream._pipe(to: subscriber, value: { _, _ in n += 1 }, completion: { c, out in
                if case .finished = c { out.send(n) }
                out.finish(c)
            })
        }
    }

    public struct Drop<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let count: Int
        let dropWhile: ((Output) -> Bool)?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var seen = 0
            var dropping = true
            upstream._pipe(to: subscriber) { v, out in
                if let dropWhile {
                    if dropping, dropWhile(v) { return }
                    dropping = false
                } else if seen < count { seen += 1; return }
                out.send(v)
            }
        }
    }

    public struct Prefix<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let maxLength: Int
        let prefixWhile: ((Output) -> Bool)?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var seen = 0
            upstream._pipe(to: subscriber) { v, out in
                if let prefixWhile {
                    if prefixWhile(v) { out.send(v) } else { out.finish(.finished) }
                } else if seen < maxLength {
                    seen += 1
                    out.send(v)
                    if seen == maxLength { out.finish(.finished) }
                }
            }
            if prefixWhile == nil, maxLength == 0 { }
        }
    }

    public struct Last<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var last: Output?
            upstream._pipe(to: subscriber, value: { v, _ in last = v }, completion: { c, out in
                if case .finished = c, let last { out.send(last) }
                out.finish(c)
            })
        }
    }

    public struct IgnoreOutput<Upstream: Publisher>: Publisher {
        public typealias Output = Never
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Never, S.Failure == Failure {
            upstream._pipe(to: subscriber, value: { _, _ in })
        }
    }

    public struct ReplaceEmpty<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let output: Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var any = false
            upstream._pipe(to: subscriber, value: { v, out in any = true; out.send(v) }, completion: { c, out in
                if case .finished = c, !any { out.send(output) }
                out.finish(c)
            })
        }
    }

    public struct ReplaceError<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Never
        let upstream: Upstream
        let output: Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
            upstream._pipe(to: subscriber, value: { v, out in out.send(v) }, completion: { c, out in
                if case .failure = c { out.send(output) }
                out.finish(.finished)
            })
        }
    }

    public struct Catch<Upstream: Publisher, NewPublisher: Publisher>: Publisher where Upstream.Output == NewPublisher.Output {
        public typealias Output = Upstream.Output
        public typealias Failure = NewPublisher.Failure
        let upstream: Upstream
        let handler: (Upstream.Failure) -> NewPublisher
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber, value: { v, out in out.send(v) }, completion: { c, out in
                switch c {
                case .finished: out.finish(.finished)
                case .failure(let e): handler(e)._forward(to: out)
                }
            })
        }
    }

    public struct Retry<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let retries: Int
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            var remaining = retries
            func attempt(_ out: _Out<Output, Failure>) {
                upstream._listen(out, failure: { e in
                    if remaining > 0 { remaining -= 1; attempt(out) } else { out.finish(.failure(e)) }
                }, value: out.send, finished: { out.finish(.finished) })
            }
            _source(subscriber) { attempt($0) }
        }
    }

    public struct HandleEvents<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let onOutput: ((Output) -> Void)?
        let onCompletion: ((Subscribers.Completion<Failure>) -> Void)?
        let onCancel: (() -> Void)?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream._pipe(to: subscriber, value: { v, out in onOutput?(v); out.send(v) }, completion: { c, out in
                onCompletion?(c)
                out.finish(c)
            })
        }
    }

    /// Operators whose only job is scheduling (debounce, throttle, receive(on:), delay, ...) pass values through.
    public struct Passthrough<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream.receive(subscriber: subscriber)
        }
    }

    public struct Decode<Upstream: Publisher, Item: Decodable, Coder: TopLevelDecoder>: Publisher where Upstream.Output == Coder.Input {
        public typealias Output = Item
        public typealias Failure = Error
        let upstream: Upstream
        let decoder: Coder
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Item, S.Failure == Error {
            upstream._pipe(to: subscriber, value: { v, out in
                do { out.send(try decoder.decode(Item.self, from: v)) } catch { out.finish(.failure(error)) }
            }, completion: { c, out in
                switch c {
                case .finished: out.finish(.finished)
                case .failure(let e): out.finish(.failure(e))
                }
            })
        }
    }

    public struct Concatenate<Prefix: Publisher, Suffix: Publisher>: Publisher where Prefix.Output == Suffix.Output, Prefix.Failure == Suffix.Failure {
        public typealias Output = Suffix.Output
        public typealias Failure = Suffix.Failure
        let prefix: Prefix
        let suffix: Suffix
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            prefix._pipe(to: subscriber, value: { v, out in out.send(v) }, completion: { c, out in
                switch c {
                case .finished: suffix._forward(to: out)
                case .failure: out.finish(c)
                }
            })
        }
    }

    public struct Merge<A: Publisher, B: Publisher>: Publisher where A.Output == B.Output, A.Failure == B.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        let a: A
        let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var remaining = 2
                let finished = { remaining -= 1; if remaining == 0 { out.finish(.finished) } }
                a._listen(out, failure: { out.finish(.failure($0)) }, value: out.send, finished: finished)
                b._listen(out, failure: { out.finish(.failure($0)) }, value: out.send, finished: finished)
            }
        }
    }

    public struct FlatMap<NewPublisher: Publisher, Upstream: Publisher>: Publisher where NewPublisher.Failure == Upstream.Failure {
        public typealias Output = NewPublisher.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        let transform: (Upstream.Output) -> NewPublisher
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var active = 0
                var upstreamDone = false
                upstream._listen(out, failure: { out.finish(.failure($0)) }, value: { v in
                    active += 1
                    transform(v)._listen(out, failure: { out.finish(.failure($0)) }, value: out.send, finished: {
                        active -= 1
                        if upstreamDone && active == 0 { out.finish(.finished) }
                    })
                }, finished: {
                    upstreamDone = true
                    if active == 0 { out.finish(.finished) }
                })
            }
        }
    }

    public struct SwitchToLatest<P: Publisher, Upstream: Publisher>: Publisher where P == Upstream.Output, P.Failure == Upstream.Failure {
        public typealias Output = P.Output
        public typealias Failure = P.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var generation = 0
                var inner: [() -> Void] = []
                var upstreamDone = false, innerActive = false
                upstream._listen(out, failure: { out.finish(.failure($0)) }, value: { p in
                    inner.forEach { $0() }
                    inner = []
                    generation += 1
                    let mine = generation
                    innerActive = true
                    let sink = Subscribers.Sink<P.Output, P.Failure>(receiveCompletion: { c in
                        guard mine == generation else { return }
                        switch c {
                        case .failure(let e): out.finish(.failure(e))
                        case .finished:
                            innerActive = false
                            if upstreamDone { out.finish(.finished) }
                        }
                    }, receiveValue: { v in if mine == generation { out.send(v) } })
                    inner.append { sink.cancel() }
                    out.link.onCancel.append { sink.cancel() }
                    p.subscribe(sink)
                }, finished: {
                    upstreamDone = true
                    if !innerActive { out.finish(.finished) }
                })
            }
        }
    }

    public struct Autoconnect<Upstream: ConnectablePublisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream.receive(subscriber: subscriber)
            _ = upstream.connect()
        }
    }

    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        let a: A, b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var la: A.Output?, lb: B.Output?
                var remaining = 2
                let finished = { remaining -= 1; if remaining == 0 { out.finish(.finished) } }
                a._listen(out, failure: { out.finish(.failure($0)) }, value: { la = $0; if let x = la, let y = lb { out.send((x, y)) } }, finished: finished)
                b._listen(out, failure: { out.finish(.failure($0)) }, value: { lb = $0; if let x = la, let y = lb { out.send((x, y)) } }, finished: finished)
            }
        }
    }

    public struct CombineLatest3<A: Publisher, B: Publisher, C: Publisher>: Publisher where A.Failure == B.Failure, B.Failure == C.Failure {
        public typealias Output = (A.Output, B.Output, C.Output)
        public typealias Failure = A.Failure
        let a: A, b: B, c: C
        public init(_ a: A, _ b: B, _ c: C) { self.a = a; self.b = b; self.c = c }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var la: A.Output?, lb: B.Output?, lc: C.Output?
                var remaining = 3
                let finished = { remaining -= 1; if remaining == 0 { out.finish(.finished) } }
                func emit() { if let x = la, let y = lb, let z = lc { out.send((x, y, z)) } }
                a._listen(out, failure: { out.finish(.failure($0)) }, value: { la = $0; emit() }, finished: finished)
                b._listen(out, failure: { out.finish(.failure($0)) }, value: { lb = $0; emit() }, finished: finished)
                c._listen(out, failure: { out.finish(.failure($0)) }, value: { lc = $0; emit() }, finished: finished)
            }
        }
    }

    public struct CombineLatest4<A: Publisher, B: Publisher, C: Publisher, D: Publisher>: Publisher
    where A.Failure == B.Failure, B.Failure == C.Failure, C.Failure == D.Failure {
        public typealias Output = (A.Output, B.Output, C.Output, D.Output)
        public typealias Failure = A.Failure
        let a: A, b: B, c: C, d: D
        public init(_ a: A, _ b: B, _ c: C, _ d: D) { self.a = a; self.b = b; self.c = c; self.d = d }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var la: A.Output?, lb: B.Output?, lc: C.Output?, ld: D.Output?
                var remaining = 4
                let finished = { remaining -= 1; if remaining == 0 { out.finish(.finished) } }
                func emit() { if let x = la, let y = lb, let z = lc, let w = ld { out.send((x, y, z, w)) } }
                a._listen(out, failure: { out.finish(.failure($0)) }, value: { la = $0; emit() }, finished: finished)
                b._listen(out, failure: { out.finish(.failure($0)) }, value: { lb = $0; emit() }, finished: finished)
                c._listen(out, failure: { out.finish(.failure($0)) }, value: { lc = $0; emit() }, finished: finished)
                d._listen(out, failure: { out.finish(.failure($0)) }, value: { ld = $0; emit() }, finished: finished)
            }
        }
    }

    public struct Zip<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        let a: A, b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            _source(subscriber) { out in
                var qa: [A.Output] = [], qb: [B.Output] = []
                var remaining = 2
                let finished = { remaining -= 1; if remaining == 0 { out.finish(.finished) } }
                func drain() { while !qa.isEmpty, !qb.isEmpty { out.send((qa.removeFirst(), qb.removeFirst())) } }
                a._listen(out, failure: { out.finish(.failure($0)) }, value: { qa.append($0); drain() }, finished: finished)
                b._listen(out, failure: { out.finish(.failure($0)) }, value: { qb.append($0); drain() }, finished: finished)
            }
        }
    }
}

// MARK: - Publisher operators

extension Publisher {
    public func map<T>(_ transform: @escaping (Output) -> T) -> Publishers.Map<Self, T> { .init(upstream: self, transform: transform) }
    public func map<T>(_ keyPath: KeyPath<Output, T>) -> Publishers.Map<Self, T> { .init(upstream: self, transform: { $0[keyPath: keyPath] }) }
    public func tryMap<T>(_ transform: @escaping (Output) throws -> T) -> Publishers.TryMap<Self, T> { .init(upstream: self, transform: transform) }
    public func mapError<E: Error>(_ transform: @escaping (Failure) -> E) -> Publishers.MapError<Self, E> { .init(upstream: self, transform: transform) }
    public func filter(_ isIncluded: @escaping (Output) -> Bool) -> Publishers.Filter<Self> { .init(upstream: self, isIncluded: isIncluded) }
    public func compactMap<T>(_ transform: @escaping (Output) -> T?) -> Publishers.CompactMap<Self, T> { .init(upstream: self, transform: transform) }
    public func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> Publishers.RemoveDuplicates<Self> { .init(upstream: self, predicate: predicate) }
    public func scan<T>(_ initial: T, _ next: @escaping (T, Output) -> T) -> Publishers.Scan<Self, T> { .init(upstream: self, initial: initial, next: next) }
    public func reduce<T>(_ initial: T, _ next: @escaping (T, Output) -> T) -> Publishers.Reduce<Self, T> { .init(upstream: self, initial: initial, next: next) }
    public func collect() -> Publishers.Collect<Self> { .init(upstream: self, count: nil) }
    public func collect(_ count: Int) -> Publishers.Collect<Self> { .init(upstream: self, count: count) }
    public func count() -> Publishers.Count<Self> { .init(upstream: self) }
    public func dropFirst(_ count: Int = 1) -> Publishers.Drop<Self> { .init(upstream: self, count: count, dropWhile: nil) }
    public func drop(while predicate: @escaping (Output) -> Bool) -> Publishers.Drop<Self> { .init(upstream: self, count: 0, dropWhile: predicate) }
    public func prefix(_ maxLength: Int) -> Publishers.Prefix<Self> { .init(upstream: self, maxLength: maxLength, prefixWhile: nil) }
    public func prefix(while predicate: @escaping (Output) -> Bool) -> Publishers.Prefix<Self> { .init(upstream: self, maxLength: 0, prefixWhile: predicate) }
    public func first() -> Publishers.Prefix<Self> { prefix(1) }
    public func first(where predicate: @escaping (Output) -> Bool) -> Publishers.Prefix<Publishers.Filter<Self>> { filter(predicate).prefix(1) }
    public func last() -> Publishers.Last<Self> { .init(upstream: self) }
    public func ignoreOutput() -> Publishers.IgnoreOutput<Self> { .init(upstream: self) }
    public func replaceEmpty(with output: Output) -> Publishers.ReplaceEmpty<Self> { .init(upstream: self, output: output) }
    public func replaceError(with output: Output) -> Publishers.ReplaceError<Self> { .init(upstream: self, output: output) }
    public func `catch`<P: Publisher>(_ handler: @escaping (Failure) -> P) -> Publishers.Catch<Self, P> where P.Output == Output { .init(upstream: self, handler: handler) }
    public func retry(_ retries: Int) -> Publishers.Retry<Self> { .init(upstream: self, retries: retries) }
    public func handleEvents(receiveSubscription: ((Subscription) -> Void)? = nil, receiveOutput: ((Output) -> Void)? = nil,
                             receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)? = nil, receiveCancel: (() -> Void)? = nil,
                             receiveRequest: ((Subscribers.Demand) -> Void)? = nil) -> Publishers.HandleEvents<Self> {
        .init(upstream: self, onOutput: receiveOutput, onCompletion: receiveCompletion, onCancel: receiveCancel)
    }
    public func print(_ prefix: String = "", to stream: (any TextOutputStream)? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func share() -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func breakpointOnError() -> Publishers.Passthrough<Self> { .init(upstream: self) }

    public func prepend(_ elements: Output...) -> Publishers.Concatenate<Publishers.Sequence<[Output], Failure>, Self> { .init(prefix: .init(sequence: elements), suffix: self) }
    public func prepend<S: Sequence>(_ elements: S) -> Publishers.Concatenate<Publishers.Sequence<S, Failure>, Self> where S.Element == Output { .init(prefix: .init(sequence: elements), suffix: self) }
    public func prepend<P: Publisher>(_ publisher: P) -> Publishers.Concatenate<P, Self> where P.Output == Output, P.Failure == Failure { .init(prefix: publisher, suffix: self) }
    public func append(_ elements: Output...) -> Publishers.Concatenate<Self, Publishers.Sequence<[Output], Failure>> { .init(prefix: self, suffix: .init(sequence: elements)) }
    public func append<S: Sequence>(_ elements: S) -> Publishers.Concatenate<Self, Publishers.Sequence<S, Failure>> where S.Element == Output { .init(prefix: self, suffix: .init(sequence: elements)) }
    public func append<P: Publisher>(_ publisher: P) -> Publishers.Concatenate<Self, P> where P.Output == Output, P.Failure == Failure { .init(prefix: self, suffix: publisher) }

    public func merge<P: Publisher>(with other: P) -> Publishers.Merge<Self, P> where P.Output == Output, P.Failure == Failure { .init(self, other) }
    public func flatMap<P: Publisher>(maxPublishers: Subscribers.Demand = .unlimited, _ transform: @escaping (Output) -> P) -> Publishers.FlatMap<P, Self> where P.Failure == Failure {
        .init(upstream: self, transform: transform)
    }
    public func combineLatest<P: Publisher>(_ other: P) -> Publishers.CombineLatest<Self, P> where P.Failure == Failure { .init(self, other) }
    public func combineLatest<P: Publisher, T>(_ other: P, _ transform: @escaping (Output, P.Output) -> T) -> Publishers.Map<Publishers.CombineLatest<Self, P>, T> where P.Failure == Failure {
        combineLatest(other).map { transform($0.0, $0.1) }
    }
    public func combineLatest<P: Publisher, Q: Publisher>(_ p: P, _ q: Q) -> Publishers.CombineLatest3<Self, P, Q> where P.Failure == Failure, Q.Failure == Failure { .init(self, p, q) }
    public func combineLatest<P: Publisher, Q: Publisher, R: Publisher>(_ p: P, _ q: Q, _ r: R) -> Publishers.CombineLatest4<Self, P, Q, R>
    where P.Failure == Failure, Q.Failure == Failure, R.Failure == Failure { .init(self, p, q, r) }
    public func zip<P: Publisher>(_ other: P) -> Publishers.Zip<Self, P> where P.Failure == Failure { .init(self, other) }

    public func decode<Item: Decodable, Coder: TopLevelDecoder>(type: Item.Type, decoder: Coder) -> Publishers.Decode<Self, Item, Coder> where Output == Coder.Input {
        .init(upstream: self, decoder: decoder)
    }

    // Scheduling operators: synchronous delivery means they are identity.
    public func receive<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func subscribe<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func debounce<S: Scheduler>(for dueTime: S.SchedulerTimeType.Stride, scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func throttle<S: Scheduler>(for interval: S.SchedulerTimeType.Stride, scheduler: S, latest: Bool) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func delay<S: Scheduler>(for interval: S.SchedulerTimeType.Stride, tolerance: S.SchedulerTimeType.Stride? = nil, scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
    public func timeout<S: Scheduler>(_ interval: S.SchedulerTimeType.Stride, scheduler: S, options: S.SchedulerOptions? = nil, customError: (() -> Failure)? = nil) -> Publishers.Passthrough<Self> { .init(upstream: self) }
}

extension Publisher where Output: Equatable {
    public func removeDuplicates() -> Publishers.RemoveDuplicates<Self> { removeDuplicates(by: { $0 == $1 }) }
}

extension Publisher where Failure == Never {
    public func setFailureType<E: Error>(to failureType: E.Type) -> Publishers.SetFailureType<Self, E> { .init(upstream: self) }
}

extension Publisher where Output: Publisher, Output.Failure == Failure {
    public func switchToLatest() -> Publishers.SwitchToLatest<Output, Self> { .init(upstream: self) }
}

extension Publisher where Output == Void {
    public func map<T>(_ value: @autoclosure @escaping () -> T) -> Publishers.Map<Self, T> { .init(upstream: self, transform: { _ in value() }) }
}

// MARK: - Connectable, schedulers, coders

public protocol ConnectablePublisher<Output, Failure>: Publisher {
    associatedtype Connection: Cancellable
    func connect() -> Connection
}

extension ConnectablePublisher {
    public func autoconnect() -> Publishers.Autoconnect<Self> { .init(upstream: self) }
}

public protocol TopLevelDecoder {
    associatedtype Input
    func decode<T: Decodable>(_ type: T.Type, from: Input) throws -> T
}
extension JSONDecoder: TopLevelDecoder { public typealias Input = Data }
extension PropertyListDecoder: TopLevelDecoder { public typealias Input = Data }

public protocol SchedulerTimeIntervalConvertible {
    static func seconds(_ s: Int) -> Self
    static func seconds(_ s: Double) -> Self
    static func milliseconds(_ ms: Int) -> Self
    static func microseconds(_ us: Int) -> Self
    static func nanoseconds(_ ns: Int) -> Self
}

public protocol Scheduler {
    associatedtype SchedulerTimeType: Strideable where SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
    associatedtype SchedulerOptions
    var now: SchedulerTimeType { get }
    var minimumTolerance: SchedulerTimeType.Stride { get }
    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                  options: SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable
}

public struct _SchedulerOptions {}

public struct _SchedulerTime: Strideable, Hashable {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func distance(to other: _SchedulerTime) -> _SchedulerStride { _SchedulerStride(seconds: other.seconds - seconds) }
    public func advanced(by n: _SchedulerStride) -> _SchedulerTime { _SchedulerTime(seconds: seconds + n.seconds) }
    public typealias Stride = _SchedulerStride
}

public struct _SchedulerStride: SignedNumeric, Comparable, Hashable, ExpressibleByFloatLiteral, SchedulerTimeIntervalConvertible {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public init(floatLiteral value: Double) { seconds = value }
    public init(integerLiteral value: Int) { seconds = Double(value) }
    public init?<T: BinaryInteger>(exactly source: T) { seconds = Double(source) }
    public var magnitude: _SchedulerStride { _SchedulerStride(seconds: abs(seconds)) }
    public static func < (a: Self, b: Self) -> Bool { a.seconds < b.seconds }
    public static func + (a: Self, b: Self) -> Self { .init(seconds: a.seconds + b.seconds) }
    public static func - (a: Self, b: Self) -> Self { .init(seconds: a.seconds - b.seconds) }
    public static func * (a: Self, b: Self) -> Self { .init(seconds: a.seconds * b.seconds) }
    public static func += (a: inout Self, b: Self) { a.seconds += b.seconds }
    public static func -= (a: inout Self, b: Self) { a.seconds -= b.seconds }
    public static func *= (a: inout Self, b: Self) { a.seconds *= b.seconds }
    public static func seconds(_ s: Int) -> Self { .init(seconds: Double(s)) }
    public static func seconds(_ s: Double) -> Self { .init(seconds: s) }
    public static func milliseconds(_ ms: Int) -> Self { .init(seconds: Double(ms) / 1e3) }
    public static func microseconds(_ us: Int) -> Self { .init(seconds: Double(us) / 1e6) }
    public static func nanoseconds(_ ns: Int) -> Self { .init(seconds: Double(ns) / 1e9) }
}

extension DispatchQueue: Scheduler {
    public typealias SchedulerTimeType = _SchedulerTime
    public typealias SchedulerOptions = _SchedulerOptions
    public var now: _SchedulerTime { _SchedulerTime(seconds: Date().timeIntervalSince1970) }
    public var minimumTolerance: _SchedulerStride { .seconds(0) }
    public func schedule(options: _SchedulerOptions?, _ action: @escaping () -> Void) { async(execute: action) }
    public func schedule(after date: _SchedulerTime, tolerance: _SchedulerStride, options: _SchedulerOptions?, _ action: @escaping () -> Void) {
        asyncAfter(deadline: .now() + max(0, date.seconds - Date().timeIntervalSince1970), execute: action)
    }
    public func schedule(after date: _SchedulerTime, interval: _SchedulerStride, tolerance: _SchedulerStride,
                         options: _SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable {
        schedule(after: date, tolerance: tolerance, options: options, action)
        return AnyCancellable {}
    }
}

extension RunLoop: Scheduler {
    public typealias SchedulerTimeType = _SchedulerTime
    public typealias SchedulerOptions = _SchedulerOptions
    public var now: _SchedulerTime { _SchedulerTime(seconds: Date().timeIntervalSince1970) }
    public var minimumTolerance: _SchedulerStride { .seconds(0) }
    public func schedule(options: _SchedulerOptions?, _ action: @escaping () -> Void) { perform(action) }
    public func schedule(after date: _SchedulerTime, tolerance: _SchedulerStride, options: _SchedulerOptions?, _ action: @escaping () -> Void) { perform(action) }
    public func schedule(after date: _SchedulerTime, interval: _SchedulerStride, tolerance: _SchedulerStride,
                         options: _SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable { AnyCancellable {} }
}

extension OperationQueue: Scheduler {
    public typealias SchedulerTimeType = _SchedulerTime
    public typealias SchedulerOptions = _SchedulerOptions
    public var now: _SchedulerTime { _SchedulerTime(seconds: Date().timeIntervalSince1970) }
    public var minimumTolerance: _SchedulerStride { .seconds(0) }
    public func schedule(options: _SchedulerOptions?, _ action: @escaping () -> Void) { addOperation(action) }
    public func schedule(after date: _SchedulerTime, tolerance: _SchedulerStride, options: _SchedulerOptions?, _ action: @escaping () -> Void) { addOperation(action) }
    public func schedule(after date: _SchedulerTime, interval: _SchedulerStride, tolerance: _SchedulerStride,
                         options: _SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable { AnyCancellable {} }
}

public struct ImmediateScheduler: Scheduler {
    public typealias SchedulerTimeType = _SchedulerTime
    public typealias SchedulerOptions = _SchedulerOptions
    public static let shared = ImmediateScheduler()
    public var now: _SchedulerTime { _SchedulerTime(seconds: Date().timeIntervalSince1970) }
    public var minimumTolerance: _SchedulerStride { .seconds(0) }
    public func schedule(options: _SchedulerOptions?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: _SchedulerTime, tolerance: _SchedulerStride, options: _SchedulerOptions?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: _SchedulerTime, interval: _SchedulerStride, tolerance: _SchedulerStride,
                         options: _SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable { action(); return AnyCancellable {} }
}

// MARK: - Foundation glue

extension Timer {
    /// A timer publisher that never fires: a screenshot shows the state before the first tick.
    public final class TimerPublisher: ConnectablePublisher {
        public typealias Output = Date
        public typealias Failure = Never
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Date, S.Failure == Never { _source(subscriber) { _ in } }
        public func connect() -> AnyCancellable { AnyCancellable {} }
    }
    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop,
                               in mode: RunLoop.Mode, options: _SchedulerOptions? = nil) -> TimerPublisher { TimerPublisher() }
}

extension NotificationCenter {
    public struct Publisher: Combine.Publisher {
        public typealias Output = Notification
        public typealias Failure = Never
        let center: NotificationCenter
        let name: Notification.Name
        let object: AnyObject?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Notification, S.Failure == Never {
            _source(subscriber) { out in
                let token = center.addObserver(forName: name, object: object, queue: nil) { out.send($0) }
                out.link.onCancel.append { [center] in center.removeObserver(token) }
            }
        }
    }
    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> Publisher {
        Publisher(center: self, name: name, object: object)
    }
}

#if canImport(FoundationNetworking)
extension URLSession {
    /// Network access is unavailable while rendering, so this publisher never emits.
    public struct DataTaskPublisher: Publisher {
        public typealias Output = (data: Data, response: URLResponse)
        public typealias Failure = URLError
        public let request: URLRequest
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == URLError { _source(subscriber) { _ in } }
    }
    public func dataTaskPublisher(for url: URL) -> DataTaskPublisher { DataTaskPublisher(request: URLRequest(url: url)) }
    public func dataTaskPublisher(for request: URLRequest) -> DataTaskPublisher { DataTaskPublisher(request: request) }
}
#endif
