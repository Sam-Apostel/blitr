import SwiftUI

// A Settings-style inset-grouped list: icon rows with trailing values, headers, footers.

struct SettingsIcon: View {
    let color: Color
    let letter: String
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .frame(width: 29, height: 29)
            .overlay(Image(systemName: letter).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
    }
}

struct SettingsRow: View {
    let color: Color
    let letter: String
    let title: String
    var value: String? = nil
    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(color: color, letter: letter)
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsScreen: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Circle().fill(.gray.opacity(0.4)).frame(width: 60, height: 60)
                        .overlay(Text("SA").font(.title2.weight(.medium)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sam Apostel").font(.title2)
                        Text("Apple Account, iCloud, and more").font(.footnote)
                    }
                }
                .padding(.vertical, -4)
            }
            Section {
                SettingsRow(color: .orange, letter: "airplane", title: "Airplane Mode")
                SettingsRow(color: .blue, letter: "wifi", title: "Wi-Fi", value: "Home")
                SettingsRow(color: .blue, letter: "bluetooth", title: "Bluetooth", value: "On")
                SettingsRow(color: .green, letter: "antenna.radiowaves.left.and.right", title: "Cellular")
            }
            Section {
                SettingsRow(color: .gray, letter: "gear", title: "General")
                SettingsRow(color: .blue, letter: "accessibility", title: "Accessibility")
                SettingsRow(color: .indigo, letter: "siri", title: "Siri")
                    .badge(2)
            } header: {
                Text("General")
            } footer: {
                Text("Siri can help you get things done just by asking. About Siri & Privacy…")
            }
            Section {
                Text("Privacy & Security")
                Text("App Store")
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
