import SwiftUI

struct SearchScreen: View {
    @State private var query = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ForEach(["Apples", "Bananas", "Cherries"], id: \.self) { Text($0).padding(.vertical, 6) }
                Spacer()
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Fruit")
            .searchable(text: $query, prompt: "Search fruit")
        }
    }
}

#Preview { SearchScreen() }
