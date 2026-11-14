import SwiftUI

// Liquid Glass tab bars and presentations (render with --ios 26 or --ios 27; --ios 18 shows the older look).

/// A colourful scrolling feed, so the glass has something to refract.
struct ColorfulFeed: View {
    let title: String
    private let colors: [Color] = [.pink, .orange, .yellow, .green, .teal, .blue, .indigo, .purple]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<14) { i in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(colors: [colors[i % colors.count], colors[(i + 3) % colors.count]],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 120)
                            .overlay(alignment: .bottomLeading) {
                                Text("Card \(i + 1)").font(.title2.bold()).foregroundStyle(.white).padding()
                            }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(title)
        }
    }
}

struct FiveTabs: View {
    @State private var selection = 2
    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: 0) { ColorfulFeed(title: "Home") }
            Tab("Explore", systemImage: "safari", value: 1) { ColorfulFeed(title: "Explore") }
            Tab("Library", systemImage: "square.stack", value: 2) { ColorfulFeed(title: "Library") }
                .badge(3)
            Tab("Inbox", systemImage: "tray", value: 3) { ColorfulFeed(title: "Inbox") }
            Tab("Account", systemImage: "person.crop.circle", value: 4) { ColorfulFeed(title: "Account") }
        }
    }
}

struct SearchTabWithAccessory: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            Tab("Listen Now", systemImage: "play.circle", value: 0) { ColorfulFeed(title: "Listen Now") }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: 1) { ColorfulFeed(title: "Radio") }
            Tab("Library", systemImage: "square.stack", value: 2) { ColorfulFeed(title: "Library") }
            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) { ColorfulFeed(title: "Search") }
        }
        .tabViewBottomAccessory {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(.orange.gradient).frame(width: 32, height: 32)
                Text("Now Playing").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "play.fill")
                Image(systemName: "forward.fill")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct MediumSheet: View {
    var body: some View {
        ColorfulFeed(title: "Photos")
            .sheet(isPresented: .constant(true)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Share Album").font(.title2.bold())
                    Text("Invite people to view and add photos to this album.").foregroundStyle(.secondary)
                    Button("Copy Link") {}.buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .presentationDetents([.medium, .large])
            }
    }
}

struct TwoButtonAlert: View {
    var body: some View {
        ColorfulFeed(title: "Photos")
            .alert("Delete Photo?", isPresented: .constant(true)) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {}
            } message: {
                Text("This photo will be deleted from all your devices.")
            }
    }
}

struct ThreeButtonAlert: View {
    var body: some View {
        ColorfulFeed(title: "Notes")
            .alert("Save changes?", isPresented: .constant(true)) {
                Button("Save") {}
                Button("Don't Save", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your changes will be lost if you don't save them.")
            }
    }
}

struct Dialog: View {
    var body: some View {
        ColorfulFeed(title: "Files")
            .confirmationDialog("Move to Trash?", isPresented: .constant(true), titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) {}
                Button("Duplicate") {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can restore it from Recently Deleted.")
            }
    }
}

#Preview("Tabs") { FiveTabs() }
#Preview("Search tab and accessory") { SearchTabWithAccessory() }
#Preview("Medium sheet") { MediumSheet() }
#Preview("Two-button alert") { TwoButtonAlert() }
#Preview("Three-button alert") { ThreeButtonAlert() }
#Preview("Confirmation dialog") { Dialog() }
