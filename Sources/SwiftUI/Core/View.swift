// The View protocol, the result builder, and the structural view types.

@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError() }
}

extension View where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive view and has no body") }
}

/// Views that turn themselves into render nodes instead of having a `body`.
protocol PrimitiveView {
    @MainActor func resolve(_ ctx: ResolveContext, into out: inout [Node])
}

// MARK: - ViewBuilder

@resultBuilder
public struct ViewBuilder {
    public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView(_value: (repeat each content)) { ctx, out in
            var index = 0
            for child in repeat each content {
                resolveView(child, ctx.child(index), into: &out)
                index += 1
            }
        }
    }
    public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
    public static func buildOptional<Content: View>(_ content: Content?) -> Content? { content }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { .init(storage: .trueContent(first)) }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { .init(storage: .falseContent(second)) }
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView { AnyView(content) }
}

public struct EmptyView: View, PrimitiveView {
    public typealias Body = Never
    public init() {}
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {}
}

public struct TupleView<T>: View, PrimitiveView {
    public typealias Body = Never
    public var value: T
    let resolver: @MainActor (ResolveContext, inout [Node]) -> Void
    init(_value: T, resolver: @escaping @MainActor (ResolveContext, inout [Node]) -> Void) {
        self.value = _value
        self.resolver = resolver
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { resolver(ctx, &out) }
}

public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View, PrimitiveView {
    public typealias Body = Never
    enum Storage { case trueContent(TrueContent), falseContent(FalseContent) }
    let storage: Storage
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        switch storage {
        case .trueContent(let v): resolveView(v, ctx.child("true"), into: &out)
        case .falseContent(let v): resolveView(v, ctx.child("false"), into: &out)
        }
    }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
}
extension Optional: PrimitiveView where Wrapped: View {
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        if let v = self { resolveView(v, ctx.child("some"), into: &out) }
    }
}

public struct AnyView: View, PrimitiveView {
    public typealias Body = Never
    let resolver: @MainActor (ResolveContext, inout [Node]) -> Void
    public init<V: View>(_ view: V) {
        if let any = view as? AnyView { resolver = any.resolver; return }
        resolver = { ctx, out in resolveView(view, ctx.child(ObjectIdentifier(V.self)), into: &out) }
    }
    public init<V: View>(erasing view: V) { self.init(view) }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { resolver(ctx, &out) }
}

public struct Group<Content> {
    package let content: Content
}
extension Group: View, PrimitiveView where Content: View {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { resolveView(content, ctx, into: &out) }
}

// MARK: - ForEach

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {
    public var data: Data
    public var content: (Data.Element) -> Content
    let idGetter: (Data.Element) -> ID
}

extension ForEach: View, PrimitiveView where Content: View {
    public typealias Body = Never
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        for element in data {
            let id = idGetter(element)
            let start = out.count
            resolveView(content(element), ctx.child(id), into: &out)
            // Each element's views carry the element id (used by List selection, ScrollViewReader, ...).
            for node in out[start...] where node.traits[IDTraitKey.self] == nil {
                node.traits[IDTraitKey.self] = AnyHashable(id)
            }
        }
    }
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension ForEach where Content: View {
    /// `ForEach($items) { $item in ... }`
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection & RandomAccessCollection,
          C.Element: Identifiable, ID == C.Element.ID, C.Index: Hashable {
        self.init(data, id: \.id, content: content)
    }
    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection & RandomAccessCollection, C.Index: Hashable {
        let collection = data.wrappedValue
        self.data = collection.indices.lazy.map { ($0, collection[$0][keyPath: id]) }
        self.idGetter = { $0.1 }
        self.content = { pair in
            content(Binding(get: { data.wrappedValue[pair.0] }, set: { data.wrappedValue[pair.0] = $0 }))
        }
    }
}

// MARK: - Equatable / identity helpers

public struct EquatableView<Content: Equatable & View>: View {
    public var content: Content
    public init(content: Content) { self.content = content }
    public var body: some View { content }
}

extension View {
    public func equatable() -> EquatableView<Self> where Self: Equatable { EquatableView(content: self) }
    public func eraseToAnyView() -> AnyView { AnyView(self) }
}
