import SwiftUI

struct Shell: View {
    @State private var selection = 1
    var body: some View {
        TabView(selection: $selection) {
            Text("Home").tabItem { Image(systemName: "house"); Text("Home") }.tag(0)
            NavigationStack {
                // Stand-in for a ScrollView: rows start under the title and run under the tab bar.
                Color.clear
                    .overlay(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<30) { i in
                                Text("Row \(i)").padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .navigationTitle("Listen Now")
            }
            .tabItem { Image(systemName: "play.circle"); Text("Listen Now") }.tag(1).badge(3)
            Text("Radio").tabItem { Image(systemName: "dot.radiowaves.left.and.right"); Text("Radio") }.tag(2)
            Text("Library").tabItem { Image(systemName: "square.stack"); Text("Library") }.tag(3).badge("New")
            Text("Search").tabItem { Image(systemName: "magnifyingglass"); Text("Search") }.tag(4)
        }
    }
}

#Preview { Shell() }
