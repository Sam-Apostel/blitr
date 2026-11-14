import SwiftUI

#Preview {
    TabView {
        Tab("Home", systemImage: "house") {
            NavigationStack {
                Text("Short content").navigationTitle("Home")
            }
        }
        .badge(2)
        Tab("Settings", systemImage: "gear") { Text("Settings") }
    }
}
