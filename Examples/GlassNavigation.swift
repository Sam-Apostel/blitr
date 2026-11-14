import SwiftUI

// Liquid Glass navigation bars, toolbars and search (render with --ios 26 or --ios 27).

struct Swatches: View {
    let colors: [Color] = [.pink, .orange, .yellow, .green, .teal, .blue, .indigo, .purple]
    var body: some View {
        LinearGradient(colors: [.purple, .pink, .orange, .yellow, .green, .teal, .blue],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                VStack(spacing: 0) {
                    ForEach(0..<14) { i in
                        HStack(spacing: 0) {
                            ForEach(0..<8) { j in
                                colors[(i + j) % colors.count].opacity((i + j) % 3 == 0 ? 0.9 : 0.25)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
    }
}

struct Album: Hashable { let name: String }

struct GlassNavigationDemo: View {
    @State private var query = ""
    @State private var path: [Album]
    init(pushed: Bool = false) { _path = State(initialValue: pushed ? [Album(name: "Summer")] : []) }

    var body: some View {
        NavigationStack(path: $path) {
            Swatches()
                .navigationTitle("Library")
                .navigationSubtitle("128 albums")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") {} }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { } label: { Image(systemName: "square.and.arrow.up") }
                        Button { } label: { Image(systemName: "heart") }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button { } label: { Image(systemName: "line.3.horizontal.decrease") }
                    }
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button { } label: { Image(systemName: "square.and.pencil") }
                    }
                }
                .searchable(text: $query, prompt: "Albums")
                .navigationDestination(for: Album.self) { album in
                    Swatches()
                        .navigationTitle(album.name)
                        .navigationSubtitle("24 photos")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button { } label: { Image(systemName: "heart") }
                                Menu { Button("Delete") {} } label: { Image(systemName: "ellipsis") }
                            }
                            ToolbarItemGroup(placement: .bottomBar) {
                                Button { } label: { Image(systemName: "square.and.arrow.up") }
                                Spacer()
                                Button { } label: { Image(systemName: "info.circle") }
                                Button { } label: { Image(systemName: "trash") }
                            }
                        }
                }
        }
    }
}

struct GlassEditor: View {
    @State private var name = "Trip"
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Toggle("Shared", isOn: .constant(true))
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) {} }
                ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) {} }
            }
        }
    }
}

struct GlassTextItems: View {
    var body: some View {
        NavigationStack {
            Swatches()
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
                    ToolbarItem(placement: .bottomBar) { Button("Select All") {} }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { Button { } label: { Image(systemName: "folder") } }
                    ToolbarItem(placement: .bottomBar) { Button { } label: { Image(systemName: "trash") }.tint(.red) }
                }
        }
    }
}

#Preview("Large title") { GlassNavigationDemo() }
#Preview("Pushed") { GlassNavigationDemo(pushed: true) }
#Preview("Confirm and cancel") { GlassEditor() }
#Preview("Text items") { GlassTextItems() }
