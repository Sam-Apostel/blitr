import SwiftUI

// move(fromOffsets:toOffset:) and remove(atOffsets:) change the data, as onMove/onDelete handlers do.

struct EditingDataExample: View {
    @State private var fruits = ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig"]
    @State private var scores: ArraySlice<Int> = [10, 20, 30, 40]

    var body: some View {
        List {
            Section("After moving Apple and Cherry to the end, and deleting Fig") {
                ForEach(fruits, id: \.self) { Text($0) }
                    .onMove { fruits.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { fruits.remove(atOffsets: $0) }
                    .onInsert(of: [.text]) { _, _ in }
            }
            Section("ArraySlice: 40 moved to the front, 20 removed") {
                ForEach(Array(scores), id: \.self) { Text("\($0)") }
                    .onDelete(perform: delete)
                    .onMove(perform: nil)
            }
        }
        .onAppear {
            fruits.move(fromOffsets: IndexSet([0, 2]), toOffset: fruits.count)
            fruits.remove(atOffsets: IndexSet(integer: fruits.firstIndex(of: "Fig")!))
            scores.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
            scores.remove(atOffsets: IndexSet(integer: 2))
        }
    }

    private func delete(at offsets: IndexSet) { fruits.remove(atOffsets: offsets) }
}

#Preview("Editing data") {
    EditingDataExample()
}
