import SwiftUI

struct Misc: View {
    @State private var sel = "b"
    var body: some View {
        TabView(selection: $sel) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Deprecated APIs")
                    NavigationLink(destination: Text("x")) { Text("Plain link") }
                }
                .navigationBarTitle("Old Style", displayMode: .inline)
                .navigationBarItems(leading: Text("Edit").foregroundColor(.accentColor),
                                    trailing: Text("Add").foregroundColor(.accentColor))
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) { Text("More") }
                }
            }
            .tabItem { Label0(title: "Old", icon: "clock") }
            .tag("a")
            NavigationSplitView {
                Color.mint.opacity(0.2)
                    .ignoresSafeArea()
                    .navigationTitle("Split Sidebar With A Very Long Title That Truncates")
                    .toolbar(.visible, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
            } detail: {
                Text("Detail")
            }
            .tabItem { Label0(title: "Split", icon: "sidebar.left") }
            .tag("b")
        }
        .tint(.orange)
    }
}

struct Label0: View {
    let title: String
    let icon: String
    var body: some View {
        Image(systemName: icon)
        Text(title)
    }
}

#Preview { Misc() }
