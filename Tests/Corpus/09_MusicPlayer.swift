import SwiftUI
import Observation

// MARK: - Model

struct PlayerTrack {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let colors: [Color]
}

@Observable
final class PlayerModel {
    let track = PlayerTrack(title: "Midnight Drive", artist: "The Neon Hours", album: "City Lights",
                            duration: 237, colors: [.pink, .purple, .indigo])
    var isPlaying = true
    var position = 84.0
    var volume = 0.65
    var isShuffled = false
    var repeatOn = true
    var liked = false

    func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Styles

struct PlayerTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Subviews

struct PlayerArtwork: View {
    let colors: [Color]
    let isPlaying: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2).padding(40)
                    Circle().strokeBorder(.white.opacity(0.15), lineWidth: 2).padding(80)
                    Image(systemName: "music.note")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .shadow(color: colors[0].opacity(0.5), radius: 30, y: 18)
            .scaleEffect(isPlaying ? 1 : 0.85)
            .animation(.spring(duration: 0.5, bounce: 0.3), value: isPlaying)
            .accessibilityHidden(true)
    }
}

struct PlayerScrubber: View {
    @Binding var position: Double
    let duration: Double
    let format: (Double) -> String

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $position, in: 0...duration)
                .tint(.white)
                .accessibilityLabel("Playback position")
            HStack {
                Text(format(position))
                Spacer()
                Text("-" + format(duration - position))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Screen

struct MusicPlayerScreen: View {
    @State private var model: PlayerModel

    init(startPlaying: Bool = true) {
        let initial = PlayerModel()
        initial.isPlaying = startPlaying
        _model = State(initialValue: initial)
    }

    var body: some View {
        @Bindable var model = model
        ZStack {
            LinearGradient(colors: [model.track.colors[2], .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                PlayerArtwork(colors: model.track.colors, isPlaying: model.isPlaying)
                    .padding(.horizontal, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.track.title).font(.title2.bold())
                        Text(model.track.artist).font(.title3).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button { model.liked.toggle() } label: {
                        Image(systemName: model.liked ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(model.liked ? Color.pink : Color.white)
                    }
                    .accessibilityLabel(model.liked ? "Unlike" : "Like")
                }

                PlayerScrubber(position: $model.position, duration: model.track.duration, format: model.format)

                HStack(spacing: 44) {
                    Button { model.isShuffled.toggle() } label: {
                        Image(systemName: "shuffle").font(.title3)
                            .foregroundStyle(model.isShuffled ? Color.green : Color.white.opacity(0.6))
                    }
                    Button { model.position = 0 } label: {
                        Image(systemName: "backward.fill").font(.system(size: 30))
                    }
                    Button { withAnimation { model.isPlaying.toggle() } } label: {
                        Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    Button { model.position = min(model.position + 15, model.track.duration) } label: {
                        Image(systemName: "forward.fill").font(.system(size: 30))
                    }
                    Button { model.repeatOn.toggle() } label: {
                        Image(systemName: "repeat").font(.title3)
                            .foregroundStyle(model.repeatOn ? Color.green : Color.white.opacity(0.6))
                    }
                }
                .buttonStyle(PlayerTransportButtonStyle())
                .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $model.volume).tint(.white)
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

                HStack {
                    Button { } label: { Image(systemName: "airplayaudio") }
                    Spacer()
                    Button { } label: { Image(systemName: "quote.bubble") }
                    Spacer()
                    Button { } label: { Image(systemName: "list.bullet") }
                }
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MusicPlayerScreen()
}

#Preview("Paused") {
    MusicPlayerScreen(startPlaying: false)
}
