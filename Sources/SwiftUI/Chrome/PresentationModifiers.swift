// Modal presentations: sheet, fullScreenCover, popover, alert, confirmationDialog and the
// deprecated Alert / ActionSheet. A presented modifier records a `PresentationRecord` in a
// preference; `PresentationHostNode` (installed by the Renderer around the root) draws it on top.

typealias NodeResolver = @MainActor (ResolveContext) -> [Node]

nonisolated func nodeResolver<V: View>(_ view: V) -> NodeResolver { { ctx in resolveNodes(view, ctx) } }

/// The role of an alert / confirmation-dialog action.
///
/// Contract for `Button` (and anything else usable in `actions:`): when a Button has a role,
/// set `node.traits[PresentationActionRoleTraitKey.self]` to `.cancel` / `.destructive` on the
/// node(s) it resolves to (e.g. end its body with `.trait(PresentationActionRoleTraitKey.self, .cancel)`).
/// The action's title is the text of the first `TextNode` inside it (its label).
enum PresentationActionRole: Hashable { case cancel, destructive }
enum PresentationActionRoleTraitKey: TraitKey { typealias Value = PresentationActionRole }

struct PresentationAction {
    var title: String
    var role: PresentationActionRole?
}

struct DialogSpec {
    var title: Text?
    var message: NodeResolver?
    /// Views from an `actions:` builder; each top-level view is one action.
    var actions: NodeResolver?
    /// Actions given directly (deprecated Alert / ActionSheet).
    var fixedActions: [PresentationAction]?
}

struct PresentationRecord {
    enum Style {
        case sheet, fullScreenCover
        case alert(DialogSpec)
        case confirmationDialog(DialogSpec)
    }
    let style: Style
    let ctx: ResolveContext
    var content: NodeResolver? = nil
}

enum PresentationsKey: PreferenceKey {
    static var defaultValue: [PresentationRecord] { [] }
    static func reduce(value: inout [PresentationRecord], nextValue: () -> [PresentationRecord]) { value += nextValue() }
}

/// Attaches a presentation (when presented) to the first node of the modified content.
struct PresentationModifier: ViewModifier, PrimitiveModifier {
    let make: @MainActor (ResolveContext) -> PresentationRecord?
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        var nodes = content.nodes(ctx)
        guard let record = make(ctx.child("presentation").with { $0.isInListRow = false; $0.stackAxis = nil }) else {
            out.append(contentsOf: nodes)
            return
        }
        if nodes.isEmpty { nodes = [Node()] }
        var records = nodes[0].preferences[PresentationsKey.self]
        records.append(record)
        nodes[0].preferences.set(PresentationsKey.self, records)
        out.append(contentsOf: nodes)
    }
}

// MARK: - Sheets, covers, popovers

public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}

extension View {
    private func present(_ make: @escaping @MainActor (ResolveContext) -> PresentationRecord?) -> some View {
        modifier(PresentationModifier(make: make))
    }

    public func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        present { ctx in
            isPresented.wrappedValue ? PresentationRecord(style: .sheet, ctx: ctx, content: { resolveNodes(content(), $0) }) : nil
        }
    }
    public func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                         @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        present { ctx in
            item.wrappedValue.map { value in PresentationRecord(style: .sheet, ctx: ctx, content: { resolveNodes(content(value), $0) }) }
        }
    }
    public func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                               @ViewBuilder content: @escaping () -> Content) -> some View {
        present { ctx in
            isPresented.wrappedValue ? PresentationRecord(style: .fullScreenCover, ctx: ctx, content: { resolveNodes(content(), $0) }) : nil
        }
    }
    public func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                                   @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        present { ctx in
            item.wrappedValue.map { value in PresentationRecord(style: .fullScreenCover, ctx: ctx, content: { resolveNodes(content(value), $0) }) }
        }
    }
    /// On iPhone a popover adapts to a sheet.
    public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                       arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, content: content)
    }
    public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                           arrowEdge: Edge? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, content: content)
    }
}

// MARK: - Alerts

extension View {
    func _alert(_ presented: Bool, title: Text?, actions: NodeResolver?, message: NodeResolver?) -> some View {
        present { ctx in
            presented ? PresentationRecord(style: .alert(DialogSpec(title: title, message: message, actions: actions)), ctx: ctx) : nil
        }
    }

    public func alert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        _alert(isPresented.wrappedValue, title: Text(titleKey), actions: nodeResolver(actions()), message: nil)
    }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        _alert(isPresented.wrappedValue, title: Text(title), actions: nodeResolver(actions()), message: nil)
    }
    public func alert<A: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        _alert(isPresented.wrappedValue, title: title, actions: nodeResolver(actions()), message: nil)
    }
    public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _alert(isPresented.wrappedValue, title: Text(titleKey), actions: nodeResolver(actions()), message: nodeResolver(message()))
    }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>,
                                                           @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _alert(isPresented.wrappedValue, title: Text(title), actions: nodeResolver(actions()), message: nodeResolver(message()))
    }
    public func alert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _alert(isPresented.wrappedValue, title: title, actions: nodeResolver(actions()), message: nodeResolver(message()))
    }

    // presenting:
    public func alert<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?,
                                  @ViewBuilder actions: (T) -> A) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: Text(titleKey), actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?,
                                                     @ViewBuilder actions: (T) -> A) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: Text(title), actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    public func alert<A: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?,
                                  @ViewBuilder actions: (T) -> A) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: title, actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    public func alert<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?,
                                           @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: Text(titleKey),
               actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?,
                                                              @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: Text(title),
               actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }
    public func alert<A: View, M: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?,
                                           @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _alert(isPresented.wrappedValue && data != nil, title: title,
               actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }

    // error:
    public func alert<E: LocalizedError, A: View>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: () -> A) -> some View {
        _alert(isPresented.wrappedValue && error != nil, title: Text(verbatim: error?.errorDescription ?? ""),
               actions: nodeResolver(actions()), message: nil)
    }
    public func alert<E: LocalizedError, A: View, M: View>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: (E) -> A,
                                                           @ViewBuilder message: (E) -> M) -> some View {
        _alert(isPresented.wrappedValue && error != nil, title: Text(verbatim: error?.errorDescription ?? ""),
               actions: error.map { nodeResolver(actions($0)) }, message: error.map { nodeResolver(message($0)) })
    }

    // Deprecated Alert value.
    public func alert(isPresented: Binding<Bool>, content: () -> Alert) -> some View {
        let alert = isPresented.wrappedValue ? content() : nil
        return present { ctx in alert.map { PresentationRecord(style: .alert($0.spec), ctx: ctx) } }
    }
    public func alert<Item: Identifiable>(item: Binding<Item?>, content: (Item) -> Alert) -> some View {
        let alert = item.wrappedValue.map(content)
        return present { ctx in alert.map { PresentationRecord(style: .alert($0.spec), ctx: ctx) } }
    }
}

// MARK: - Confirmation dialogs

extension View {
    func _dialog(_ presented: Bool, title: Text, titleVisibility: Visibility, actions: NodeResolver?, message: NodeResolver?) -> some View {
        present { ctx in
            presented ? PresentationRecord(style: .confirmationDialog(DialogSpec(title: titleVisibility == .visible ? title : nil,
                                                                                  message: message, actions: actions)), ctx: ctx) : nil
        }
    }

    public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        _dialog(isPresented.wrappedValue, title: Text(titleKey), titleVisibility: titleVisibility, actions: nodeResolver(actions()), message: nil)
    }
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                               @ViewBuilder actions: () -> A) -> some View {
        _dialog(isPresented.wrappedValue, title: Text(title), titleVisibility: titleVisibility, actions: nodeResolver(actions()), message: nil)
    }
    public func confirmationDialog<A: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        _dialog(isPresented.wrappedValue, title: title, titleVisibility: titleVisibility, actions: nodeResolver(actions()), message: nil)
    }
    public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                     @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _dialog(isPresented.wrappedValue, title: Text(titleKey), titleVisibility: titleVisibility,
                actions: nodeResolver(actions()), message: nodeResolver(message()))
    }
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _dialog(isPresented.wrappedValue, title: Text(title), titleVisibility: titleVisibility,
                actions: nodeResolver(actions()), message: nodeResolver(message()))
    }
    public func confirmationDialog<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                     @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        _dialog(isPresented.wrappedValue, title: title, titleVisibility: titleVisibility,
                actions: nodeResolver(actions()), message: nodeResolver(message()))
    }
    public func confirmationDialog<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                               presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: Text(titleKey), titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                  presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: Text(title), titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    public func confirmationDialog<A: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                               presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: title, titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: nil)
    }
    public func confirmationDialog<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: Text(titleKey), titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                           presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: Text(title), titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }
    public func confirmationDialog<A: View, M: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _dialog(isPresented.wrappedValue && data != nil, title: title, titleVisibility: titleVisibility,
                actions: data.map { nodeResolver(actions($0)) }, message: data.map { nodeResolver(message($0)) })
    }

    // Deprecated ActionSheet value.
    public func actionSheet(isPresented: Binding<Bool>, content: () -> ActionSheet) -> some View {
        let sheet = isPresented.wrappedValue ? content() : nil
        return present { ctx in sheet.map { PresentationRecord(style: .confirmationDialog($0.spec), ctx: ctx) } }
    }
    public func actionSheet<T: Identifiable>(item: Binding<T?>, content: (T) -> ActionSheet) -> some View {
        let sheet = item.wrappedValue.map(content)
        return present { ctx in sheet.map { PresentationRecord(style: .confirmationDialog($0.spec), ctx: ctx) } }
    }
}

// MARK: - Deprecated Alert / ActionSheet values

public struct Alert {
    let title: Text
    let message: Text?
    let buttons: [Button]

    public init(title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil) {
        self.title = title
        self.message = message
        self.buttons = [dismissButton ?? .default(Text("OK"))]
    }
    public init(title: Text, message: Text? = nil, primaryButton: Alert.Button, secondaryButton: Alert.Button) {
        self.title = title
        self.message = message
        self.buttons = [primaryButton, secondaryButton]
    }

    public struct Button {
        let label: Text
        let role: PresentationActionRole?
        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, role: nil) }
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, role: .cancel) }
        public static func cancel(_ action: (() -> Void)? = {}) -> Alert.Button { Button(label: Text("Cancel"), role: .cancel) }
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, role: .destructive) }
    }

    var spec: DialogSpec {
        DialogSpec(title: title, message: message.map { nodeResolver($0) }, actions: nil,
                   fixedActions: buttons.map { PresentationAction(title: $0.label.plainString, role: $0.role) })
    }
}

public struct ActionSheet {
    public typealias Button = Alert.Button
    let title: Text
    let message: Text?
    let buttons: [Button]
    public init(title: Text, message: Text? = nil, buttons: [ActionSheet.Button] = [.cancel()]) {
        self.title = title
        self.message = message
        self.buttons = buttons
    }
    var spec: DialogSpec {
        DialogSpec(title: title, message: message.map { nodeResolver($0) }, actions: nil,
                   fixedActions: buttons.map { PresentationAction(title: $0.label.plainString, role: $0.role) })
    }
}

// MARK: - Presentation options (applied inside the presented content)

public struct PresentationDetent: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case medium, large, fraction(CGFloat), height(CGFloat), custom(ObjectIdentifier) }
    let kind: Kind
    let customHeight: (@MainActor @Sendable (Context) -> CGFloat?)?

    init(kind: Kind, customHeight: (@MainActor @Sendable (Context) -> CGFloat?)? = nil) {
        self.kind = kind
        self.customHeight = customHeight
    }
    public static func == (l: Self, r: Self) -> Bool { l.kind == r.kind }
    public func hash(into hasher: inout Hasher) { hasher.combine(kind) }

    public static let medium = PresentationDetent(kind: .medium)
    public static let large = PresentationDetent(kind: .large)
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { PresentationDetent(kind: .fraction(fraction)) }
    public static func height(_ height: CGFloat) -> PresentationDetent { PresentationDetent(kind: .height(height)) }
    public static func custom<D: CustomPresentationDetent>(_ type: D.Type) -> PresentationDetent {
        PresentationDetent(kind: .custom(ObjectIdentifier(type)), customHeight: { D.height(in: $0) })
    }

    @dynamicMemberLookup
    public struct Context {
        public var maxDetentValue: CGFloat
        let environment: EnvironmentValues
        public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T { environment[keyPath: keyPath] }
    }
}

public protocol CustomPresentationDetent {
    static func height(in context: Self.Context) -> CGFloat?
    typealias Context = PresentationDetent.Context
}

public struct PresentationBackgroundInteraction: Sendable {
    enum Kind: Sendable { case automatic, disabled, enabled(PresentationDetent?) }
    let kind: Kind
    public static let automatic = PresentationBackgroundInteraction(kind: .automatic)
    public static let disabled = PresentationBackgroundInteraction(kind: .disabled)
    public static let enabled = PresentationBackgroundInteraction(kind: .enabled(nil))
    public static func enabled(upThrough detent: PresentationDetent) -> PresentationBackgroundInteraction {
        PresentationBackgroundInteraction(kind: .enabled(detent))
    }
}

public struct PresentationAdaptation: Sendable {
    let id: Int
    public static let automatic = PresentationAdaptation(id: 0)
    public static let none = PresentationAdaptation(id: 1)
    public static let popover = PresentationAdaptation(id: 2)
    public static let sheet = PresentationAdaptation(id: 3)
    public static let fullScreenCover = PresentationAdaptation(id: 4)
}

public struct PresentationContentInteraction: Equatable, Sendable {
    let id: Int
    public static let automatic = PresentationContentInteraction(id: 0)
    public static let resizes = PresentationContentInteraction(id: 1)
    public static let scrolls = PresentationContentInteraction(id: 2)
}

/// iPad/Mac sheet sizing; a sheet on iPhone always spans the width.
public protocol PresentationSizing: Sendable {}
public struct AutomaticPresentationSizing: PresentationSizing {}
public struct FormPresentationSizing: PresentationSizing {}
public struct PagePresentationSizing: PresentationSizing {}
public struct FittedPresentationSizing: PresentationSizing {}
extension PresentationSizing where Self == AutomaticPresentationSizing { public static var automatic: AutomaticPresentationSizing { .init() } }
extension PresentationSizing where Self == FormPresentationSizing { public static var form: FormPresentationSizing { .init() } }
extension PresentationSizing where Self == PagePresentationSizing { public static var page: PagePresentationSizing { .init() } }
extension PresentationSizing where Self == FittedPresentationSizing { public static var fitted: FittedPresentationSizing { .init() } }
extension PresentationSizing {
    public func fitted(horizontal: Bool, vertical: Bool) -> some PresentationSizing { self }
    public func sticky(horizontal: Bool = false, vertical: Bool = false) -> some PresentationSizing { self }
}

struct PresentationOptions {
    var detents: [PresentationDetent]?
    var selection: PresentationDetent?
    var dragIndicator: Visibility?
    var cornerRadius: CGFloat?
    var backgroundPaint: _Paint?
    var backgroundNode: Node?
    var backgroundInteraction: PresentationBackgroundInteraction?

    mutating func merge(_ o: PresentationOptions) {
        detents = o.detents ?? detents
        selection = o.selection ?? selection
        dragIndicator = o.dragIndicator ?? dragIndicator
        cornerRadius = o.cornerRadius ?? cornerRadius
        if o.backgroundPaint != nil || o.backgroundNode != nil {
            backgroundPaint = o.backgroundPaint
            backgroundNode = o.backgroundNode
        }
        backgroundInteraction = o.backgroundInteraction ?? backgroundInteraction
    }
}

enum PresentationOptionsKey: PreferenceKey {
    static var defaultValue: PresentationOptions { PresentationOptions() }
    static func reduce(value: inout PresentationOptions, nextValue: () -> PresentationOptions) { value.merge(nextValue()) }
}

struct PresentationOptionModifier: ViewModifier, PrimitiveModifier {
    let apply: @MainActor (inout PresentationOptions, ResolveContext) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) {
            var options = node.preferences[PresentationOptionsKey.self]
            apply(&options, ctx)
            node.preferences.set(PresentationOptionsKey.self, options)
            out.append(node)
        }
    }
}

extension View {
    private func presentationOption(_ apply: @escaping @MainActor (inout PresentationOptions, ResolveContext) -> Void) -> some View {
        modifier(PresentationOptionModifier(apply: apply))
    }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        presentationOption { o, _ in o.detents = Array(detents) }
    }
    public func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        presentationOption { o, _ in o.detents = Array(detents); o.selection = selection.wrappedValue }
    }
    public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        presentationOption { o, _ in o.dragIndicator = visibility }
    }
    public func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View {
        presentationOption { o, _ in o.cornerRadius = cornerRadius }
    }
    public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        presentationOption { o, ctx in o.backgroundPaint = style._paint(in: ctx.env); o.backgroundNode = nil }
    }
    public func presentationBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        let background = content()
        return presentationOption { o, ctx in
            o.backgroundNode = resolveSingle(background, ctx.child("presentationBackground").with { $0.stackAxis = nil })
            o.backgroundPaint = nil
        }
    }
    public func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> some View {
        presentationOption { o, _ in o.backgroundInteraction = interaction }
    }
    public func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View { self }
    public func presentationCompactAdaptation(horizontal: PresentationAdaptation, vertical: PresentationAdaptation) -> some View { self }
    public func presentationContentInteraction(_ behavior: PresentationContentInteraction) -> some View { self }
    public func presentationSizing(_ sizing: some PresentationSizing) -> some View { self }
}
