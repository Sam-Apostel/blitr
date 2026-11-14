import SwiftUI

// tvOS controls and system chrome, one preview per area. Each preview shows the unfocused, focused,
// disabled and selected states side by side; the first element in reading order starts focused.
//
//   swiftui-screenshot render Examples/TVControls.swift --device apple-tv --all --out-dir out
//   swiftui-screenshot render Examples/TVControls.swift --device apple-tv --all --out-dir out --scheme dark
//   swiftui-screenshot render Examples/TVControls.swift --device apple-tv --all --out-dir out --os 18
//
// Move focus to see other elements focused:
//   ... --preview Buttons --focus "Prominent"            focus a button by its label
//   ... --preview "Tab Bar" --press down                 leave the tab bar (selected tab stays marked)
//   ... --preview Alert --press down                     focus the second alert button
//   ... --preview "Settings List" --press down,down      focus the third row

// MARK: - Buttons

struct TVButtonsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            Text("Buttons").font(.title3)
            HStack(spacing: 40) {
                Button("Focused") {}
                Button("Bordered") {}
                Button("Prominent") {}.buttonStyle(.borderedProminent)
                Button("Delete", role: .destructive) {}
                Button("Disabled") {}.disabled(true)
            }
            HStack(spacing: 40) {
                Button("Play", systemImage: "play.fill") {}
                Button("Capsule") {}.buttonBorderShape(.capsule)
                Button { } label: { Image(systemName: "heart.fill") }.buttonBorderShape(.circle)
                Button("Small") {}.controlSize(.small)
                Button("Large") {}.controlSize(.large)
            }
            HStack(alignment: .top, spacing: 60) {
                Button {} label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Poster(hue: 0.6).frame(width: 260, height: 156)
                        Text("Card").font(.callout).padding([.horizontal, .bottom], 16)
                    }
                }
                .buttonStyle(.card)
                Button {} label: {
                    VStack(spacing: 14) {
                        Poster(hue: 0.05).frame(width: 220, height: 330).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("Borderless").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                Button {} label: { Poster(hue: 0.35).frame(width: 220, height: 330) }
                    .buttonStyle(.plain)
                Button("Plain text") {}.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// A gradient stand-in for artwork.
struct Poster: View {
    let hue: Double
    var body: some View {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85), Color(hue: hue, saturation: 0.8, brightness: 0.4)],
                       startPoint: .top, endPoint: .bottom)
    }
}

#Preview("Buttons") { TVButtonsDemo() }

// MARK: - Toggles, pickers, text fields and other controls

struct TVInputsDemo: View {
    @State private var subtitles = true
    @State private var autoplay = false
    @State private var quality = "Auto"
    @State private var tab = 1
    @State private var name = ""
    @State private var email = "sam@example.com"

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 30) {
                Toggle("Subtitles", isOn: $subtitles)
                Toggle("Autoplay", isOn: $autoplay)
                Toggle("Switch style", isOn: $subtitles).toggleStyle(.switch)
                Toggle("Disabled", isOn: $autoplay).disabled(true)
                Picker("Quality", selection: $quality) {
                    ForEach(["Auto", "1080p", "4K"], id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Picker("Quality", selection: $quality) {
                    ForEach(["Auto", "1080p", "4K"], id: \.self) { Text($0) }
                }
                .pickerStyle(.navigationLink)
                Picker("Section", selection: $tab) {
                    Text("Movies").tag(0)
                    Text("Shows").tag(1)
                    Text("Kids").tag(2)
                }
            }
            .frame(width: 760)
            VStack(alignment: .leading, spacing: 30) {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                SecureField("Password", text: $email)
                Menu("More Options") {
                    Button("Share") {}
                    Button("Report") {}
                }
                Link("Privacy Policy", destination: URL(string: "https://example.com")!)
                Label("Downloaded", systemImage: "checkmark.circle")
                ProgressView(value: 0.4)
                HStack(spacing: 40) {
                    ProgressView()
                    ProgressView("Loading")
                }
            }
            .frame(width: 760)
        }
    }
}

#Preview("Inputs") { TVInputsDemo() }

struct TVInlinePickerDemo: View {
    @State private var quality = "1080p"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Inline picker").font(.headline)
            Picker("Quality", selection: $quality) {
                ForEach(["Auto", "1080p", "4K"], id: \.self) { Text($0) }
            }
            .pickerStyle(.inline)
        }
        .frame(width: 700)
    }
}

#Preview("Inline Picker") { TVInlinePickerDemo() }

// MARK: - Tab bar, sidebar, pages

struct TVShelfContent: View {
    let title: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(title).font(.title3)
                ScrollView(.horizontal) {
                    HStack(spacing: 40) {
                        ForEach(0..<6, id: \.self) { i in
                            Button {} label: {
                                Poster(hue: Double(i) / 6).frame(width: 300, height: 170)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
        }
    }
}

struct TVTabsDemo: View {
    @State private var selection = 1
    var body: some View {
        TabView(selection: $selection) {
            Tab("Search", systemImage: "magnifyingglass", value: 0) { TVShelfContent(title: "Search") }
            Tab("Watch Now", systemImage: "play.rectangle", value: 1) { TVShelfContent(title: "Up Next") }
            Tab("Movies", systemImage: "film", value: 2) { TVShelfContent(title: "Movies") }
            Tab("Library", systemImage: "books.vertical", value: 3) { TVShelfContent(title: "Library") }
        }
    }
}

#Preview("Tab Bar") { TVTabsDemo() }

struct TVSidebarDemo: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { TVShelfContent(title: "Home") }
            Tab("Movies", systemImage: "film") { TVShelfContent(title: "Movies") }
            Tab("Settings", systemImage: "gear") { TVShelfContent(title: "Settings") }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview("Sidebar") { TVSidebarDemo() }

struct TVPagesDemo: View {
    var body: some View {
        TabView {
            ForEach(0..<4, id: \.self) { i in
                Poster(hue: Double(i) / 4).ignoresSafeArea()
            }
        }
        .tabViewStyle(.page)
    }
}

#Preview("Pages") { TVPagesDemo() }

// MARK: - Navigation and lists

struct TVSettingsListDemo: View {
    @State private var subtitles = true
    @State private var autoplay = false
    @State private var quality = "Auto"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Account") { Text("Account") }
                    Toggle("Subtitles", isOn: $subtitles)
                    Toggle("Autoplay Previews", isOn: $autoplay)
                    Picker("Video Quality", selection: $quality) {
                        ForEach(["Auto", "1080p", "4K"], id: \.self) { Text($0) }
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Previews play when a title has focus for a moment.")
                }
                Section("About") {
                    LabeledContent("Version", value: "2.4")
                    NavigationLink {
                        Text("Licenses")
                    } label: {
                        LabeledContent("Licenses", value: "12")
                    }
                    Button("Sign Out", role: .destructive) {}
                    Button("Reset") {}.disabled(true)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Help") {} }
            }
        }
    }
}

#Preview("Settings List") { TVSettingsListDemo() }

struct TVSearchDemo: View {
    @State private var query = ""
    var body: some View {
        NavigationStack {
            TVShelfContent(title: "Top Results")
                .searchable(text: $query, prompt: "Movies, shows and more")
        }
    }
}

#Preview("Search") { TVSearchDemo() }

// MARK: - Presentations

struct TVAlertDemo: View {
    @State private var showsAlert = true
    var body: some View {
        TVShelfContent(title: "Library")
            .padding(80)
            .alert("Delete Download?", isPresented: $showsAlert) {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The episode is removed from this Apple TV.")
            }
    }
}

#Preview("Alert") { TVAlertDemo() }

struct TVDialogDemo: View {
    @State private var showsDialog = true
    var body: some View {
        TVShelfContent(title: "Library")
            .padding(80)
            .confirmationDialog("Play from", isPresented: $showsDialog, titleVisibility: .visible) {
                Button("Resume at 12:40") {}
                Button("Beginning") {}
                Button("Remove from Up Next", role: .destructive) {}
            }
    }
}

#Preview("Dialog") { TVDialogDemo() }

struct TVSheetDemo: View {
    @State private var showsSheet = true
    var body: some View {
        TVShelfContent(title: "Library")
            .padding(80)
            .sheet(isPresented: $showsSheet) {
                VStack(spacing: 40) {
                    Text("Rate this movie").font(.title2)
                    HStack(spacing: 30) {
                        Button("Loved it") {}
                        Button("It was fine") {}
                        Button("Not for me") {}
                    }
                }
            }
    }
}

#Preview("Sheet") { TVSheetDemo() }

// MARK: - Focus visuals for custom views

struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlowBody(label: configuration.label)
    }
}

/// A custom style draws focus itself from `isFocused`; tvOS adds no effect to it.
struct GlowBody: View {
    let label: ButtonStyleConfiguration.Label
    @Environment(\.isFocused) private var isFocused
    var body: some View {
        label
            .padding(.horizontal, 36).padding(.vertical, 18)
            .background(isFocused ? Color.orange : Color.gray.opacity(0.3), in: Capsule())
            .scaleEffect(isFocused ? 1.08 : 1)
    }
}

struct FocusableTile: View {
    let title: String
    @Environment(\.isFocused) private var isFocused
    var body: some View {
        Text(title)
            .frame(width: 280, height: 160)
            .background(isFocused ? Color.blue : Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(isFocused ? .white : .primary)
    }
}

struct TVFocusVisualsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            HStack(spacing: 40) {
                Button("Custom style") {}.buttonStyle(GlowButtonStyle())
                Button("Custom style") {}.buttonStyle(GlowButtonStyle())
                Button("No effect") {}.focusEffectDisabled()
            }
            HStack(spacing: 40) {
                FocusableTile(title: ".focusable()").focusable()
                Poster(hue: 0.55).frame(width: 280, height: 160).clipShape(RoundedRectangle(cornerRadius: 16))
                    .hoverEffect(.highlight).focusable()
                Poster(hue: 0.8).frame(width: 280, height: 160).clipShape(RoundedRectangle(cornerRadius: 16))
                    .hoverEffect(.lift).focusable()
            }
        }
    }
}

#Preview("Focus Visuals") { TVFocusVisualsDemo() }
