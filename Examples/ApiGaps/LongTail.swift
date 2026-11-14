import SwiftUI

// The long tail of the coverage list: PreviewProvider with the preview modifiers, accessibility modifiers
// with isEnabled, and the indefinite bounce symbol effect.

struct BadgeRow: View {
    var showsHint = true
    var body: some View {
        HStack {
            Image(systemName: "bell.badge")
                .symbolEffect(.bounce)
                .symbolEffect(.bounce, options: .repeating, isActive: true)
            Text("Notifications")
        }
        .accessibilityLabel("Notifications", isEnabled: true)
        .accessibilityHint(Text("Opens the inbox"), isEnabled: showsHint)
        .accessibilityValue("3 unread", isEnabled: true)
        .accessibilityIdentifier("bell", isEnabled: true)
    }
}

struct BadgeRow_Previews: PreviewProvider {
    static var previews: some View {
        BadgeRow()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Badge row")
            .previewDevice(PreviewDevice(rawValue: "iPhone 16"))
            .previewDevice("iPhone 16 Pro")
            .previewInterfaceOrientation(.portrait)
            .padding()
    }
    static var platform: PreviewPlatform? { .iOS }
}
