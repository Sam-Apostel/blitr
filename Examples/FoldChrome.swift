import SwiftUI

// The system chrome on a foldable: render with --device iphone-duo-half-open (bent like a book) and
// iphone-duo-open (flat) to see where the tab bar, the bar's buttons and full-bleed content go.

struct FoldHeader: View {
    var body: some View {
        LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            .frame(height: 220)
            .overlay(alignment: .bottomLeading) {
                Text("Harbour day").font(.largeTitle.bold()).foregroundStyle(.white).padding(20)
            }
    }
}

struct FoldPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FoldHeader()
                ForEach(1...10, id: \.self) { i in
                    HStack {
                        Text("Stop \(i)").font(.headline)
                        Spacer()
                        Text("\(8 + i):00").monospacedDigit()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    Divider().padding(.leading, 20)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {} label: { Label("Back", systemImage: "chevron.left") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {} label: { Label("Map", systemImage: "map") }
                Menu {
                    Button("Edit") {}
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }
}

struct FoldTabs: View {
    var body: some View {
        TabView(selection: .constant(1)) {
            Tab("Now", systemImage: "sunrise", value: 0) { NavigationStack { FoldPage() } }
            Tab("Days", systemImage: "calendar", value: 1) { NavigationStack { FoldPage() } }
            Tab("Map", systemImage: "map", value: 2) { NavigationStack { FoldPage() } }
            Tab("Journal", systemImage: "book", value: 3) { NavigationStack { FoldPage() } }
            Tab("Plan", systemImage: "list.clipboard", value: 4) { NavigationStack { FoldPage() } }
        }
    }
}

struct FoldTitled: View {
    var body: some View {
        TabView {
            Tab("Days", systemImage: "calendar") {
                NavigationStack {
                    List(1...12, id: \.self) { i in Text("Day \(i)") }
                        .navigationTitle("Ten days")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {} label: { Label("Add", systemImage: "plus") }
                            }
                        }
                }
            }
            Tab("Plan", systemImage: "list.clipboard") { Text("Plan") }
        }
    }
}

/// Two pages side by side, as an app lays out a fold bent open: a list on the leading page with a custom
/// item in its bar, a page with a full-bleed photo on the trailing one, whose buttons come from two toolbars.
struct FoldTwoPages: View {
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                NavigationStack {
                    List(1...12, id: \.self) { i in Text("Day \(i)") }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                HStack(spacing: 6) {
                                    Text("Trip").font(.headline)
                                    Image(systemName: "chevron.down").font(.caption.bold())
                                }
                                .padding(.horizontal, 14).frame(height: 44)
                            }
                        }
                        .ignoresSafeArea(.container, edges: .trailing)
                }
                .frame(width: proxy.size.width / 2 + proxy.safeAreaInsets.trailing / 2)
                NavigationStack {
                    FoldPage()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {} label: { Label("Settings", systemImage: "slider.horizontal.3") }
                            }
                            if #available(iOS 26, *) {
                                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {} label: { Label("Account", systemImage: "person.crop.circle") }
                            }
                        }
                }
            }
        }
    }
}

#Preview("Tabs") {
    FoldTabs()
}

#Preview("No tabs") {
    NavigationStack { FoldPage() }
}

#Preview("Large title") {
    FoldTitled()
}

#Preview("Two pages") {
    FoldTwoPages()
}
