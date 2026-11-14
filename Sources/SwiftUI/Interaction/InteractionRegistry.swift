// What scripted steps (`--steps`, docs/INTERACTION.md) can do to each control beyond its default action.
//
// `Runtime.activations` and `AccessibilityInfo.activate` already say what a tap does. Controls with more
// to offer (typing, setting a value, the two halves of a stepper, swipe actions) record handlers here
// with `.interaction { ... }`, keyed by the accessibility element they belong to. The registry is
// rebuilt on every pass and only filled during an interaction capture.

@MainActor
struct InteractionHandlers {
    /// Short name of the control for messages ("text field", "slider"...).
    var kind = ""
    var setText: (@MainActor (String) -> Void)?
    var submit: (@MainActor () -> Void)?
    /// Parses and applies a value; returns how it reads back, or throws a message for the user.
    var setValue: (@MainActor (String) throws -> String)?
    var increment: (@MainActor () -> Void)?
    var decrement: (@MainActor () -> Void)?
    var longPress: (@MainActor () -> Void)?
    /// Swipe actions per edge, in the order they are declared (the first is the full-swipe action).
    var swipeLeading: [SwipeAction] = []
    var swipeTrailing: [SwipeAction] = []
    /// A context menu is attached (it cannot be shown).
    var hasContextMenu = false

    struct SwipeAction {
        var label: String
        var run: @MainActor () -> Void
    }

    mutating func merge(_ o: InteractionHandlers) {
        if kind.isEmpty { kind = o.kind }
        setText = setText ?? o.setText
        submit = submit ?? o.submit
        setValue = setValue ?? o.setValue
        increment = increment ?? o.increment
        decrement = decrement ?? o.decrement
        longPress = longPress ?? o.longPress
        swipeLeading += o.swipeLeading
        swipeTrailing += o.swipeTrailing
        hasContextMenu = hasContextMenu || o.hasContextMenu
    }
}

@MainActor
enum InteractionRegistry {
    /// True during an interaction capture; nothing is recorded otherwise.
    static var isActive = false
    private(set) static var handlers: [ObjectIdentifier: InteractionHandlers] = [:]
    private static var boxes: [AXBox] = []
    /// Navigation stacks of the pass: the node, its identity, and how to pop a bound path.
    private(set) static var stacks: [(node: Node, path: IdentityPath)] = []
    private(set) static var pathPops: [IdentityPath: @MainActor () -> Bool] = [:]
    /// Paging TabViews of the pass.
    private(set) static var pagers: [(node: Node, count: Int, selected: Int, select: @MainActor (Int) -> Void)] = []
    /// Passes run since the counter was last read (for the step log).
    static var passCount = 0

    static func beginPass() {
        handlers = [:]
        boxes = []
        stacks = []
        pathPops = [:]
        pagers = []
        passCount += 1
    }

    static func add(_ box: AXBox, _ h: InteractionHandlers) {
        let id = ObjectIdentifier(box)
        if var existing = handlers[id] {
            existing.merge(h)
            handlers[id] = existing
        } else {
            handlers[id] = h
            boxes.append(box)
        }
    }

    static func noteStack(_ node: Node, _ path: IdentityPath) {
        guard isActive else { return }
        stacks.append((node, path))
    }

    static func notePager(_ node: Node, count: Int, selected: Int, select: @escaping @MainActor (Int) -> Void) {
        guard isActive else { return }
        pagers.append((node, count, selected, select))
    }

    /// `pop` removes the last element of a `NavigationStack(path:)` binding; false when it is empty.
    static func notePathPop(_ path: IdentityPath, _ pop: (@MainActor () -> Bool)?) {
        guard isActive, let pop else { return }
        pathPops[path] = pop
    }
}

struct InteractionModifier: ViewModifier, PrimitiveModifier {
    let make: @MainActor (ResolveContext) -> InteractionHandlers?
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let start = out.count
        content.resolve(ctx, into: &out)
        guard InteractionRegistry.isActive, start < out.count, let handlers = make(ctx) else { return }
        var seen: Set<ObjectIdentifier> = []
        for node in out[start...] {
            let box: AXBox
            if let existing = node.ax { box = existing } else { box = AXBox(); node.ax = box }
            if seen.insert(ObjectIdentifier(box)).inserted { InteractionRegistry.add(box, handlers) }
        }
    }
}

extension View {
    /// Records what scripted steps can do to this control. Apply it outside the control's `axInfo`.
    func interaction(_ make: @escaping @MainActor (ResolveContext) -> InteractionHandlers?) -> ModifiedContent<Self, InteractionModifier> {
        modifier(InteractionModifier(make: make))
    }
    func interaction(_ handlers: InteractionHandlers?) -> ModifiedContent<Self, InteractionModifier> {
        modifier(InteractionModifier { _ in handlers })
    }
}

// MARK: - Handlers of the built-in controls

extension InteractionHandlers {
    static func text(_ binding: Binding<String>, kind: String = "text field") -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = kind
        h.setText = { binding.wrappedValue = $0 }
        return h
    }

    static func toggle(_ binding: Binding<Bool>) -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = "toggle"
        h.setValue = { raw in
            switch raw.lowercased() {
            case "on", "true", "yes", "1": binding.wrappedValue = true
            case "off", "false", "no", "0": binding.wrappedValue = false
            case "toggle": binding.wrappedValue.toggle()
            default: throw RenderError("a toggle takes on or off, not \"\(raw)\"")
            }
            return binding.wrappedValue ? "on" : "off"
        }
        return h
    }

    static func slider<V: BinaryFloatingPoint>(_ binding: Binding<V>, bounds: ClosedRange<V>, step: V.Stride?) -> InteractionHandlers
    where V.Stride: BinaryFloatingPoint {
        var h = InteractionHandlers()
        h.kind = "slider"
        let lower = Double(bounds.lowerBound), upper = Double(bounds.upperBound)
        func apply(_ value: Double) -> String {
            var v = min(upper, max(lower, value))
            if let step, Double(step) > 0 { v = min(upper, lower + ((v - lower) / Double(step)).rounded() * Double(step)) }
            binding.wrappedValue = V(v)
            return AnimationDefaults.format(v)
        }
        h.setValue = { raw in
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix("%"), let pct = Double(text.dropLast()) { return apply(lower + (upper - lower) * pct / 100) }
            guard let v = Double(text) else {
                throw RenderError("a slider takes a number in \(AnimationDefaults.format(lower))...\(AnimationDefaults.format(upper)) or a percentage, not \"\(raw)\"")
            }
            return apply(v)
        }
        let delta = step.map { Double($0) } ?? (upper - lower) / 10
        h.increment = { _ = apply(Double(binding.wrappedValue) + delta) }
        h.decrement = { _ = apply(Double(binding.wrappedValue) - delta) }
        return h
    }

    static func stepper<V: Strideable>(_ binding: Binding<V>, bounds: ClosedRange<V>?, step: V.Stride) -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = "stepper"
        func clamp(_ v: V) -> V {
            guard let bounds else { return v }
            return min(bounds.upperBound, max(bounds.lowerBound, v))
        }
        h.increment = { binding.wrappedValue = clamp(binding.wrappedValue.advanced(by: step)) }
        h.decrement = { binding.wrappedValue = clamp(binding.wrappedValue.advanced(by: 0 - step)) }
        h.setValue = { raw in
            let text = raw.trimmingCharacters(in: .whitespaces)
            var parsed: V?
            if V.self == Int.self { parsed = Int(text) as? V }
            else if V.self == Double.self { parsed = Double(text) as? V }
            else if V.self == Float.self { parsed = Float(text) as? V }
            else if V.self == CGFloat.self { parsed = Double(text).map { CGFloat($0) } as? V }
            else if let losslessType = V.self as? LosslessStringConvertible.Type { parsed = losslessType.init(text) as? V }
            guard let value = parsed else { throw RenderError("a stepper takes a number, not \"\(raw)\" (or use `tap <stepper> +` / `-`)") }
            binding.wrappedValue = clamp(value)
            return "\(binding.wrappedValue)"
        }
        return h
    }

    static func stepper(onIncrement: (() -> Void)?, onDecrement: (() -> Void)?) -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = "stepper"
        h.increment = onIncrement.map { f in { f() } }
        h.decrement = onDecrement.map { f in { f() } }
        return h
    }

    static func date(_ binding: Binding<Date>) -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = "date picker"
        h.setValue = { raw in
            guard let date = InteractionDates.parse(raw) else {
                throw RenderError("a date picker takes an ISO 8601 date such as 2025-03-01 or 2025-03-01T09:30:00Z, not \"\(raw)\"")
            }
            binding.wrappedValue = date
            return InteractionDates.format(date)
        }
        return h
    }

    /// A picker: `labels` are the option titles, `select` chooses one by index.
    static func picker(labels: [String], select: @escaping @MainActor (Int) -> Void) -> InteractionHandlers {
        var h = InteractionHandlers()
        h.kind = "picker"
        h.setValue = { raw in
            let wanted = raw.trimmingCharacters(in: .whitespaces)
            var index = labels.firstIndex(of: wanted)
                ?? labels.firstIndex { $0.caseInsensitiveCompare(wanted) == .orderedSame }
            if index == nil {
                let partial = labels.indices.filter { labels[$0].range(of: wanted, options: .caseInsensitive) != nil }
                if partial.count == 1 { index = partial[0] }
            }
            if index == nil, wanted.hasPrefix("#"), let n = Int(wanted.dropFirst()), labels.indices.contains(n - 1) { index = n - 1 }
            guard let index else {
                throw RenderError("the picker has no option \"\(raw)\". Options: \(labels.map { "\"\($0)\"" }.joined(separator: ", "))")
            }
            select(index)
            return labels[index]
        }
        return h
    }
}

enum InteractionDates {
    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate]] {
            iso.formatOptions = options
            if let d = iso.date(from: text) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }

    static func format(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }
}

// MARK: - Modifiers that used to be inert

enum SubmitActionsKey: EnvironmentKey { static let defaultValue: [@MainActor () -> Void] = [] }
extension EnvironmentValues {
    /// `onSubmit` actions around the view, outermost first.
    var submitActions: [@MainActor () -> Void] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }
}

extension InteractionHandlers {
    /// The handlers of a text input in `ctx`: typing writes the binding, `submit` runs the `onSubmit` actions.
    static func textInput(_ binding: Binding<String>?, kind: String, _ ctx: ResolveContext) -> InteractionHandlers? {
        guard let binding else { return nil }
        var h = InteractionHandlers.text(binding, kind: kind)
        let actions = ctx.env.submitActions
        h.submit = { for action in actions.reversed() { action() } }
        return h
    }
}

/// `ForEach(...).onDelete`: a swipe on a row deletes it.
public struct _EditableForEach<Base: DynamicViewContent>: DynamicViewContent, PrimitiveView {
    public typealias Body = Never
    let base: Base
    let delete: ((IndexSet) -> Void)?
    public var data: Base.Data { base.data }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let start = out.count
        resolveView(base, ctx, into: &out)
        guard InteractionRegistry.isActive, let delete, start < out.count else { return }
        // Consecutive nodes with one ForEach id are one element.
        var index = -1
        var last: AnyHashable?
        for node in out[start...] {
            let id = node.traits[IDTraitKey.self]
            if index < 0 || id != last { index += 1; last = id }
            let i = index
            var h = InteractionHandlers()
            h.swipeTrailing = [.init(label: "Delete", run: { delete(IndexSet(integer: i)) })]
            let box: AXBox
            if let existing = node.ax { box = existing } else { box = AXBox(); node.ax = box }
            InteractionRegistry.add(box, h)
        }
    }
}

struct SwipeActionsModifier<T: View>: ViewModifier, PrimitiveModifier {
    let edge: HorizontalEdge
    let actions: T
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let start = out.count
        content.resolve(ctx, into: &out)
        guard InteractionRegistry.isActive, start < out.count else { return }
        // Each top-level view of the content with a default action (a Button) is one swipe action.
        var found: [InteractionHandlers.SwipeAction] = []
        func collect(_ node: Node) {
            if let run = node.ax?.info.activate {
                found.append(.init(label: axText([node]), run: run))
                return
            }
            for child in node.children { collect(child) }
        }
        for node in resolveNodes(actions, ctx.child("swipeActions")) { collect(node) }
        guard !found.isEmpty else { return }
        var h = InteractionHandlers()
        if edge == .leading { h.swipeLeading = found } else { h.swipeTrailing = found }
        for node in out[start...] {
            let box: AXBox
            if let existing = node.ax { box = existing } else { box = AXBox(); node.ax = box }
            InteractionRegistry.add(box, h)
        }
    }
}
