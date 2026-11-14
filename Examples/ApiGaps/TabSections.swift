import SwiftUI

// The iOS 18 Tab API: TabSection, tabs with values and roles, sidebar header/footer/bottom bar and
// customization. On an iPhone the sections are flattened into the tab bar; the sidebar is not shown.

enum LibraryTab: Hashable {
    case home, search, albums, artists
    case playlist(Int)
}

struct Playlist: Identifiable {
    let id: Int
    let name: String
}

struct TabSectionsExample: View {
    @State private var selection: LibraryTab = .albums
    @AppStorage("tab-customization") private var customization: TabViewCustomization
    private let playlists = [Playlist(id: 1, name: "Morning")]

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: LibraryTab.home) {
                Text("Home")
            }
            .customizationID("home")
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)

            TabSection("Library") {
                Tab("Albums", systemImage: "square.stack", value: LibraryTab.albums) {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack").font(.largeTitle)
                        Text("Albums is selected")
                    }
                }
                .badge(2)
                Tab("Artists", systemImage: "music.mic", value: LibraryTab.artists) {
                    Text("Artists")
                }
                .defaultVisibility(.hidden, for: .tabBar)
                .hidden(true)
            }
            .customizationID("library")
            .defaultSectionExpansion(.expanded)

            TabSection {
                ForEach(playlists) { playlist in
                    Tab(playlist.name, systemImage: "music.note.list", value: LibraryTab.playlist(playlist.id)) {
                        Text(playlist.name)
                    }
                    .contextMenu { Button("Rename") {} }
                    .draggable(playlist.name)
                }
            } header: {
                Label("Playlists", systemImage: "music.note.list")
            }
            .sectionActions {
                Button("New Playlist", systemImage: "plus") {}
            }
            .tabPlacement(.sidebarOnly)

            Tab(value: LibraryTab.search, role: .search) {
                Text("Search")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .tabViewSidebarHeader { Text("Music").font(.title2.bold()) }
        .tabViewSidebarFooter { Text("3 playlists") }
        .tabViewSidebarBottomBar { Button("Account") {} }
        .defaultAdaptableTabBarPlacement(.tabBar)
    }
}

struct UnlabelledTabsExample: View {
    var body: some View {
        TabView {
            Tab {
                Text("First page")
            }
            Tab {
                Text("Second page")
            } label: {
                Label("Custom label", systemImage: "star")
            }
            Tab(role: .search) {
                Text("Search")
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
        }
    }
}

#Preview("Tab sections") {
    TabSectionsExample()
}

#Preview("Tabs without labels, search role") {
    UnlabelledTabsExample()
}
