import SwiftUI
import TipKit

// TipKit: tips show here after Tips.showAllTipsForTesting() (or with --show-tips). Rules, events and
// parameters compile and are evaluated; `#Rule` and `@Parameter` are TipKit's macros.

struct FavoriteTip: Tip {
    @Parameter static var isLoggedIn: Bool = false
    @Parameter(.transient) static var visits: Int = 0
    static let didOpenDetail = Event(id: "didOpenDetail")
    static let didShare = Tips.Event<ShareInfo>(id: "didShare", donationLimit: .max(10))

    var title: Text { Text("Save as a Favorite") }
    var message: Text? { Text("Your favorite backyards always appear at the top of the list.") }
    var image: Image? { Image(systemName: "star") }

    var actions: [Action] {
        Action(id: "learn-more", title: "Learn More")
        Action(id: "settings") { Text("Open Settings") }
    }

    var rules: [Rule] {
        #Rule(Self.$isLoggedIn) { $0 == true }
        #Rule(Self.didOpenDetail) { $0.donations.count >= 3 }
        #Rule(Self.didShare) { $0.donations.donatedWithin(.week).filter { $0.info.channel == "mail" }.count > 0 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(3)
        Tips.IgnoresDisplayFrequency(true)
    }
}

struct ShareInfo: Codable, Sendable {
    let channel: String
}

struct InlineTip: Tip {
    var title: Text { Text("Pull to refresh") }
    var message: Text? { Text("Drag the list down to load the newest posts.") }
}

struct HiddenTip: Tip {
    var title: Text { Text("Never shown") }
}

struct TipsExample: View {
    private let favorite = FavoriteTip()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TipView(InlineTip())
                TipView(favorite, arrowEdge: .bottom) { action in
                    if action.id == "learn-more" { favorite.invalidate(reason: .actionPerformed) }
                }
                TipView(HiddenTip())
                HStack {
                    Spacer()
                    Image(systemName: "star")
                        .font(.title)
                        .popoverTip(favorite, arrowEdge: .top)
                    Spacer()
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Backyards")
        }
        .task {
            try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
            FavoriteTip.isLoggedIn = true
            await FavoriteTip.didOpenDetail.donate()
            await FavoriteTip.didShare.donate(ShareInfo(channel: "mail"))
        }
    }
}

#Preview("Tips shown") {
    TipsExample()
        .onAppear {
            Tips.showAllTipsForTesting()
            Tips.hideTipsForTesting([HiddenTip.self])
        }
}

#Preview("Tips not shown by default") {
    TipsExample()
}

#Preview("Mini tip style") {
    TipView(InlineTip())
        .tipViewStyle(.miniTip)
        .tipBackground(Color.yellow.opacity(0.2))
        .tipCornerRadius(20)
        .tipImageSize(CGSize(width: 24, height: 24))
        .padding()
        .onAppear { Tips.showTipsForTesting([InlineTip.self]) }
}
