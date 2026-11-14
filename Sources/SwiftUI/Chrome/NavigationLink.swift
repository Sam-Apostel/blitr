// NavigationLink: draws its label. In a List row it asks the row for a disclosure chevron and
// keeps the primary color; elsewhere it is tinted like a button. An active link (deprecated
// `isActive` / `tag:selection:` forms) pushes its destination onto the enclosing stack.

public struct NavigationLink<Label: View, Destination: View>: View, PrimitiveView {
    public typealias Body = Never
    let label: Label
    let destination: Destination?
    let isActive: Bool
    /// The value of a `NavigationLink(value:)`, pushed through the stack's `navigationDestination`.
    var value: AnyHashable?

    init(label: Label, destination: Destination?, isActive: Bool = false) {
        self.label = label
        self.destination = destination
        self.isActive = isActive
    }

    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination())
    }
    @available(*, deprecated, message: "Use init(destination:label:) with a destination closure")
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init(isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination(), isActive: isActive.wrappedValue)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init(destination: Destination, isActive: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination, isActive: isActive.wrappedValue)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init<V: Hashable>(tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination(), isActive: selection.wrappedValue == tag)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init<V: Hashable>(destination: Destination, tag: V, selection: Binding<V?>, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: destination, isActive: selection.wrappedValue == tag)
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        // Focusable; remote `select` pushes the destination onto the enclosing stack.
        let stack = ctx.env.navigationStackIdentity, runtime = ctx.runtime
        let push: NavigationPush? = destination.map { .view(AnyView($0)) } ?? value.map { .value($0) }
        let activate: @MainActor () -> Void = {
            guard let stack, let push else {
                runtime.warn(push == nil ? "NavigationLink has no destination or value; select does nothing"
                                         : "NavigationLink is not inside a NavigationStack; select cannot push its destination")
                return
            }
            runtime.focus.pushes[stack, default: []].append(push)
            runtime.needsAnotherPass = true
        }
        let content = ModifierContent { ctx, out in self.resolveLink(ctx, into: &out) }
        FocusElementModifier(role: "navigationLink", activate: activate).resolve(content: content, ctx, into: &out)
    }

    private func resolveLink(_ ctx: ResolveContext, into out: inout [Node]) {
        let inRow = ctx.env.isInListRow
        if ctx.env.renderPlatform == .tvOS {
            // tvOS: a row (the List draws the platter; dark content while focused) or a bordered button.
            let start = out.count
            if inRow {
                resolveView(label, ctx.with { if $0.tvShowsFocus { $0.colorScheme = .light; $0.tvOnFocusedPlatter = true } }, into: &out)
            } else {
                resolveView(_TVButtonVisual(kind: .automatic, label: AnyView(label), role: nil), ctx, into: &out)
            }
            for node in out[start...] where inRow { node.traits[ListRowAccessoryTraitKey.self] = .disclosureIndicator }
            axApplyShared(out[start...], .button(enabled: ctx.env.isEnabled))
            if isActive, let destination, out.count > start {
                var chrome = out[start].preferences[NavigationChromeKey.self]
                chrome.presented.append(AnyView(destination))
                out[start].preferences.set(NavigationChromeKey.self, chrome)
            }
            return
        }
        let labelCtx = ctx.with { env in
            if !inRow {
                let accent = Color.accentColor.rgba(in: env)
                env.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color(env.isEnabled ? accent : SystemColor.tertiaryLabel.resolve(env.colorScheme))))
                env.foregroundStyleLevels = nil
            }
        }
        let start = out.count
        resolveView(label, labelCtx, into: &out)
        for node in out[start...] { node.traits[ListRowAccessoryTraitKey.self] = .disclosureIndicator }
        axApplyShared(out[start...], .button(enabled: ctx.env.isEnabled))
        if isActive, let destination, out.count > start {
            let first = out[start]
            var chrome = first.preferences[NavigationChromeKey.self]
            chrome.presented.append(AnyView(destination))
            first.preferences.set(NavigationChromeKey.self, chrome)
        }
    }
}

extension NavigationLink where Destination == Never {
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.init(label: label(), destination: nil)
        self.value = value.map { AnyHashable($0) }
    }
}

extension NavigationLink where Label == Text, Destination == Never {
    public init<P: Hashable>(_ titleKey: LocalizedStringKey, value: P?) {
        self.init(label: Text(titleKey), destination: nil)
        self.value = value.map { AnyHashable($0) }
    }
    @_disfavoredOverload
    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) {
        self.init(label: Text(title), destination: nil)
        self.value = value.map { AnyHashable($0) }
    }
}

extension NavigationLink where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(titleKey), destination: destination())
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(title), destination: destination())
    }
    @available(*, deprecated, message: "Pass a closure as the destination")
    public init(_ titleKey: LocalizedStringKey, destination: Destination) {
        self.init(label: Text(titleKey), destination: destination)
    }
    @available(*, deprecated, message: "Pass a closure as the destination")
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, destination: Destination) {
        self.init(label: Text(title), destination: destination)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init(_ titleKey: LocalizedStringKey, isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(titleKey), destination: destination(), isActive: isActive.wrappedValue)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(title), destination: destination(), isActive: isActive.wrappedValue)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    public init<V: Hashable>(_ titleKey: LocalizedStringKey, tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(titleKey), destination: destination(), isActive: selection.wrappedValue == tag)
    }
    @available(*, deprecated, message: "use NavigationLink(value:label:) inside a NavigationStack")
    @_disfavoredOverload
    public init<S: StringProtocol, V: Hashable>(_ title: S, tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(title), destination: destination(), isActive: selection.wrappedValue == tag)
    }
}

extension View {
    public func isDetailLink(_ isDetailLink: Bool) -> some View { self }
}
