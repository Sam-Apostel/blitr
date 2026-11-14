import SwiftUI

// A tvOS media home screen: tab bar, a hero with actions, and shelves of lockups.
// Rendered with --device apple-tv in CI; on iOS the same file shows a phone-sized version.

// MARK: - Model

struct Show: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let hue: Double
}

enum HomeTab: Hashable {
    case search, watchNow, shows, library
}

let featuredShow = Show(id: 0, title: "The Long Coast", subtitle: "Drama · 3 Seasons · New episode Friday", hue: 0.58)

let continueWatching: [Show] = [
    Show(id: 1, title: "Harbour Lights", subtitle: "S2, E4 · 18 min left", hue: 0.07),
    Show(id: 2, title: "North Ridge", subtitle: "S1, E9 · 32 min left", hue: 0.33),
    Show(id: 3, title: "Salt & Stone", subtitle: "Episode 3 · 41 min left", hue: 0.12),
    Show(id: 4, title: "Night Market", subtitle: "S3, E1 · 5 min left", hue: 0.82),
    Show(id: 5, title: "Glass Valley", subtitle: "S1, E2 · 50 min left", hue: 0.48),
]

let topShows: [Show] = (0..<9).map { i in
    Show(id: 10 + i, title: ["Paper Moons", "Tidewater", "The Quiet Hour", "Lanterns", "Coldwater", "Second Spring",
                             "Wildflower", "The Crossing", "Blue Hour"][i], subtitle: "", hue: Double(i) / 9)
}

// MARK: - Artwork

struct Artwork: View {
    let hue: Double
    var symbol: String? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.9),
                                    Color(hue: hue + 0.06, saturation: 0.85, brightness: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 60)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Hero

struct HeroView: View {
    let show: Show
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(hue: show.hue)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 18) {
                Text(show.title).font(.largeTitle).bold()
                Text(show.subtitle).font(.callout).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 24) {
                    Button("Play", systemImage: "play.fill") {}
                    Button("Add to Up Next", systemImage: "plus") {}
                    Button {} label: { Image(systemName: "info.circle") }
                        .buttonBorderShape(.circle)
                }
            }
            .foregroundStyle(.white)
            .padding(60)
        }
        #if os(tvOS)
        .frame(height: 560)
        #else
        .frame(height: 320)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Shelves

struct Lockup: View {
    let show: Show
    let size: CGSize
    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 12) {
                Artwork(hue: show.hue)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title).font(.callout)
                    if !show.subtitle.isEmpty {
                        Text(show.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: size.width, alignment: .leading)
            }
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

struct Shelf: View {
    let title: String
    let shows: [Show]
    let size: CGSize
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(shows) { Lockup(show: $0, size: size) }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

struct WatchNowView: View {
    #if os(tvOS)
    let wide = CGSize(width: 400, height: 225)
    let poster = CGSize(width: 200, height: 300)
    #else
    let wide = CGSize(width: 220, height: 124)
    let poster = CGSize(width: 110, height: 165)
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HeroView(show: featuredShow)
                Shelf(title: "Continue Watching", shows: continueWatching, size: wide)
                Shelf(title: "Top Shows", shows: topShows, size: poster)
            }
            #if !os(tvOS)
            .padding()
            #endif
        }
    }
}

// MARK: - Screen

struct TVHomeScreen: View {
    @State private var tab = HomeTab.watchNow

    var body: some View {
        TabView(selection: $tab) {
            Tab("Search", systemImage: "magnifyingglass", value: HomeTab.search) {
                Text("Search")
            }
            Tab("Watch Now", systemImage: "play.rectangle", value: HomeTab.watchNow) {
                WatchNowView()
            }
            Tab("Shows", systemImage: "tv", value: HomeTab.shows) {
                Text("Shows")
            }
            Tab("Library", systemImage: "books.vertical", value: HomeTab.library) {
                Text("Library")
            }
        }
    }
}

#Preview {
    TVHomeScreen()
}

#Preview("Dark") {
    TVHomeScreen().preferredColorScheme(.dark)
}
