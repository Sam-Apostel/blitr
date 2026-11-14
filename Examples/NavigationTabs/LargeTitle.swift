import SwiftUI

#Preview {
    NavigationStack {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hello, navigation").font(.title2)
            Text("Body text under a large title.").foregroundStyle(.secondary)
            NavigationLink("Open details", value: 3)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
            }
        }
    }
}
