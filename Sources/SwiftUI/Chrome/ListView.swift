// List: the public initializers. Layout and drawing live in ListLayout.swift.

public struct List<SelectionValue: Hashable, Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let content: Content
    /// Form always draws inset grouped, whatever `.listStyle` says.
    var forcedStyle: ListStyleKind? = nil

    init(content: Content, forcedStyle: ListStyleKind? = nil) {
        self.content = content
        self.forcedStyle = forcedStyle
    }

    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let style = forcedStyle ?? ctx.env.listStyleKind ?? .insetGrouped
        let rowCtx = ctx.child("list").with {
            $0.isInListRow = true
            $0.stackAxis = nil
            $0.listContentStyle = style
        }
        let nodes = resolveNodes(content, rowCtx)
        let list = ListNode(items: nodes, style: style, env: ctx.env)
        list.scrollIdentity = ctx.path
        out.append(list)
    }
}

// MARK: Data-driven initializers

extension List {
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    public init<RowContent: View>(
        _ data: Range<Int>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<RowContent: View>(
        _ data: Range<Int>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(content: ForEach(data, content: rowContent))
    }
    /// Hierarchical data: only the top level is drawn (rows start collapsed).
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    /// `List($items, selection: $selection) { $item in ... }`
    public init<Data: MutableCollection & RandomAccessCollection, RowContent: View>(
        _ data: Binding<Data>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>,
            Data.Element: Identifiable, Data.Index: Hashable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: MutableCollection & RandomAccessCollection, RowContent: View>(
        _ data: Binding<Data>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>,
            Data.Element: Identifiable, Data.Index: Hashable {
        self.init(content: ForEach(data, content: rowContent))
    }
}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content())
    }
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    public init<RowContent: View>(
        _ data: Range<Int>, @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
    public init<Data: MutableCollection & RandomAccessCollection, RowContent: View>(
        _ data: Binding<Data>, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>,
            Data.Element: Identifiable, Data.Index: Hashable {
        self.init(content: ForEach(data, content: rowContent))
    }
    public init<Data: MutableCollection & RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data.Index: Hashable {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }
}
