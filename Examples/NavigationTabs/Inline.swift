import SwiftUI

#Preview {
    NavigationStack {
        ZStack {
            Color.yellow.opacity(0.3).ignoresSafeArea()
            Text("Inline title with items")
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { NavigationLink("Cancel", value: 1) }
            ToolbarItem(placement: .confirmationAction) { NavigationLink("Done", value: 1) }
        }
    }
}
