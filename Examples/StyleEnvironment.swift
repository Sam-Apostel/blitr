import SwiftUI
struct PillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(isEnabled ? (scheme == .dark ? Color.yellow : Color.blue) : Color.gray, in: Capsule())
            .foregroundStyle(.white)
    }
}
struct TagStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var size
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.icon; configuration.title; Text(size > .large ? "big" : "std") }
    }
}
#Preview {
    VStack(spacing: 20) {
        Button("Enabled") {}.buttonStyle(PillStyle())
        Button("Disabled") {}.buttonStyle(PillStyle()).disabled(true)
        Button("Dark") {}.buttonStyle(PillStyle()).environment(\.colorScheme, .dark)
        Label("Tag", systemImage: "tag").labelStyle(TagStyle())
    }
}
