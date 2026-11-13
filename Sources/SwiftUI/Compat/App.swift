// App / Scene. Nothing here launches anything: the screenshot runner renders the first
// WindowGroup's content (see `_PreviewEntry(app:)`).
import Observation

@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Scene where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive scene and has no body") }
}
extension Never: Scene {}

@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    @MainActor @preconcurrency init()
    @MainActor @preconcurrency static func main()
}

extension App {
    /// `@main` is stripped by the preprocessor; running the app is the runner's job.
    @MainActor public static func main() {}
}

/// Scenes that know which view they show.
protocol _SceneContent {
    @MainActor func _windowContent() -> AnyView?
}

extension Scene {
    @MainActor func _firstWindowContent() -> AnyView? {
        if let scene = self as? _SceneContent { return scene._windowContent() }
        if Body.self == Never.self { return nil }
        return body._firstWindowContent()
    }
}

extension _PreviewEntry {
    /// Renders an `App` the way it launches: the first window of its first window group.
    public init<A: App>(app: A) {
        self.init(String(describing: A.self)) {
            app.body._firstWindowContent() ?? AnyView(EmptyView())
        }
    }
}

// MARK: - Builders

@resultBuilder
public struct SceneBuilder {
    public static func buildBlock() -> _EmptyScene { _EmptyScene() }
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> TupleScene<(repeat each Content)> {
        TupleScene(find: {
            for scene in repeat each content {
                if let view = scene._firstWindowContent() { return view }
            }
            return nil
        })
    }
    public static func buildOptional<Content: Scene>(_ content: Content?) -> Content? { content }
    public static func buildIf<Content: Scene>(_ content: Content?) -> Content? { content }
    public static func buildEither<T: Scene, F: Scene>(first: T) -> _ConditionalScene<T, F> { .init(storage: .first(first)) }
    public static func buildEither<T: Scene, F: Scene>(second: F) -> _ConditionalScene<T, F> { .init(storage: .second(second)) }
}

public struct _EmptyScene: Scene {
    public typealias Body = Never
    public init() {}
}

public struct TupleScene<T>: Scene, _SceneContent {
    public typealias Body = Never
    let find: @MainActor () -> AnyView?
    @MainActor func _windowContent() -> AnyView? { find() }
}

public struct _ConditionalScene<TrueContent: Scene, FalseContent: Scene>: Scene, _SceneContent {
    public typealias Body = Never
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    @MainActor func _windowContent() -> AnyView? {
        switch storage {
        case .first(let s): return s._firstWindowContent()
        case .second(let s): return s._firstWindowContent()
        }
    }
}

extension Optional: Scene where Wrapped: Scene {}
extension Optional: _SceneContent where Wrapped: Scene {
    @MainActor func _windowContent() -> AnyView? { self?._firstWindowContent() }
}

// MARK: - Scenes

public struct WindowGroup<Content: View>: Scene, _SceneContent {
    public typealias Body = Never
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public init(id: String, @ViewBuilder content: () -> Content) { self.content = content() }
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) { self.content = content() }
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) { self.content = content() }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.content = content() }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) { self.content = content() }
    public init<D: Hashable & Codable>(for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> Content) {
        self.content = content(.constant(nil))
    }
    public init<D: Hashable & Codable>(id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> Content) {
        self.content = content(.constant(nil))
    }
    public init<D: Hashable & Codable>(_ titleKey: LocalizedStringKey, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> Content) {
        self.content = content(.constant(nil))
    }

    @MainActor func _windowContent() -> AnyView? { AnyView(content) }
}

public struct Window<Content: View>: Scene, _SceneContent {
    public typealias Body = Never
    let content: Content
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) { self.content = content() }
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) { self.content = content() }
    @MainActor func _windowContent() -> AnyView? { AnyView(content) }
}

/// macOS preferences window: never the launch window.
public struct Settings<Content: View>: Scene {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) {}
}

public struct FileDocumentConfiguration<Document> {
    @Binding public var document: Document
    public var isEditable = true
    public init(document: Binding<Document>) { _document = document }
}

/// Documents need a file system and a document type registry; the group is accepted and renders nothing.
public struct DocumentGroup<Document, Content: View>: Scene {
    public typealias Body = Never
    public init(newDocument: @autoclosure @escaping () -> Document, @ViewBuilder editor: @escaping (FileDocumentConfiguration<Document>) -> Content) {}
    public init(viewing documentType: Document.Type, @ViewBuilder viewer: @escaping (FileDocumentConfiguration<Document>) -> Content) {}
}

// MARK: - Scene modifiers

struct _ModifiedScene<Base: Scene>: Scene, _SceneContent {
    typealias Body = Never
    let base: Base
    let transform: (AnyView) -> AnyView
    @MainActor func _windowContent() -> AnyView? { base._firstWindowContent().map(transform) }
}

public struct WindowResizability: Hashable, Sendable {
    let raw: Int
    public static let automatic = WindowResizability(raw: 0)
    public static let contentSize = WindowResizability(raw: 1)
    public static let contentMinSize = WindowResizability(raw: 2)
}

extension Scene {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some Scene {
        _ModifiedScene(base: self) { AnyView($0.environment(keyPath, value)) }
    }
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some Scene {
        _ModifiedScene(base: self) { AnyView($0.environment(object)) }
    }
    public func environmentObject<T: ObservableObject>(_ object: T) -> some Scene {
        _ModifiedScene(base: self) { AnyView($0.environmentObject(object)) }
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some Scene { self }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some Scene { self }
    public func commands<C: Commands>(@CommandsBuilder content: () -> C) -> some Scene { self }
    public func commandsRemoved() -> some Scene { self }
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene { self }
    public func defaultSize(_ size: CGSize) -> some Scene { self }
    public func windowResizability(_ resizability: WindowResizability) -> some Scene { self }
    public func handlesExternalEvents(matching conditions: Set<String>) -> some Scene { self }
    public func defaultAppStorage(_ store: UserDefaults) -> some Scene { self }
}

// MARK: - Commands

@MainActor @preconcurrency
public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder @MainActor @preconcurrency var body: Self.Body { get }
}
extension Commands where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive command and has no body") }
}
extension Never: Commands {}

@resultBuilder
public struct CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<Content: Commands>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Commands>(_ content: repeat each Content) -> TupleCommands<(repeat each Content)> { TupleCommands() }
    public static func buildOptional<Content: Commands>(_ content: Content?) -> Content? { content }
    public static func buildEither<T: Commands, F: Commands>(first: T) -> _ConditionalCommands<T, F> { _ConditionalCommands() }
    public static func buildEither<T: Commands, F: Commands>(second: F) -> _ConditionalCommands<T, F> { _ConditionalCommands() }
}

public struct EmptyCommands: Commands {
    public typealias Body = Never
    public init() {}
}
public struct TupleCommands<T>: Commands { public typealias Body = Never }
public struct _ConditionalCommands<T: Commands, F: Commands>: Commands { public typealias Body = Never }
extension Optional: Commands where Wrapped: Commands {}

public struct CommandGroupPlacement: Hashable, Sendable {
    let name: String
    public static let appInfo = CommandGroupPlacement(name: "appInfo")
    public static let systemServices = CommandGroupPlacement(name: "systemServices")
    public static let appVisibility = CommandGroupPlacement(name: "appVisibility")
    public static let appTermination = CommandGroupPlacement(name: "appTermination")
    public static let newItem = CommandGroupPlacement(name: "newItem")
    public static let saveItem = CommandGroupPlacement(name: "saveItem")
    public static let importExport = CommandGroupPlacement(name: "importExport")
    public static let printItem = CommandGroupPlacement(name: "printItem")
    public static let undoRedo = CommandGroupPlacement(name: "undoRedo")
    public static let pasteboard = CommandGroupPlacement(name: "pasteboard")
    public static let textEditing = CommandGroupPlacement(name: "textEditing")
    public static let textFormatting = CommandGroupPlacement(name: "textFormatting")
    public static let toolbar = CommandGroupPlacement(name: "toolbar")
    public static let sidebar = CommandGroupPlacement(name: "sidebar")
    public static let windowSize = CommandGroupPlacement(name: "windowSize")
    public static let windowList = CommandGroupPlacement(name: "windowList")
    public static let singleWindowList = CommandGroupPlacement(name: "singleWindowList")
    public static let windowArrangement = CommandGroupPlacement(name: "windowArrangement")
    public static let help = CommandGroupPlacement(name: "help")
}

public struct CommandMenu<Content: View>: Commands {
    public typealias Body = Never
    public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {}
    public init<S: StringProtocol>(_ name: S, @ViewBuilder content: () -> Content) {}
}

public struct CommandGroup<Content: View>: Commands {
    public typealias Body = Never
    public init(before placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
    public init(after placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
    public init(replacing placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
}

public struct SidebarCommands: Commands { public typealias Body = Never; public init() {} }
public struct ToolbarCommands: Commands { public typealias Body = Never; public init() {} }
public struct TextEditingCommands: Commands { public typealias Body = Never; public init() {} }
public struct TextFormattingCommands: Commands { public typealias Body = Never; public init() {} }
public struct InspectorCommands: Commands { public typealias Body = Never; public init() {} }
