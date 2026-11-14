// The Table result builders. Swift cannot yet express "every element of a pack has this associated
// type", so they spell out one buildBlock per arity up to ten, like Apple's.
import Foundation

@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator> {
    public static func buildExpression<Content: TableColumnContent>(_ content: Content) -> Content
    where Content.TableRowValue == RowValue, Content.TableColumnSortComparator == Sort { content }
    public static func buildBlock<Column: TableColumnContent>(_ column: Column) -> Column
    where Column.TableRowValue == RowValue, Column.TableColumnSortComparator == Sort { column }
    public static func buildIf<Column: TableColumnContent>(_ column: Column?) -> Column?
    where Column.TableRowValue == RowValue, Column.TableColumnSortComparator == Sort { column }
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(first column: T) -> _ConditionalTableColumnContent<T, F>
    where T.TableRowValue == RowValue, T.TableColumnSortComparator == Sort, F.TableRowValue == RowValue, F.TableColumnSortComparator == Sort {
        _ConditionalTableColumnContent(storage: .first(column))
    }
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(second column: F) -> _ConditionalTableColumnContent<T, F>
    where T.TableRowValue == RowValue, T.TableColumnSortComparator == Sort, F.TableRowValue == RowValue, F.TableColumnSortComparator == Sort {
        _ConditionalTableColumnContent(storage: .second(column))
    }
    public static func buildLimitedAvailability<Column: TableColumnContent>(_ column: Column) -> Column
    where Column.TableRowValue == RowValue, Column.TableColumnSortComparator == Sort { column }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent>(_ c0: C0, _ c1: C1) -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1)) { _tableColumns(of: c0) + _tableColumns(of: c1) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort, C5.TableRowValue == RowValue, C5.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) + _tableColumns(of: c5) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort, C5.TableRowValue == RowValue, C5.TableColumnSortComparator == Sort, C6.TableRowValue == RowValue, C6.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) + _tableColumns(of: c5) + _tableColumns(of: c6) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort, C5.TableRowValue == RowValue, C5.TableColumnSortComparator == Sort, C6.TableRowValue == RowValue, C6.TableColumnSortComparator == Sort, C7.TableRowValue == RowValue, C7.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) + _tableColumns(of: c5) + _tableColumns(of: c6) + _tableColumns(of: c7) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort, C5.TableRowValue == RowValue, C5.TableColumnSortComparator == Sort, C6.TableRowValue == RowValue, C6.TableColumnSortComparator == Sort, C7.TableRowValue == RowValue, C7.TableColumnSortComparator == Sort, C8.TableRowValue == RowValue, C8.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) + _tableColumns(of: c5) + _tableColumns(of: c6) + _tableColumns(of: c7) + _tableColumns(of: c8) }
    }

    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent, C9: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where C0.TableRowValue == RowValue, C0.TableColumnSortComparator == Sort, C1.TableRowValue == RowValue, C1.TableColumnSortComparator == Sort, C2.TableRowValue == RowValue, C2.TableColumnSortComparator == Sort, C3.TableRowValue == RowValue, C3.TableColumnSortComparator == Sort, C4.TableRowValue == RowValue, C4.TableColumnSortComparator == Sort, C5.TableRowValue == RowValue, C5.TableColumnSortComparator == Sort, C6.TableRowValue == RowValue, C6.TableColumnSortComparator == Sort, C7.TableRowValue == RowValue, C7.TableColumnSortComparator == Sort, C8.TableRowValue == RowValue, C8.TableColumnSortComparator == Sort, C9.TableRowValue == RowValue, C9.TableColumnSortComparator == Sort {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) { _tableColumns(of: c0) + _tableColumns(of: c1) + _tableColumns(of: c2) + _tableColumns(of: c3) + _tableColumns(of: c4) + _tableColumns(of: c5) + _tableColumns(of: c6) + _tableColumns(of: c7) + _tableColumns(of: c8) + _tableColumns(of: c9) }
    }

}

@resultBuilder
public struct TableRowBuilder<Value: Identifiable> {
    public static func buildExpression<Content: TableRowContent>(_ content: Content) -> Content where Content.TableRowValue == Value { content }
    public static func buildBlock<C: TableRowContent>(_ content: C) -> C where C.TableRowValue == Value { content }
    public static func buildIf<C: TableRowContent>(_ content: C?) -> C? where C.TableRowValue == Value { content }
    public static func buildEither<T: TableRowContent, F: TableRowContent>(first: T) -> _ConditionalTableRowContent<T, F>
    where T.TableRowValue == Value, F.TableRowValue == Value { _ConditionalTableRowContent(storage: .first(first)) }
    public static func buildEither<T: TableRowContent, F: TableRowContent>(second: F) -> _ConditionalTableRowContent<T, F>
    where T.TableRowValue == Value, F.TableRowValue == Value { _ConditionalTableRowContent(storage: .second(second)) }
    public static func buildLimitedAvailability<C: TableRowContent>(_ content: C) -> C where C.TableRowValue == Value { content }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent>(_ c0: C0, _ c1: C1) -> TupleTableRowContent<Value, (C0, C1)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableRowContent<Value, (C0, C1, C2)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleTableRowContent<Value, (C0, C1, C2, C3)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value, C5.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out); _collectTableRows(of: c5, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value, C5.TableRowValue == Value, C6.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out); _collectTableRows(of: c5, depth, &out); _collectTableRows(of: c6, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value, C5.TableRowValue == Value, C6.TableRowValue == Value, C7.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out); _collectTableRows(of: c5, depth, &out); _collectTableRows(of: c6, depth, &out); _collectTableRows(of: c7, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent, C8: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value, C5.TableRowValue == Value, C6.TableRowValue == Value, C7.TableRowValue == Value, C8.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out); _collectTableRows(of: c5, depth, &out); _collectTableRows(of: c6, depth, &out); _collectTableRows(of: c7, depth, &out); _collectTableRows(of: c8, depth, &out) }
    }

    public static func buildBlock<C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent, C8: TableRowContent, C9: TableRowContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where C0.TableRowValue == Value, C1.TableRowValue == Value, C2.TableRowValue == Value, C3.TableRowValue == Value, C4.TableRowValue == Value, C5.TableRowValue == Value, C6.TableRowValue == Value, C7.TableRowValue == Value, C8.TableRowValue == Value, C9.TableRowValue == Value {
        TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) { depth, out in _collectTableRows(of: c0, depth, &out); _collectTableRows(of: c1, depth, &out); _collectTableRows(of: c2, depth, &out); _collectTableRows(of: c3, depth, &out); _collectTableRows(of: c4, depth, &out); _collectTableRows(of: c5, depth, &out); _collectTableRows(of: c6, depth, &out); _collectTableRows(of: c7, depth, &out); _collectTableRows(of: c8, depth, &out); _collectTableRows(of: c9, depth, &out) }
    }

}
