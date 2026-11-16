import SwiftUI

// More tvOS states, one preview each: focused `.plain` and `.borderless` buttons, a Label inside a
// button, the collapsed sidebar, a focused toolbar item, a focused segment and a segmented picker in a
// List. The first element in reading order starts focused; the presses below reach the other states.
//
//   swiftui-screenshot render Examples/TVControlsMore.swift --device apple-tv --all --out-dir out
//
//   ... --preview "Plain Buttons" --press right           focus the plain artwork button
//   ... --preview "Plain Buttons" --press right,right     focus the plain text button
//   ... --preview "Plain Buttons" --press right,right,right   focus the borderless text button
//   ... --preview "Plain Buttons" --press right,right,right,right   focus the borderless image button
//   ... --preview "Label Buttons" --press right           focus the second Label button
//   ... --preview "Collapsed Sidebar" --press right       move focus into the content
//   ... --preview "Toolbar Item" --press up               focus the toolbar item
//   ... --preview "Segments" --press right                focus (and select) the next segment
//   ... --preview "List Picker" --press down              focus the picker's selected segment
//   ... --preview "List Picker" --press down,down         focus the toggle row

/// A gradient stand-in for artwork.
struct Artwork: View {
    let hue: Double
    var body: some View {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.9), Color(hue: hue, saturation: 0.85, brightness: 0.45)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Plain and borderless buttons

struct TVPlainButtonsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            Text("Plain and borderless").font(.title3)
            HStack(alignment: .top, spacing: 70) {
                Button {} label: {
                    VStack(spacing: 14) {
                        Artwork(hue: 0.58).frame(width: 240, height: 360).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("Borderless art").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                Button {} label: {
                    VStack(spacing: 14) {
                        Artwork(hue: 0.08).frame(width: 240, height: 360)
                        Text("Plain art").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                Button("Plain text") {}.buttonStyle(.plain)
                Button("Borderless text") {}.buttonStyle(.borderless)
                Button {} label: {
                    VStack(spacing: 14) {
                        Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 120, height: 120)
                        Text("Borderless image").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

#Preview("Plain Buttons") { TVPlainButtonsDemo() }

// MARK: - Labels in buttons

struct TVLabelButtonsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            HStack(spacing: 40) {
                Button {} label: { Label("Resume", systemImage: "play.fill") }
                Button {} label: { Label("Add to List", systemImage: "plus") }
                Button("Trailer", systemImage: "film") {}
                Button {} label: { Label("Rate", systemImage: "star") }.controlSize(.small)
            }
            HStack(spacing: 60) {
                Label("Downloaded", systemImage: "checkmark.circle")
                Label("4K Dolby Vision", systemImage: "sparkles.tv")
            }
        }
    }
}

#Preview("Label Buttons") { TVLabelButtonsDemo() }

// MARK: - Collapsed sidebar

struct TVCollapsedSidebarDemo: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { TVPosterRow(title: "Home") }
            Tab("Movies", systemImage: "film") { TVPosterRow(title: "Movies") }
            Tab("Shows", systemImage: "tv") { TVPosterRow(title: "Shows") }
            Tab("Settings", systemImage: "gear") { TVPosterRow(title: "Settings") }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct TVPosterRow: View {
    let title: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(title).font(.title3)
                HStack(spacing: 40) {
                    ForEach(0..<4, id: \.self) { i in
                        Button {} label: { Artwork(hue: Double(i) / 5).frame(width: 300, height: 170) }
                            .buttonStyle(.card)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Collapsed Sidebar") { TVCollapsedSidebarDemo() }

// MARK: - Toolbar item

struct TVToolbarItemDemo: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Profiles") { Text("Profiles") }
                NavigationLink("Notifications") { Text("Notifications") }
                NavigationLink("Storage") { Text("Storage") }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") {} }
            }
        }
    }
}

#Preview("Toolbar Item") { TVToolbarItemDemo() }

// MARK: - Segments

struct TVSegmentsDemo: View {
    @State private var range = 0
    @State private var sort = "Recent"
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Picker("Range", selection: $range) {
                Text("Today").tag(0)
                Text("This Week").tag(1)
                Text("This Month").tag(2)
            }
            .pickerStyle(.segmented)
            Picker("Sort", selection: $sort) {
                ForEach(["Recent", "Title", "Length"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
        }
        .frame(width: 900)
    }
}

#Preview("Segments") { TVSegmentsDemo() }

// MARK: - Segmented picker in a List

struct TVListPickerDemo: View {
    @State private var audio = "Stereo"
    @State private var captions = true
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Language") { Text("Language") }
                Picker("Audio", selection: $audio) {
                    ForEach(["Stereo", "Surround", "Spatial"], id: \.self) { Text($0) }
                }
                Toggle("Captions", isOn: $captions)
            }
        }
    }
}

#Preview("List Picker") { TVListPickerDemo() }
