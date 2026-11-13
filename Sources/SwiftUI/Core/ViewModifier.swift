@MainActor @preconcurrency
public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier where Body == Never {
    public func body(content: Content) -> Never { fatalError("\(Self.self) is a primitive modifier") }
}

/// The not-yet-modified content handed to a modifier.
struct ModifierContent {
    let resolver: @MainActor (ResolveContext, inout [Node]) -> Void
    @MainActor func resolve(_ ctx: ResolveContext, into out: inout [Node]) { resolver(ctx, &out) }
    @MainActor func nodes(_ ctx: ResolveContext) -> [Node] {
        var out: [Node] = []
        resolver(ctx, &out)
        return out
    }
}

/// Built-in modifiers implement this instead of `body(content:)`.
protocol PrimitiveModifier {
    @MainActor func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node])
}

/// A built-in modifier that wraps every view it is applied to in one node.
/// (Applied to a Group/ForEach it wraps each child separately, as SwiftUI does.)
protocol NodeModifier: PrimitiveModifier {
    @MainActor func makeNode(child: Node, _ ctx: ResolveContext) -> Node
}
extension NodeModifier {
    @MainActor func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for child in content.nodes(ctx) { out.append(makeNode(child: child, ctx)) }
    }
}

public struct _ViewModifier_Content<Modifier: ViewModifier>: View, PrimitiveView {
    public typealias Body = Never
    let content: ModifierContent
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { content.resolve(ctx, into: &out) }
}

public struct ModifiedContent<Content, Modifier> {
    public var content: Content
    public var modifier: Modifier
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: View, PrimitiveView where Content: View, Modifier: ViewModifier {
    public typealias Body = Never
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let content = self.content
        let inner = ModifierContent { ctx, out in resolveView(content, ctx, into: &out) }
        if let primitive = modifier as? PrimitiveModifier {
            primitive.resolve(content: inner, ctx, into: &out)
        } else {
            let ctx = ctx.child(ObjectIdentifier(Modifier.self))
            installDynamicProperties(of: modifier, ctx)
            resolveView(modifier.body(content: _ViewModifier_Content(content: inner)), ctx, into: &out)
        }
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public func body(content: _ViewModifier_Content<Self>) -> some View {
        content.modifier(self.content).modifier(self.modifier)
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ViewModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

public struct EmptyModifier: ViewModifier {
    public static let identity = EmptyModifier()
    public init() {}
    public func body(content: Content) -> some View { content }
}
