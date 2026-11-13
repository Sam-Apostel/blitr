import SwiftUI
import Observation

// MARK: - Model

enum SettingsAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum SettingsLanguage: String, CaseIterable, Identifiable {
    case english = "English", german = "Deutsch", spanish = "Español", japanese = "日本語"
    var id: String { rawValue }
}

@Observable
final class SettingsStore {
    var airplaneMode = false
    var notificationsEnabled = true
    var showPreviews = true
    var appearance: SettingsAppearance = .system
    var language: SettingsLanguage = .english
    var fontScale = 1.0
    var brightness = 0.6
    var autoLockMinutes = 5
    var wifiName = "Home Network"
    var storageUsed = "42.1 GB"

    func reset() {
        notificationsEnabled = true
        showPreviews = true
        appearance = .system
        fontScale = 1.0
        brightness = 0.6
        autoLockMinutes = 5
    }
}

// MARK: - Subviews

struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsValueRow: View {
    let title: String
    let symbol: String
    let color: Color
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsDetailPlaceholder: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "gearshape", description: Text("Nothing to configure yet."))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Screen

struct SettingsScreen: View {
    @State private var store = SettingsStore()
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                            .overlay(Text("SM").font(.title2.weight(.semibold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sam Morgan").font(.title3.weight(.semibold))
                            Text("Account, iCloud and purchases").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Connectivity") {
                    Toggle(isOn: $store.airplaneMode.animation()) {
                        Label { Text("Airplane Mode") } icon: { SettingsIcon(symbol: "airplane", color: .orange) }
                    }
                    NavigationLink {
                        SettingsDetailPlaceholder(title: "Wi-Fi")
                    } label: {
                        SettingsValueRow(title: "Wi-Fi", symbol: "wifi", color: .blue,
                                         value: store.airplaneMode ? "Off" : store.wifiName)
                    }
                    NavigationLink {
                        SettingsDetailPlaceholder(title: "Bluetooth")
                    } label: {
                        SettingsValueRow(title: "Bluetooth", symbol: "wave.3.right", color: .cyan, value: "On")
                    }
                }

                Section {
                    Toggle("Allow Notifications", isOn: $store.notificationsEnabled)
                    if store.notificationsEnabled {
                        Toggle("Show Previews", isOn: $store.showPreviews)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Previews show a snippet of each message on the lock screen.")
                }

                Section("Display") {
                    Picker("Appearance", selection: $store.appearance) {
                        ForEach(SettingsAppearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Language", selection: $store.language) {
                        ForEach(SettingsLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    VStack(alignment: .leading) {
                        Text("Text Size: \(Int(store.fontScale * 100))%")
                        Slider(value: $store.fontScale, in: 0.8...1.4, step: 0.1)
                            .accessibilityLabel("Text size")
                    }
                    HStack {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: $store.brightness)
                        Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                    }
                    Stepper("Auto-Lock: \(store.autoLockMinutes) min", value: $store.autoLockMinutes, in: 1...30)
                }

                Section("General") {
                    SettingsValueRow(title: "Storage", symbol: "internaldrive", color: .gray, value: store.storageUsed)
                    NavigationLink {
                        SettingsDetailPlaceholder(title: "Privacy")
                    } label: {
                        SettingsValueRow(title: "Privacy & Security", symbol: "hand.raised.fill", color: .blue)
                    }
                }

                Section {
                    Button("Reset All Settings", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.reset() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsScreen()
}

#Preview("Dark") {
    SettingsScreen().preferredColorScheme(.dark)
}
