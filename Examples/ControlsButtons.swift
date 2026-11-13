import SwiftUI

struct ButtonsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Borderless") {}
            Button("Plain", action: {}).buttonStyle(.plain)
            Button("Bordered") {}.buttonStyle(.bordered)
            Button("Prominent") {}.buttonStyle(.borderedProminent)
            HStack {
                Button("Cancel", role: .cancel) {}.buttonStyle(.bordered)
                Button("Delete", role: .destructive) {}.buttonStyle(.bordered)
                Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Mini") {}.buttonStyle(.bordered).controlSize(.mini)
                Button("Small") {}.buttonStyle(.bordered).controlSize(.small)
                Button("Regular") {}.buttonStyle(.bordered)
                Button("Large") {}.buttonStyle(.borderedProminent).controlSize(.large)
            }
            HStack {
                Button("Tinted") {}.buttonStyle(.bordered).tint(.green)
                Button("Tinted") {}.buttonStyle(.borderedProminent).tint(.orange)
                Button("Capsule") {}.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            }
            HStack {
                Button("Disabled") {}.disabled(true)
                Button("Disabled") {}.buttonStyle(.bordered).disabled(true)
                Button("Disabled") {}.buttonStyle(.borderedProminent).disabled(true)
            }
            Button { } label: { Label("With icon", systemImage: "star.fill") }.buttonStyle(.bordered)
            Button("Large wide") {}
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
            Label("Title only", systemImage: "heart").labelStyle(.titleOnly)
            Label("Title and icon", systemImage: "heart")
            LabeledContent("Version", value: "1.2.3")
            Link("Open site", destination: URL(string: "https://example.com")!)
            Menu("Options") { Button("One") {} }
        }
        .padding(20)
    }
}

#Preview { ButtonsDemo() }
