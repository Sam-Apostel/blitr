import SwiftUI

// tvOS focus: render with --device apple-tv and add --focus-map / --focus-overlay / --press.
//   swiftui-screenshot render Examples/TVFocus.swift --device apple-tv --all --out-dir out \
//       --focus-map out/focus.json --focus-overlay out/focus.png

// MARK: - Poster grid

struct Poster: View {
    let index: Int
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [Color(hue: Double(index % 12) / 12, saturation: 0.6, brightness: 0.8),
                                          Color(hue: Double(index % 12) / 12, saturation: 0.8, brightness: 0.45)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomLeading) {
                Text("Movie \(index + 1)").font(.headline).foregroundStyle(.white).padding(16)
            }
    }
}

struct PosterGrid: View {
    let columns = Array(repeating: GridItem(.fixed(300), spacing: 48), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("Movies").font(.title2).bold()
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(0..<20, id: \.self) { i in
                        Button {} label: { Poster(index: i, size: CGSize(width: 300, height: 420)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }
}

// MARK: - Shelves (the classic tvOS home screen)

struct Shelves: View {
    let rows: [(title: String, count: Int, size: CGSize)] = [
        ("Up Next", 8, CGSize(width: 480, height: 270)),
        ("Top Movies", 12, CGSize(width: 250, height: 375)),
        ("Channels", 10, CGSize(width: 200, height: 200)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                ForEach(rows.indices, id: \.self) { r in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(rows[r].title).font(.title3).bold().padding(.leading, 80)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 40) {
                                ForEach(0..<rows[r].count, id: \.self) { i in
                                    Button {} label: { Poster(index: r * 20 + i, size: rows[r].size) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 80)
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
            .padding(.vertical, 50)
        }
    }
}

// MARK: - Side by side: a button only .focusSection() makes reachable

struct SideBySide: View {
    let fixed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 120) {
            VStack(alignment: .leading, spacing: 30) {
                Text(fixed ? "With .focusSection()" : "Without .focusSection()").font(.title3).bold()
                Button("Library") {}
                Button("Search") {}
                Button("Settings") {}
            }
            .frame(width: 500, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            // Both columns are sections: the right one so focus can get in, the left one so it can get back.
            .modifier(SectionIf(enabled: fixed))
            VStack {
                Spacer()
                Button("Play Trailer") {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .modifier(SectionIf(enabled: fixed))
        }
        .padding(80)
    }
}

struct SectionIf: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.focusSection() } else { content }
    }
}

// MARK: - TabView with a settings list

struct SettingsTabs: View {
    @State private var subtitles = true
    @State private var autoplay = false
    @State private var quality = "Auto"

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Toggle("Subtitles", isOn: $subtitles)
                    Toggle("Autoplay Previews", isOn: $autoplay)
                    Picker("Video Quality", selection: $quality) {
                        ForEach(["Auto", "High", "Low"], id: \.self) { Text($0) }
                    }
                    NavigationLink("About") { Text("Version 1.0") }
                    Button("Sign Out") {}
                }
                .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            Text("Home").tabItem { Label("Home", systemImage: "house") }
            Text("Search").tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}

// MARK: - @FocusState and defaultFocus

struct SignIn: View {
    enum Field: Hashable { case user, password, submit }
    @FocusState private var field: Field?
    @State private var user = ""

    var body: some View {
        VStack(spacing: 30) {
            Text("Sign In").font(.title2).bold()
            TextField("Email", text: $user).focused($field, equals: .user).frame(width: 600)
            SecureField("Password", text: .constant("")).focused($field, equals: .password).frame(width: 600)
            Button("Continue") {}.focused($field, equals: .submit)
            Text(field.map { "focused: \($0)" } ?? "focused: nothing").foregroundStyle(.secondary)
        }
        .defaultFocus($field, .password)
    }
}

struct FocusCard: View {
    let title: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(width: 320, height: 180)
            .background(isFocused ? Color.blue : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(isFocused ? .white : .primary)
    }
}

struct FocusStateFromOnAppear: View {
    @FocusState private var focusedCard: Int?

    var body: some View {
        HStack(spacing: 40) {
            ForEach(0..<4, id: \.self) { i in
                FocusCard(title: "Card \(i + 1)")
                    .focusable()
                    .focused($focusedCard, equals: i)
            }
        }
        .onAppear { focusedCard = 2 }
    }
}

#Preview("Poster Grid") { PosterGrid() }
#Preview("Shelves") { Shelves() }
#Preview("Unreachable") { SideBySide(fixed: false) }
#Preview("Focus Section") { SideBySide(fixed: true) }
#Preview("Settings Tabs") { SettingsTabs() }
#Preview("Default Focus") { SignIn() }
#Preview("Focus On Appear") { FocusStateFromOnAppear() }
