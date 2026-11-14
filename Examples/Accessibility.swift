import SwiftUI

// Deliberately flawed: render with
//   swiftui-screenshot render Examples/Accessibility.swift --accessibility-tree a11y.json --tap-targets taps.png --accessibility-outline
// and the issues array reports the small icon button, the unlabeled buttons, the asset image without
// a label, the duplicate identifier and the truncated text.

struct AccessibilityShowcase: View {
    @State private var notifications = true

    var body: some View {
        NavigationStack {
            List {
                Section("Problems") {
                    HStack {
                        Text("Favourite")
                        Spacer()
                        // 24pt icon button, no label.
                        Button { } label: {
                            Image(systemName: "heart").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("action")
                    }
                    HStack {
                        Text("Avatar")
                        Spacer()
                        // Button whose only content is a shape: nothing to read.
                        Button { } label: {
                            Circle().fill(.blue).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("action")
                    }
                    Image("hero_banner").resizable().frame(height: 60)
                    Text("This description is far too long for a single line and gets cut off by its line limit")
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                }
                Section("Fine") {
                    Toggle("Notifications", isOn: $notifications)
                    Button("Save") { }
                    Button { } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .frame(width: 44, height: 44)
                    Image(decorative: "divider")
                }
            }
            .navigationTitle("Accessibility")
        }
    }
}

#Preview { AccessibilityShowcase() }
