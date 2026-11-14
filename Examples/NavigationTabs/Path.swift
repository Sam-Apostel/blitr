import SwiftUI

struct Item: Hashable { let name: String }

#Preview {
    NavigationStack(path: .constant([Item(name: "Detail")])) {
        Text("Root")
            .navigationTitle("Settings")
            .navigationDestination(for: Item.self) { item in
                Text("Pushed \(item.name)")
                    .navigationTitle(item.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Text("Edit").foregroundStyle(.tint) }
            }
    }
}
