import SwiftUI

// Text-to-text spacing: two texts stacked without an explicit spacing, in a VStack and in a
// LazyVStack, in text-style fonts (which have leading) and in `.system(size:)` fonts (which have none).

struct TextSpacingPair: View {
    let name: String
    let lazy: Bool
    let top: Font
    let bottom: Font

    var body: some View {
        if lazy {
            LazyVStack(alignment: .leading) {
                Text("\(name) upper").font(top).background(Color.yellow.opacity(0.4))
                Text("\(name) lower").font(bottom).background(Color.cyan.opacity(0.4))
            }
        } else {
            VStack(alignment: .leading) {
                Text("\(name) upper").font(top).background(Color.yellow.opacity(0.4))
                Text("\(name) lower").font(bottom).background(Color.cyan.opacity(0.4))
            }
        }
    }
}

struct TextSpacingScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextSpacingPair(name: "Stack body", lazy: false, top: .body, bottom: .body)
            TextSpacingPair(name: "Lazy body", lazy: true, top: .body, bottom: .body)
            TextSpacingPair(name: "Stack caption title", lazy: false, top: .caption, bottom: .title)
            TextSpacingPair(name: "Lazy caption title", lazy: true, top: .caption, bottom: .title)
            TextSpacingPair(name: "Stack size 17", lazy: false, top: .system(size: 17), bottom: .system(size: 17))
            TextSpacingPair(name: "Lazy size 17", lazy: true, top: .system(size: 17), bottom: .system(size: 17))
            TextSpacingPair(name: "Stack size 12 30", lazy: false, top: .system(size: 12), bottom: .system(size: 30))
            TextSpacingPair(name: "Lazy size 12 30", lazy: true, top: .system(size: 12), bottom: .system(size: 30))
            LazyVStack(alignment: .leading) {
                ForEach(0..<3) { index in
                    Text("Lazy row \(index)").background(Color.yellow.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Text spacing") {
    TextSpacingScreen()
}
