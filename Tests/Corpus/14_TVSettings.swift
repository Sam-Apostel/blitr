import SwiftUI

// A tvOS settings screen: a navigation title, sections of toggles, pickers and links, and a destructive
// action behind a confirmation dialog. Rendered with --device apple-tv in CI; also renders on iOS.

enum StreamQuality: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case hd = "HD"
    case uhd = "4K HDR"
    var id: Self { self }
}

@MainActor
final class PlaybackSettings: ObservableObject {
    @Published var autoplay = true
    @Published var subtitles = false
    @Published var reduceLoudSounds = true
    @Published var quality = StreamQuality.automatic
    @Published var audioLanguage = "English"
}

struct SettingsScreen: View {
    @StateObject private var settings = PlaybackSettings()
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 60) {
                #if os(tvOS)
                VStack(spacing: 24) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 160))
                        .foregroundStyle(.secondary)
                    Text("Riverbend TV").font(.headline)
                    Text("Version 3.2 (418)").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
                #endif
                Form {
                    Section {
                        Toggle("Autoplay Next Episode", isOn: $settings.autoplay)
                        Toggle("Subtitles", isOn: $settings.subtitles)
                        Picker("Streaming Quality", selection: $settings.quality) {
                            ForEach(StreamQuality.allCases) { Text($0.rawValue).tag($0) }
                        }
                        NavigationLink {
                            Text("Audio Language")
                        } label: {
                            LabeledContent("Audio Language", value: settings.audioLanguage)
                        }
                    } header: {
                        Text("Playback")
                    } footer: {
                        Text("Higher quality uses more bandwidth.")
                    }

                    Section("Sound") {
                        Toggle("Reduce Loud Sounds", isOn: $settings.reduceLoudSounds)
                    }

                    Section("Account") {
                        LabeledContent("Signed in as", value: "Robin")
                        NavigationLink("Manage Subscription") { Text("Subscription") }
                        Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of Riverbend?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {}
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
