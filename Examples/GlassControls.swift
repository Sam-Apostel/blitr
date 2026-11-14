import SwiftUI

// iOS 26 look of buttons and controls. Render with --ios 26 or --ios 27.

struct GlassControlsDemo: View {
    @State private var on = true
    @State private var off = false
    @State private var value = 0.45
    @State private var stepped = 6.0
    @State private var count = 3
    @State private var segment = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sizes("Bordered", style: .bordered)
                sizes("Bordered prominent", style: .borderedProminent)
                // Colourful backdrop so the refraction of the glass buttons is visible.
                Group {
                    VStack(spacing: 12) {
                        glassRow(.glass)
                        glassRow(.glassProminent)
                        HStack {
                            Button("Tinted") {}.buttonStyle(.glassProminent).tint(.red)
                            Button("Disabled") {}.buttonStyle(.glass).disabled(true)
                            Button("Icon") {}.buttonStyle(.glass).buttonBorderShape(.circle)
                        }
                        Button("Flexible") {}.buttonStyle(.glassProminent).buttonSizing(.flexible).controlSize(.large)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.pink, .orange, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                HStack(spacing: 16) {
                    Toggle("", isOn: $on).labelsHidden()
                    Toggle("", isOn: $off).labelsHidden()
                    Stepper("", value: $count, in: 0...10).labelsHidden()
                }
                Slider(value: $value)
                Slider(value: $stepped, in: 0...10, step: 1)
                Picker("Mode", selection: $segment) {
                    Text("Day").tag(0)
                    Text("Week").tag(1)
                    Text("Month").tag(2)
                }
                .pickerStyle(.segmented)
                GroupBox("Group") { Text("Content in a group box") }
                Text("List").font(.headline)
                ListDemo().frame(height: 460)
            }
            .padding(16)
        }
    }

    func sizes(_ title: String, style: some PrimitiveButtonStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Mini") {}.controlSize(.mini)
                Button("Small") {}.controlSize(.small)
                Button("Regular") {}
                Button("Large") {}.controlSize(.large)
            }
            Button("Extra large") {}.controlSize(.extraLarge)
        }
        .buttonStyle(style)
    }

    func glassRow(_ style: some PrimitiveButtonStyle) -> some View {
        HStack {
            Button("Mini") {}.controlSize(.mini)
            Button("Small") {}.controlSize(.small)
            Button("Regular") {}
            Button("Large") {}.controlSize(.large)
        }
        .buttonStyle(style)
    }
}

struct ListDemo: View {
    @State private var wifi = true
    var body: some View {
        List {
            Section {
                Toggle("Wi-Fi", isOn: $wifi)
                NavigationLink("Bluetooth") { Text("") }
                Label("Cellular", systemImage: "antenna.radiowaves.left.and.right")
            } header: {
                Text("Connectivity")
            } footer: {
                Text("Turn these off to save battery.")
            }
            Section("Display") {
                Text("Brightness")
                Text("Text size")
            }
            Section {
                Text("Prominent header")
            } header: {
                Text("Account").font(.title3)
            }
            .headerProminence(.increased)
        }
    }
}

#Preview { GlassControlsDemo() }
