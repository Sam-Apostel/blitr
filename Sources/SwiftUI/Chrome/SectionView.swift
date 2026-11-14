// Section: a header, rows and a footer. Inside a List it resolves to a `SectionMarkerNode` that
// the List takes apart; anywhere else the same node simply stacks header, content and footer.

/// What a Section resolves to. A List reads `header`, `rows`, `footer`; any other container just
/// lays it out as a vertical stack of the three parts.
final class SectionMarkerNode: Node {
    let header: Node?
    let rows: [Node]
    let footer: Node?
    /// Spacing before this section (`.listSectionSpacing` at the section).
    let spacing: ListSectionSpacing
    private var stack: Node { children[0] }

    init(header: Node?, rows: [Node], footer: Node?, spacing: ListSectionSpacing) {
        self.header = header
        self.rows = rows
        self.footer = footer
        self.spacing = spacing
        let parts = (header.map { [$0] } ?? []) + rows + (footer.map { [$0] } ?? [])
        super.init(children: [StackNode(axis: .vertical, alignment: .leading, spacing: nil, children: parts)])
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { stack.sizeThatFits(proposal) }
    override func layout(size: CGSize, _ ctx: PlaceContext) { stack.place(at: .zero, size: size, ctx) }
}

public struct Section<Parent, Content, Footer> {
    let header: Parent
    let content: Content
    let footer: Footer
    var isExpanded: Binding<Bool>? = nil
}

extension Section: View, PrimitiveView where Parent: View, Content: View, Footer: View {
    public typealias Body = Never

    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    @available(iOS, deprecated: 100000.0, renamed: "Section(content:header:footer:)")
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
        self.footer = footer
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let style = ctx.env.listContentStyle
        let scheme = ctx.env.colorScheme
        func decorate(_ env: inout EnvironmentValues, isHeader: Bool) {
            guard let style else { return }
            env.isInListRow = false
            env.stackAxis = nil
            let secondary = AnyShapeStyle(Color(SystemColor.secondaryLabel.resolve(scheme)))
            if env.renderPlatform == .tvOS {
                // tvOS: sentence-case secondary headers and footers (est. sizes, TVMetrics).
                env.font = isHeader ? .system(size: TVMetrics.headerFontSize, weight: .semibold) : .system(size: TVMetrics.footerFontSize)
                env.foregroundStyle = isHeader && env.headerProminence == .increased ? AnyShapeStyle(Color(SystemColor.label.resolve(scheme))) : secondary
                env.foregroundStyleLevels = nil
                return
            }
            if isHeader && env.headerProminence == .increased {
                env.font = .system(size: ListMetrics.prominentHeaderFontSize, weight: .semibold)
                env.foregroundStyle = AnyShapeStyle(Color(SystemColor.label.resolve(scheme)))
            } else if isHeader && !style.isGroupedFamily {
                env.font = .system(size: ListMetrics.plainHeaderFontSize, weight: .semibold)
                env.foregroundStyle = secondary
            } else if isHeader {
                // iOS 26 inset grouped headers: sentence case, semibold, larger.
                let design = ListMetrics.forDesign(style == .insetGrouped ? env.designLanguage : .flat)
                if let weight = design.headerWeight {
                    env.font = .system(size: design.headerFontSize, weight: weight)
                } else {
                    env.font = .system(size: design.headerFontSize)
                }
                env.foregroundStyle = secondary
                if design.headerUppercased { env.textCase = .uppercase }
            } else {
                env.font = .system(size: ListMetrics.footerFontSize)
                env.foregroundStyle = secondary
            }
            env.foregroundStyleLevels = nil
        }
        let headerNodes = resolveNodes(header, ctx.child("header").with { decorate(&$0, isHeader: true) })
        let footerNodes = resolveNodes(footer, ctx.child("footer").with { decorate(&$0, isHeader: false) })
        let expanded = isExpanded?.wrappedValue ?? true
        let rows = expanded ? resolveNodes(content, ctx.child("content")) : []
        func single(_ nodes: [Node]) -> Node? {
            if nodes.isEmpty { return nil }
            return nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: .leading, spacing: nil, children: nodes)
        }
        guard style != nil else {
            // Outside a List: header, content and footer in order.
            out.append(contentsOf: headerNodes)
            out.append(contentsOf: rows)
            out.append(contentsOf: footerNodes)
            return
        }
        out.append(SectionMarkerNode(header: single(headerNodes), rows: rows, footer: single(footerNodes),
                                     spacing: ctx.env.listSectionSpacing))
    }
}

extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(header: EmptyView(), content: content(), footer: footer())
    }
    @available(iOS, deprecated: 100000.0, renamed: "Section(content:footer:)")
    public init(footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: footer)
    }
}

extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(header: header(), content: content(), footer: EmptyView())
    }
    @available(iOS, deprecated: 100000.0, renamed: "Section(content:header:)")
    public init(header: Parent, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content(), footer: EmptyView())
    }
    public init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(header: header(), content: content(), footer: EmptyView(), isExpanded: isExpanded)
    }
}

extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: EmptyView())
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(header: Text(titleKey), content: content(), footer: EmptyView())
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(header: Text(title), content: content(), footer: EmptyView())
    }
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(header: Text(titleKey), content: content(), footer: EmptyView(), isExpanded: isExpanded)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(header: Text(title), content: content(), footer: EmptyView(), isExpanded: isExpanded)
    }
}
