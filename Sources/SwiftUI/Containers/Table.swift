// Table: columns and rows. In a compact width (iPhone) a table shows only its first column, as a plain
// list without headers; in a regular width (iPad, and macOS) it draws a header row and every column.
import Foundation

// MARK: - Row content

@MainActor @preconcurrency
public protocol TableRowContent<TableRowValue> {
    associatedtype TableRowValue: Identifiable = TableRowBody.TableRowValue
    associatedtype TableRowBody: TableRowContent
    @MainActor @preconcurrency var tableRowBody: Self.TableRowBody { get }
}

extension Never: TableRowContent {
    public typealias TableRowBody = Never
    public typealias TableRowValue = Never
    public var tableRowBody: Never { fatalError() }
}

extension TableRowContent where TableRowBody == Never {
    public var tableRowBody: Never { fatalError("\(Self.self) is a primitive table row and has no body") }
}

/// One drawn row: a value for the column cells, or a section header.
struct _TableRowItem {
    var value: Any?
    var id: AnyHashable?
    var depth = 0
    /// nil: no disclosure indicator; otherwise whether the row's children are shown.
    var expanded: Bool?
    var header: AnyView?
}

/// Built-in row content lists its rows; user types go through `tableRowBody`.
protocol _TableRowSource {
    @MainActor func _collectRows(depth: Int, into out: inout [_TableRowItem])
}

@MainActor
func _collectTableRows<R: TableRowContent>(of rows: R, _ depth: Int, _ out: inout [_TableRowItem]) {
    if let source = rows as? _TableRowSource {
        source._collectRows(depth: depth, into: &out)
    } else if R.TableRowBody.self != Never.self {
        _collectTableRows(of: rows.tableRowBody, depth, &out)
    }
}

public struct TableRow<Value: Identifiable>: TableRowContent, _TableRowSource {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never
    let value: Value
    public init(_ value: Value) { self.value = value }
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        out.append(_TableRowItem(value: value, id: AnyHashable(value.id), depth: depth))
    }
}

public struct EmptyTableRowContent<Value: Identifiable>: TableRowContent, _TableRowSource {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never
    init() {}
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {}
}

public struct TupleTableRowContent<Value: Identifiable, T>: TableRowContent, _TableRowSource {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never
    public var value: T
    let collect: @MainActor (Int, inout [_TableRowItem]) -> Void
    init(value: T, collect: @escaping @MainActor (Int, inout [_TableRowItem]) -> Void) {
        self.value = value
        self.collect = collect
    }
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) { collect(depth, &out) }
}

public struct _ConditionalTableRowContent<TrueContent: TableRowContent, FalseContent: TableRowContent>: TableRowContent, _TableRowSource
where TrueContent.TableRowValue == FalseContent.TableRowValue {
    public typealias TableRowValue = TrueContent.TableRowValue
    public typealias TableRowBody = Never
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        switch storage {
        case .first(let rows): _collectTableRows(of: rows, depth, &out)
        case .second(let rows): _collectTableRows(of: rows, depth, &out)
        }
    }
}

extension Optional: TableRowContent where Wrapped: TableRowContent {
    public typealias TableRowValue = Wrapped.TableRowValue
    public typealias TableRowBody = Never
}
extension Optional: _TableRowSource where Wrapped: TableRowContent {
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        if let rows = self { _collectTableRows(of: rows, depth, &out) }
    }
}

/// The rows of `Table(data) { columns }`.
public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent, _TableRowSource where Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element
    public typealias TableRowBody = Never
    let data: Data
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        for element in data { out.append(_TableRowItem(value: element, id: AnyHashable(element.id), depth: depth)) }
    }
}

/// The rows of a hierarchical `Table(data, children:) { columns }`. Every level starts collapsed, as on a device.
public struct TableOutlineGroupContent<Data: RandomAccessCollection>: TableRowContent, _TableRowSource where Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element
    public typealias TableRowBody = Never
    let data: Data
    let children: KeyPath<Data.Element, Data?>
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        for element in data {
            let hasChildren = element[keyPath: children] != nil
            out.append(_TableRowItem(value: element, id: AnyHashable(element.id), depth: depth, expanded: hasChildren ? false : nil))
        }
    }
}

extension ForEach: TableRowContent where Content: TableRowContent {
    public typealias TableRowValue = Content.TableRowValue
    public typealias TableRowBody = Never

    public init<V>(_ data: Data, @TableRowBuilder<V> content: @escaping (Data.Element) -> Content)
    where ID == Data.Element.ID, V == Content.TableRowValue, Data.Element: Identifiable {
        self.data = data
        self.content = content
        self.idGetter = { $0.id }
    }
    public init<V>(_ data: Data, id: KeyPath<Data.Element, ID>, @TableRowBuilder<V> content: @escaping (Data.Element) -> Content)
    where V == Content.TableRowValue {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
    public init<V>(_ data: Data) where ID == Data.Element.ID, Content == TableRow<V>, Data.Element == V {
        self.data = data
        self.content = { TableRow($0) }
        self.idGetter = { $0.id }
    }
    public init<V>(_ data: Range<Int>, @TableRowBuilder<V> content: @escaping (Int) -> Content)
    where Data == Range<Int>, ID == Int, V == Content.TableRowValue {
        self.data = data
        self.content = content
        self.idGetter = { $0 }
    }
}
extension ForEach: _TableRowSource where Content: TableRowContent {
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        for element in data { _collectTableRows(of: content(element), depth, &out) }
    }
}

/// The header row of a `Section` inside a table.
public struct TableHeaderRowContent<Value: Identifiable, Content: View>: TableRowContent, _TableRowSource {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never
    let content: Content
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        out.append(_TableRowItem(depth: depth, header: AnyView(content)))
    }
}

extension Section: TableRowContent where Parent: TableRowContent, Content: TableRowContent, Footer: TableRowContent {
    public typealias TableRowValue = Content.TableRowValue
    public typealias TableRowBody = Never

    public init<V, H: View>(@TableRowBuilder<V> content: () -> Content, @ViewBuilder header: () -> H)
    where Parent == TableHeaderRowContent<V, H>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(header: TableHeaderRowContent(content: header()), content: content(), footer: EmptyTableRowContent())
    }
    public init<V>(_ titleKey: LocalizedStringKey, @TableRowBuilder<V> content: () -> Content)
    where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(header: TableHeaderRowContent(content: Text(titleKey)), content: content(), footer: EmptyTableRowContent())
    }
    public init<V, S: StringProtocol>(_ title: S, @TableRowBuilder<V> content: () -> Content)
    where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(header: TableHeaderRowContent(content: Text(title)), content: content(), footer: EmptyTableRowContent())
    }
    public init<V>(@TableRowBuilder<V> content: () -> Content)
    where Parent == EmptyTableRowContent<V>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(header: EmptyTableRowContent(), content: content(), footer: EmptyTableRowContent())
    }
}
extension Section: _TableRowSource where Parent: TableRowContent, Content: TableRowContent, Footer: TableRowContent {
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        _collectTableRows(of: header, depth, &out)
        _collectTableRows(of: content, depth, &out)
        _collectTableRows(of: footer, depth, &out)
    }
}

/// A row that discloses child rows. Without a binding it starts collapsed.
public struct DisclosureTableRow<Label: TableRowContent, Content: TableRowContent>: TableRowContent, _TableRowSource
where Label.TableRowValue == Content.TableRowValue {
    public typealias TableRowValue = Label.TableRowValue
    public typealias TableRowBody = Never
    let label: Label
    let content: Content
    let isExpanded: Bool

    public init<Value>(_ value: Value, isExpanded: Binding<Bool>? = nil, @TableRowBuilder<Value> content: () -> Content)
    where Label == TableRow<Value>, Value == Content.TableRowValue {
        self.label = TableRow(value)
        self.content = content()
        self.isExpanded = isExpanded?.wrappedValue ?? false
    }

    func _collectRows(depth: Int, into out: inout [_TableRowItem]) {
        var own: [_TableRowItem] = []
        _collectTableRows(of: label, depth, &own)
        for index in own.indices { own[index].expanded = isExpanded }
        out.append(contentsOf: own)
        if isExpanded { _collectTableRows(of: content, depth + 1, &out) }
    }
}

/// Row modifiers that only matter during interaction keep the rows as they are.
public struct _InertTableRowModifier<Base: TableRowContent>: TableRowContent, _TableRowSource {
    public typealias TableRowValue = Base.TableRowValue
    public typealias TableRowBody = Never
    let base: Base
    func _collectRows(depth: Int, into out: inout [_TableRowItem]) { _collectTableRows(of: base, depth, &out) }
}
public typealias ItemProviderTableRowModifier = _InertTableRowModifier

extension TableRowContent {
    public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
    public func contextMenu<M: View, P: View>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping (_ items: [T]) -> Void) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
    public func onHover(perform action: @escaping (Bool) -> Void) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
    public func itemProvider(_ action: (@Sendable () -> NSItemProvider?)?) -> ItemProviderTableRowModifier<Self> {
        _InertTableRowModifier(base: self)
    }
    public func selectionDisabled(_ isDisabled: Bool = true) -> some TableRowContent<TableRowValue> {
        _InertTableRowModifier(base: self)
    }
}

// MARK: - Column content

@MainActor @preconcurrency
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
    associatedtype TableRowValue: Identifiable = TableColumnBody.TableRowValue
    associatedtype TableColumnSortComparator: SortComparator = TableColumnBody.TableColumnSortComparator
    associatedtype TableColumnBody: TableColumnContent
    @MainActor @preconcurrency var tableColumnBody: Self.TableColumnBody { get }
}

extension Never: TableColumnContent {
    public typealias TableColumnBody = Never
    public typealias TableColumnSortComparator = Never
    public var tableColumnBody: Never { fatalError() }
}

extension TableColumnContent where TableColumnBody == Never {
    public var tableColumnBody: Never { fatalError("\(Self.self) is a primitive table column and has no body") }
}

public struct TableColumnAlignment: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case automatic, leading, center, trailing, numeric }
    let kind: Kind
    public static var automatic: TableColumnAlignment { .init(kind: .automatic) }
    public static var leading: TableColumnAlignment { .init(kind: .leading) }
    public static var center: TableColumnAlignment { .init(kind: .center) }
    public static var trailing: TableColumnAlignment { .init(kind: .trailing) }
    /// Numbers align to the trailing edge in a left-to-right layout.
    public static var numeric: TableColumnAlignment { .init(kind: .numeric) }
    public static func numeric(_ numberingSystem: Locale.NumberingSystem) -> TableColumnAlignment { .init(kind: .numeric) }

    var alignment: Alignment {
        switch kind {
        case .automatic, .leading: return .leading
        case .center: return .center
        case .trailing, .numeric: return .trailing
        }
    }
}

struct _TableColumnInfo {
    var label: AnyView
    var cell: @MainActor (Any) -> AnyView
    var minWidth: CGFloat?
    var idealWidth: CGFloat?
    var maxWidth: CGFloat?
    var fixedWidth: CGFloat?
    var alignment = TableColumnAlignment.automatic
    /// The column's comparator, for the sort indicator.
    var comparator: Any?
    var hidden = false
}

protocol _TableColumnSource {
    @MainActor func _columns() -> [_TableColumnInfo]
}

@MainActor
func _tableColumns<C: TableColumnContent>(of columns: C) -> [_TableColumnInfo] {
    if let source = columns as? _TableColumnSource { return source._columns() }
    if C.TableColumnBody.self != Never.self { return _tableColumns(of: columns.tableColumnBody) }
    return []
}

public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: View, Label: View>: TableColumnContent, _TableColumnSource {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never
    var info: _TableColumnInfo

    init(label: Label, comparator: Sort?, content: @escaping (RowValue) -> Content) {
        info = _TableColumnInfo(label: AnyView(label), cell: { value in
            guard let row = value as? RowValue else { return AnyView(EmptyView()) }
            return AnyView(content(row))
        }, comparator: comparator)
    }

    func _columns() -> [_TableColumnInfo] { [info] }

    /// A fixed width, or (with no argument) the column's ideal width.
    public func width(_ fixed: CGFloat? = nil) -> TableColumn<RowValue, Sort, Content, Label> {
        var copy = self
        copy.info.fixedWidth = fixed
        copy.info.minWidth = nil
        copy.info.idealWidth = nil
        copy.info.maxWidth = nil
        return copy
    }
    public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn<RowValue, Sort, Content, Label> {
        var copy = self
        copy.info.fixedWidth = nil
        copy.info.minWidth = min
        copy.info.idealWidth = ideal
        copy.info.maxWidth = max
        return copy
    }
}

// Unsortable columns.
extension TableColumn where Sort == Never, Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(titleKey), comparator: nil, content: content)
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(title), comparator: nil, content: content)
    }
    public init(_ text: Text, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: text, comparator: nil, content: content)
    }
}
extension TableColumn where Sort == Never, Content == Text, Label == Text {
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) {
        self.init(label: Text(titleKey), comparator: nil) { Text(verbatim: $0[keyPath: value]) }
    }
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) {
        self.init(label: Text(title), comparator: nil) { Text(verbatim: $0[keyPath: value]) }
    }
    public init(_ text: Text, value: KeyPath<RowValue, String>) {
        self.init(label: text, comparator: nil) { Text(verbatim: $0[keyPath: value]) }
    }
}

/// Foundation on Linux only has the lexical string comparator. Sortable tables name the localized ones
/// (they are the default of `TableColumn(_:value:)`), so they exist here and order lexically.
extension String.StandardComparator {
    public static var localizedStandard: String.StandardComparator { .lexical }
    public static var localized: String.StandardComparator { .lexical }
}

// Columns sortable by a key path.
extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
    public init<V: Comparable>(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(titleKey), comparator: KeyPathComparator(value), content: content)
    }
    public init<S: StringProtocol, V: Comparable>(_ title: S, value: KeyPath<RowValue, V>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(title), comparator: KeyPathComparator(value), content: content)
    }
    public init<V: Comparable>(_ text: Text, value: KeyPath<RowValue, V>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: text, comparator: KeyPathComparator(value), content: content)
    }
    public init<V: Comparable>(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V?>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(titleKey), comparator: KeyPathComparator(value), content: content)
    }
    public init<S: StringProtocol, V: Comparable>(_ title: S, value: KeyPath<RowValue, V?>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(title), comparator: KeyPathComparator(value), content: content)
    }
    public init<V: Comparable>(_ text: Text, value: KeyPath<RowValue, V?>, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: text, comparator: KeyPathComparator(value), content: content)
    }
    public init<V, C: SortComparator>(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V>, comparator: C,
                                      @ViewBuilder content: @escaping (RowValue) -> Content) where C.Compared == V {
        self.init(label: Text(titleKey), comparator: KeyPathComparator(value, comparator: comparator), content: content)
    }
    public init<S: StringProtocol, V, C: SortComparator>(_ title: S, value: KeyPath<RowValue, V>, comparator: C,
                                                         @ViewBuilder content: @escaping (RowValue) -> Content) where C.Compared == V {
        self.init(label: Text(title), comparator: KeyPathComparator(value, comparator: comparator), content: content)
    }
    public init<V, C: SortComparator>(_ text: Text, value: KeyPath<RowValue, V>, comparator: C,
                                      @ViewBuilder content: @escaping (RowValue) -> Content) where C.Compared == V {
        self.init(label: text, comparator: KeyPathComparator(value, comparator: comparator), content: content)
    }
}
extension TableColumn where Sort == KeyPathComparator<RowValue>, Content == Text, Label == Text {
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>, comparator: String.StandardComparator = .localizedStandard) {
        self.init(label: Text(titleKey), comparator: KeyPathComparator(value, comparator: comparator)) { Text(verbatim: $0[keyPath: value]) }
    }
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>, comparator: String.StandardComparator = .localizedStandard) {
        self.init(label: Text(title), comparator: KeyPathComparator(value, comparator: comparator)) { Text(verbatim: $0[keyPath: value]) }
    }
    public init(_ text: Text, value: KeyPath<RowValue, String>, comparator: String.StandardComparator = .localizedStandard) {
        self.init(label: text, comparator: KeyPathComparator(value, comparator: comparator)) { Text(verbatim: $0[keyPath: value]) }
    }
}

// Columns sortable by any comparator.
extension TableColumn where Label == Text {
    public init(_ titleKey: LocalizedStringKey, sortUsing comparator: Sort, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(titleKey), comparator: comparator, content: content)
    }
    public init<S: StringProtocol>(_ title: S, sortUsing comparator: Sort, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: Text(title), comparator: comparator, content: content)
    }
    public init(_ text: Text, sortUsing comparator: Sort, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(label: text, comparator: comparator, content: content)
    }
}

public struct TupleTableColumnContent<RowValue: Identifiable, Sort: SortComparator, T>: TableColumnContent, _TableColumnSource {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never
    public let value: T
    let collect: @MainActor () -> [_TableColumnInfo]
    init(value: T, collect: @escaping @MainActor () -> [_TableColumnInfo]) {
        self.value = value
        self.collect = collect
    }
    func _columns() -> [_TableColumnInfo] { collect() }
}

public struct _ConditionalTableColumnContent<TrueContent: TableColumnContent, FalseContent: TableColumnContent>: TableColumnContent, _TableColumnSource
where TrueContent.TableRowValue == FalseContent.TableRowValue, TrueContent.TableColumnSortComparator == FalseContent.TableColumnSortComparator {
    public typealias TableRowValue = TrueContent.TableRowValue
    public typealias TableColumnSortComparator = TrueContent.TableColumnSortComparator
    public typealias TableColumnBody = Never
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    func _columns() -> [_TableColumnInfo] {
        switch storage {
        case .first(let columns): return _tableColumns(of: columns)
        case .second(let columns): return _tableColumns(of: columns)
        }
    }
}

extension Optional: TableColumnContent where Wrapped: TableColumnContent {
    public typealias TableRowValue = Wrapped.TableRowValue
    public typealias TableColumnSortComparator = Wrapped.TableColumnSortComparator
    public typealias TableColumnBody = Never
}
extension Optional: _TableColumnSource where Wrapped: TableColumnContent {
    func _columns() -> [_TableColumnInfo] { map { _tableColumns(of: $0) } ?? [] }
}

public struct TableColumnForEach<Data: RandomAccessCollection, ID: Hashable, RowValue, Sort, Content: TableColumnContent>: TableColumnContent, _TableColumnSource
where RowValue == Content.TableRowValue, Sort == Content.TableColumnSortComparator {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never
    public var data: Data
    public var content: (Data.Element) -> Content

    public init(_ data: Data, @TableColumnBuilder<RowValue, Sort> content: @escaping (Data.Element) -> Content)
    where ID == Data.Element.ID, Data.Element: Identifiable {
        self.data = data
        self.content = content
    }
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @TableColumnBuilder<RowValue, Sort> content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }
    public init(_ data: Range<Int>, @TableColumnBuilder<RowValue, Sort> content: @escaping (Int) -> Content) where Data == Range<Int>, ID == Int {
        self.data = data
        self.content = content
    }
    func _columns() -> [_TableColumnInfo] { data.flatMap { _tableColumns(of: content($0)) } }
}

public struct _ModifiedTableColumn<Base: TableColumnContent>: TableColumnContent, _TableColumnSource {
    public typealias TableRowValue = Base.TableRowValue
    public typealias TableColumnSortComparator = Base.TableColumnSortComparator
    public typealias TableColumnBody = Never
    let base: Base
    let change: (inout _TableColumnInfo) -> Void
    func _columns() -> [_TableColumnInfo] {
        var columns = _tableColumns(of: base)
        for index in columns.indices { change(&columns[index]) }
        return columns
    }
}

public struct TableColumnCustomizationBehavior: SetAlgebra, Sendable {
    var raw: Int
    public init() { raw = 0 }
    init(raw: Int) { self.raw = raw }
    public static var all: TableColumnCustomizationBehavior { .init(raw: 7) }
    public static var reorder: TableColumnCustomizationBehavior { .init(raw: 1) }
    public static var resize: TableColumnCustomizationBehavior { .init(raw: 2) }
    public static var visibility: TableColumnCustomizationBehavior { .init(raw: 4) }
    public var isEmpty: Bool { raw == 0 }
    public func contains(_ member: TableColumnCustomizationBehavior) -> Bool { raw & member.raw == member.raw }
    public func union(_ other: TableColumnCustomizationBehavior) -> TableColumnCustomizationBehavior { .init(raw: raw | other.raw) }
    public func intersection(_ other: TableColumnCustomizationBehavior) -> TableColumnCustomizationBehavior { .init(raw: raw & other.raw) }
    public func symmetricDifference(_ other: TableColumnCustomizationBehavior) -> TableColumnCustomizationBehavior { .init(raw: raw ^ other.raw) }
    public mutating func formUnion(_ other: TableColumnCustomizationBehavior) { raw |= other.raw }
    public mutating func formIntersection(_ other: TableColumnCustomizationBehavior) { raw &= other.raw }
    public mutating func formSymmetricDifference(_ other: TableColumnCustomizationBehavior) { raw ^= other.raw }
    @discardableResult public mutating func insert(_ member: TableColumnCustomizationBehavior) -> (inserted: Bool, memberAfterInsert: TableColumnCustomizationBehavior) {
        let had = contains(member)
        raw |= member.raw
        return (!had, member)
    }
    @discardableResult public mutating func remove(_ member: TableColumnCustomizationBehavior) -> TableColumnCustomizationBehavior? {
        let had = contains(member)
        raw &= ~member.raw
        return had ? member : nil
    }
    @discardableResult public mutating func update(with member: TableColumnCustomizationBehavior) -> TableColumnCustomizationBehavior? {
        let had = contains(member)
        raw |= member.raw
        return had ? member : nil
    }
}

extension TableColumnContent {
    public func alignment(_ alignment: TableColumnAlignment) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumn(base: self) { $0.alignment = alignment }
    }
    /// Customization is stored per column id; nothing is stored between renders, so columns keep their declared state.
    public func customizationID(_ id: String) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumn(base: self) { _ in }
    }
    public func defaultVisibility(_ visibility: Visibility) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumn(base: self) { $0.hidden = visibility == .hidden }
    }
    public func disabledCustomizationBehavior(_ behavior: TableColumnCustomizationBehavior) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumn(base: self) { _ in }
    }
}

public struct TableColumnCustomization<RowValue: Identifiable>: Equatable, Sendable, Codable {
    var visibilities: [String: Bool] = [:]
    public init() {}
    public mutating func resetOrder() {}
    public subscript(visibility id: String) -> Visibility {
        get { visibilities[id].map { $0 ? .visible : .hidden } ?? .automatic }
        set { visibilities[id] = newValue == .automatic ? nil : newValue == .visible }
    }
}

// MARK: - Style

public struct TableStyleConfiguration {
    init() {}
}

@MainActor @preconcurrency
public protocol TableStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = TableStyleConfiguration
}

public struct AutomaticTableStyle: TableStyle {
    public init() {}
    public func makeBody(configuration: TableStyleConfiguration) -> some View { EmptyView() }
}
public struct InsetTableStyle: TableStyle {
    var alternates = false
    public init() {}
    public init(alternatesRowBackgrounds: Bool) { alternates = alternatesRowBackgrounds }
    public func makeBody(configuration: TableStyleConfiguration) -> some View { EmptyView() }
}
/// macOS: a table with a border around it.
public struct BorderedTableStyle: TableStyle {
    var alternates = false
    public init() {}
    public init(alternatesRowBackgrounds: Bool) { alternates = alternatesRowBackgrounds }
    public func makeBody(configuration: TableStyleConfiguration) -> some View { EmptyView() }
}
extension TableStyle where Self == AutomaticTableStyle {
    public static var automatic: AutomaticTableStyle { AutomaticTableStyle() }
}
extension TableStyle where Self == InsetTableStyle {
    public static var inset: InsetTableStyle { InsetTableStyle() }
    public static func inset(alternatesRowBackgrounds: Bool) -> InsetTableStyle { InsetTableStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}
extension TableStyle where Self == BorderedTableStyle {
    public static var bordered: BorderedTableStyle { BorderedTableStyle() }
    public static func bordered(alternatesRowBackgrounds: Bool) -> BorderedTableStyle { BorderedTableStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

struct _TableLook: Equatable {
    var bordered = false
    var alternates = false
    var headers = Visibility.automatic
}
enum TableLookKey: EnvironmentKey { static let defaultValue = _TableLook() }

extension View {
    public func tableStyle<S: TableStyle>(_ style: S) -> some View {
        env {
            switch style {
            case let inset as InsetTableStyle:
                $0[TableLookKey.self].bordered = false
                $0[TableLookKey.self].alternates = inset.alternates
            case let bordered as BorderedTableStyle:
                $0[TableLookKey.self].bordered = true
                $0[TableLookKey.self].alternates = bordered.alternates
            case is AutomaticTableStyle:
                $0[TableLookKey.self].bordered = false
                $0[TableLookKey.self].alternates = false
            default:
                Runtime.current?.warn("a custom TableStyle is ignored: the table draws with the automatic style")
            }
        }
    }
    public func tableColumnHeaders(_ visibility: Visibility) -> some View {
        env { $0[TableLookKey.self].headers = visibility }
    }
}

// MARK: - Table

public struct Table<Value, Rows: TableRowContent, Columns: TableColumnContent>: View, PrimitiveView
where Value == Rows.TableRowValue, Rows.TableRowValue == Columns.TableRowValue {
    public typealias Body = Never
    private let _tvOSCheck = tvOSUnavailable("Table")
    let rows: Rows
    let columns: Columns
    /// Ids of the selected rows.
    var selected: Set<AnyHashable> = []
    /// For a column's comparator: the direction it currently sorts in, when it is the primary sort.
    var activeOrder: (Any) -> SortOrder? = { _ in nil }

    init(rows: Rows, columns: Columns) {
        self.rows = rows
        self.columns = columns
    }

    mutating func select(_ id: Value.ID?) { if let id { selected = [AnyHashable(id)] } }
    mutating func select(_ ids: Set<Value.ID>) { selected = Set(ids.map { AnyHashable($0) }) }
    mutating func sort<Sort: SortComparator>(_ order: [Sort]) {
        guard let primary = order.first else { return }
        activeOrder = { comparator in
            guard var candidate = comparator as? Sort else { return nil }
            candidate.order = primary.order
            return candidate == primary ? primary.order : nil
        }
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let columnInfos = _tableColumns(of: columns).filter { !$0.hidden }
        var items: [_TableRowItem] = []
        _collectTableRows(of: rows, 0, &items)
        let look = ctx.env[TableLookKey.self]
        let view: AnyView
        if ctx.env.horizontalSizeClass == .compact {
            view = AnyView(_CompactTable(columns: columnInfos, items: items))
        } else {
            view = AnyView(_RegularTable(columns: columnInfos, items: items, selected: selected, activeOrder: activeOrder, look: look))
        }
        resolveView(view, ctx.child("table"), into: &out)
    }
}

// Rows from a collection.
extension Table {
    public init<Data: RandomAccessCollection>(_ data: Data, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
}

// Rows from a collection, with customizable columns.
extension Table {
    public init<Data: RandomAccessCollection>(_ data: Data, columnCustomization: Binding<TableColumnCustomization<Value>>,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Set<Value.ID>>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, sortOrder: Binding<[Sort]>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
                                                    columnCustomization: Binding<TableColumnCustomization<Value>>,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
                                                    columnCustomization: Binding<TableColumnCustomization<Value>>,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableForEachContent(data: data), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
}

// Rows from a row builder.
extension Table {
    public init(of valueType: Value.Type, @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
    }
    public init(of valueType: Value.Type, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> Columns,
                @TableRowBuilder<Value> rows: () -> Rows) where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> Columns,
                @TableRowBuilder<Value> rows: () -> Rows) where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns,
                      @TableRowBuilder<Value> rows: () -> Rows) where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
                      @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
                      @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init(of valueType: Value.Type, columnCustomization: Binding<TableColumnCustomization<Value>>,
                @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
    }
    public init(of valueType: Value.Type, selection: Binding<Value.ID?>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, sortOrder: Binding<[Sort]>, columnCustomization: Binding<TableColumnCustomization<Value>>,
                      @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
                      columnCustomization: Binding<TableColumnCustomization<Value>>,
                      @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
                      columnCustomization: Binding<TableColumnCustomization<Value>>,
                      @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }

    // The row value is inferred from the builders.
    public init(@TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
    }
    public init(selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init(selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Never {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Sort>(sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns, @TableRowBuilder<Value> rows: () -> Rows)
    where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns,
                      @TableRowBuilder<Value> rows: () -> Rows) where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Sort>(selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns,
                      @TableRowBuilder<Value> rows: () -> Rows) where Columns.TableColumnSortComparator == Sort {
        self.init(rows: rows(), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
}

// Hierarchical rows.
extension Table {
    public init<Data: RandomAccessCollection>(_ data: Data, children: KeyPath<Value, Data?>,
                                              columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
    }
    public init<Data: RandomAccessCollection>(_ data: Data, children: KeyPath<Value, Data?>, selection: Binding<Value.ID?>,
                                              columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection>(_ data: Data, children: KeyPath<Value, Data?>, selection: Binding<Set<Value.ID>>,
                                              columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
        select(selection.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, children: KeyPath<Value, Data?>, sortOrder: Binding<[Sort]>,
                                                    columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, children: KeyPath<Value, Data?>, selection: Binding<Value.ID?>,
                                                    sortOrder: Binding<[Sort]>,
                                                    columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
    public init<Data: RandomAccessCollection, Sort>(_ data: Data, children: KeyPath<Value, Data?>, selection: Binding<Set<Value.ID>>,
                                                    sortOrder: Binding<[Sort]>,
                                                    columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableOutlineGroupContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Sort {
        self.init(rows: TableOutlineGroupContent(data: data, children: children), columns: columns())
        select(selection.wrappedValue)
        sort(sortOrder.wrappedValue)
    }
}

// MARK: - Drawing

/// iPhone: a plain list of the first column's cells. No headers, no other columns.
struct _CompactTable: View {
    let columns: [_TableColumnInfo]
    let items: [_TableRowItem]
    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                if let header = pair.element.header {
                    header.font(.headline)
                } else if let value = pair.element.value, let first = columns.first {
                    HStack(spacing: 8) {
                        first.cell(value)
                        if let expanded = pair.element.expanded {
                            Spacer(minLength: 8)
                            Chevron(direction: expanded ? .down : .right, width: 7, height: 12, weight: 2, color: AnyShapeStyle(Color(SystemColor.tertiaryLabel)))
                        }
                    }
                    .padding(.leading, CGFloat(pair.element.depth) * 20)
                }
            }
        }
        .listStyle(.plain)
    }
}

/// iPad and macOS: a header row, then one row per value with a cell per column (metrics est. from iPadOS).
struct _RegularTable: View {
    let columns: [_TableColumnInfo]
    let items: [_TableRowItem]
    let selected: Set<AnyHashable>
    let activeOrder: (Any) -> SortOrder?
    let look: _TableLook

    private static let rowHeight: CGFloat = 44
    private static let headerHeight: CGFloat = 32
    private static let margin: CGFloat = 20
    private static let columnSpacing: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            if look.headers != .hidden {
                row { index, column in
                    HStack(spacing: 4) {
                        column.label.lineLimit(1)
                        if let comparator = column.comparator, let order = activeOrder(comparator) {
                            Chevron(direction: order == .forward ? .up : .down, width: 4, height: 8, weight: 1.6, color: AnyShapeStyle(Color(SystemColor.secondaryLabel)))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(height: Self.headerHeight)
                Rectangle().fill(Color(SystemColor.separator)).frame(height: 0.5)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { pair in
                        rowView(pair.element, index: pair.offset)
                    }
                }
            }
        }
        .overlay(look.bordered ? AnyView(Rectangle().stroke(Color(SystemColor.separator), lineWidth: 1)) : AnyView(EmptyView()))
    }

    @ViewBuilder private func rowView(_ item: _TableRowItem, index: Int) -> some View {
        let isSelected = item.id.map { selected.contains($0) } ?? false
        VStack(spacing: 0) {
            if let header = item.header {
                header.font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.margin)
                    .frame(minHeight: Self.rowHeight)
            } else if let value = item.value {
                row { columnIndex, column in
                    HStack(spacing: 6) {
                        if columnIndex == 0, let expanded = item.expanded {
                            Chevron(direction: expanded ? .down : .right, width: 6, height: 10, weight: 2, color: AnyShapeStyle(Color(SystemColor.secondaryLabel)))
                                .frame(width: 12)
                        }
                        column.cell(value)
                            .foregroundStyle(columnIndex == 0 ? AnyShapeStyle(Color(SystemColor.label)) : AnyShapeStyle(Color(SystemColor.secondaryLabel)))
                    }
                    .padding(.leading, columnIndex == 0 ? CGFloat(item.depth) * 20 : 0)
                }
                .frame(minHeight: Self.rowHeight)
                .background(rowBackground(index: index, selected: isSelected))
            }
            Rectangle().fill(Color(SystemColor.separator)).frame(height: 0.5).padding(.leading, Self.margin)
        }
    }

    private func rowBackground(index: Int, selected: Bool) -> Color {
        if selected { return Color(SystemColor.gray4) }
        if look.alternates && index % 2 == 1 { return Color(SystemColor.quaternaryFill) }
        return Color.clear
    }

    /// One horizontal run of column slots, shared by the header and the rows so they line up.
    private func row<Cell: View>(@ViewBuilder cell: @escaping (Int, _TableColumnInfo) -> Cell) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { pair in
                slot(pair.element, cell(pair.offset, pair.element))
            }
        }
        .padding(.horizontal, Self.margin)
    }

    @ViewBuilder private func slot<Cell: View>(_ column: _TableColumnInfo, _ cell: Cell) -> some View {
        let alignment = column.alignment.alignment
        if let fixed = column.fixedWidth {
            cell.frame(width: fixed, alignment: alignment)
        } else if column.minWidth != nil || column.idealWidth != nil || column.maxWidth != nil {
            cell.frame(minWidth: column.minWidth, idealWidth: column.idealWidth, maxWidth: column.maxWidth ?? .infinity, alignment: alignment)
        } else {
            cell.frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}
