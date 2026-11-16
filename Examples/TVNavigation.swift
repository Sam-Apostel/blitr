import SwiftUI

// tvOS navigation in an app with its own chrome: a hand-built top bar of focus sections, a page that scrolls a
// whole section into view as focus enters it, a row of pills in a horizontal scroll view above a board, and a
// full-screen cover that closes itself on Menu. Render with --device apple-tv and drive it with --press:
//   blitr render Examples/TVNavigation.swift --device apple-tv --preview Page --press down,down,down
//   blitr render Examples/TVNavigation.swift --device apple-tv --preview Board --press down,down,up
//   blitr render Examples/TVNavigation.swift --device apple-tv --preview Cover --press right,down,right,select,menu

private struct Tile: View {
    let title: String
    let hue: Double
    var width: CGFloat = 420
    var height: CGFloat = 240

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.55))
            .frame(width: width, height: height)
            .overlay(alignment: .bottomLeading) {
                Text(title).font(.title3.bold()).foregroundStyle(.white).padding(20)
            }
    }
}

private struct PillStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, selected: selected) }
}

private struct PillBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(Capsule().fill(isFocused ? Color.white : selected ? Color.white.opacity(0.2) : Color.clear))
    }
}

private struct CardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CardBody(configuration: configuration) }
}

private struct CardBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: isFocused ? 5 : 0) }
    }
}

/// The bar: a name on the left, the screens in the middle, a settings button on the right, each a focus section.
private struct TopBar: View {
    @Binding var screen: Int
    let names = ["Home", "Library", "Board"]

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach(names.indices, id: \.self) { i in
                    Button(names[i]) { screen = i }.buttonStyle(PillStyle(selected: i == screen))
                }
            }
            .padding(6)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .focusSection()
            HStack {
                Button("Lakeside") {}.buttonStyle(PillStyle()).focusSection()
                Spacer()
                Button { } label: { Image(systemName: "gearshape") }.buttonStyle(PillStyle())
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
        .focusSection()
    }
}

private struct Shell<Content: View>: View {
    @State private var screen = 0
    @ViewBuilder var content: Content

    var body: some View {
        ZStack { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { TopBar(screen: $screen) }
            .background(Color(white: 0.07).ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - A page that scrolls a section to the top as focus enters it

private struct SectionedPage: View {
    private enum Section: Hashable { case rooms, notes, trips }
    @FocusState private var section: Section?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Lakeside cabin").font(.largeTitle.bold())
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        row("Rooms", count: 3, hue: 0.55, size: CGSize(width: 520, height: 300), section: .rooms).id(Section.rooms)
                        row("Notes", count: 4, hue: 0.1, size: CGSize(width: 380, height: 240), section: .notes).id(Section.notes)
                        row("Trips", count: 2, hue: 0.8, size: CGSize(width: 520, height: 160), section: .trips).id(Section.trips)
                    }
                    .padding(10)
                }
                .contentMargins(.bottom, 300, for: .scrollContent)
                .onChange(of: section) { _, new in
                    guard let new else { return }
                    withAnimation { proxy.scrollTo(new, anchor: .top) }
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, count: Int, hue: Double, size: CGSize, section: Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 32) {
                    ForEach(0..<count, id: \.self) { i in
                        Button {} label: { Tile(title: "\(title) \(i + 1)", hue: hue + Double(i) * 0.03, width: size.width, height: size.height) }
                            .buttonStyle(CardStyle())
                            .focused($section, equals: section)
                    }
                }
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

// MARK: - Pills in a horizontal scroll view above a board

private struct Board: View {
    @State private var pick = 0
    let groups = ["North shore", "South shore", "Islands"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(groups.indices, id: \.self) { i in
                            Button(groups[i]) { pick = i }.buttonStyle(PillStyle(selected: i == pick))
                        }
                    }
                    .padding(6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .scrollClipDisabled()
                .focusSection()
                Spacer()
                Text("3 cabins").font(.headline).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(0..<3, id: \.self) { i in
                        Button {} label: { Tile(title: "Cabin \(i + 1)", hue: 0.3 + Double(i) * 0.05, width: 440, height: 620) }
                            .buttonStyle(CardStyle())
                    }
                }
                .padding(.vertical, 22)
            }
            .focusSection()
        }
        .padding(.horizontal, 32)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - A full-screen cover that closes on Menu

private struct CoverDetail: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Text("Cabin 2").font(.largeTitle.bold())
            HStack(spacing: 30) {
                Button("Next") {}
                Button("Share") {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hue: 0.35, saturation: 0.4, brightness: 0.3).ignoresSafeArea())
        .onExitCommand { dismiss() }
    }
}

private struct CoverHost: View {
    @State private var open = false

    var body: some View {
        HStack(spacing: 40) {
            Button {} label: { Tile(title: "Cabin 1", hue: 0.3) }.buttonStyle(CardStyle())
            Button { open = true } label: { Tile(title: "Cabin 2", hue: 0.35) }.buttonStyle(CardStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $open) { CoverDetail() }
    }
}

#Preview("Page") { Shell { SectionedPage() } }
#Preview("Board") { Shell { Board() } }
#Preview("Cover") { Shell { CoverHost() } }
