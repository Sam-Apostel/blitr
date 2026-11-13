import SwiftUI

// MARK: - Model

enum ProfileTab: String, CaseIterable, Identifiable {
    case posts = "Posts", reels = "Reels", tagged = "Tagged"
    var id: String { rawValue }
}

struct ProfileStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct ProfilePhoto: Identifiable {
    let id: Int
    var colors: [Color] {
        let palettes: [[Color]] = [[.pink, .orange], [.blue, .cyan], [.purple, .indigo], [.green, .mint], [.red, .yellow]]
        return palettes[id % palettes.count]
    }
}

// MARK: - Styles

struct ProfilePillButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(filled ? Color.white : Color.primary)
            .background(filled ? Color.blue : Color.gray.opacity(0.18), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Subviews

struct ProfileStatsRow: View {
    let stats: [ProfileStat]

    var body: some View {
        HStack {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                VStack(spacing: 2) {
                    Text(stat.value).font(.title3.bold()).monospacedDigit()
                    Text(stat.label).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                if index < stats.count - 1 {
                    Divider().frame(height: 28)
                }
            }
        }
    }
}

struct ProfileHeader: View {
    @Binding var isFollowing: Bool
    let onMessage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(AngularGradient(colors: [.pink, .orange, .yellow, .pink], center: .center))
                .frame(width: 104, height: 104)
                .overlay(
                    Circle().fill(.background).padding(4)
                        .overlay(Text("LR").font(.system(size: 36, weight: .bold, design: .rounded)))
                )
                .accessibilityLabel("Profile photo")
            VStack(spacing: 4) {
                Text("Lena Rivera").font(.title2.bold())
                Text("@lena.makes").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Ceramics, film cameras and slow mornings. Sharing what I make from my tiny studio in Lisbon.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button(isFollowing ? "Following" : "Follow") {
                    withAnimation(.snappy) { isFollowing.toggle() }
                }
                .buttonStyle(ProfilePillButtonStyle(filled: !isFollowing))
                Button("Message", action: onMessage)
                    .buttonStyle(ProfilePillButtonStyle(filled: false))
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen

struct ProfileScreen: View {
    @State private var isFollowing = false
    @State private var tab: ProfileTab = .posts
    @State private var showMessageAlert: Bool
    private let stats = [
        ProfileStat(value: "248", label: "Posts"),
        ProfileStat(value: "12.4K", label: "Followers"),
        ProfileStat(value: "391", label: "Following"),
    ]
    private let photos = (0..<18).map { ProfilePhoto(id: $0) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(showMessageAlert: Bool = false) {
        _showMessageAlert = State(initialValue: showMessageAlert)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProfileHeader(isFollowing: $isFollowing) { showMessageAlert = true }
                    ProfileStatsRow(stats: stats)
                    Picker("Section", selection: $tab) {
                        ForEach(ProfileTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            LinearGradient(colors: photo.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .topTrailing) {
                                    if photo.id % 4 == 0 {
                                        Image(systemName: "square.on.square")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .alert("Message Lena?", isPresented: $showMessageAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Send Message") { }
            } message: {
                Text("Start a new conversation with @lena.makes.")
            }
        }
    }
}

#Preview {
    ProfileScreen()
}

#Preview("Alert") {
    ProfileScreen(showMessageAlert: true)
}
