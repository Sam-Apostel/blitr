// The collection helpers SwiftUI adds for `onMove` and `onDelete`. They change the data for real.
import Foundation

extension MutableCollection {
    /// Moves the elements at `source` so they sit, in order, before the element that was at `destination`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let elements = Array(self)
        guard !source.isEmpty, let last = source.last, last < elements.count, destination >= 0, destination <= elements.count else { return }
        var reordered: [Element] = []
        reordered.reserveCapacity(elements.count)
        for (offset, element) in elements.enumerated() where offset < destination && !source.contains(offset) { reordered.append(element) }
        for offset in source { reordered.append(elements[offset]) }
        for (offset, element) in elements.enumerated() where offset >= destination && !source.contains(offset) { reordered.append(element) }
        var index = startIndex
        for element in reordered {
            self[index] = element
            formIndex(after: &index)
        }
    }
}

extension RangeReplaceableCollection where Self: MutableCollection {
    /// Removes the elements at `offsets` (positions from the start, as `onDelete` reports them).
    public mutating func remove(atOffsets offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        var kept = Self()
        for (offset, element) in enumerated() where !offsets.contains(offset) { kept.append(element) }
        self = kept
    }
}

extension DynamicViewContent {
    public func onInsert(of supportedContentTypes: [UTType], perform action: @escaping (Int, [NSItemProvider]) -> Void) -> some DynamicViewContent { self }
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping ([T], Int) -> Void) -> some DynamicViewContent { self }
}
