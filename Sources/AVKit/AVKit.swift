// `import AVKit`: VideoPlayer is drawn as a black player surface with its controls; nothing plays.
@_exported import SwiftUI
@_exported import AVFoundation

public struct VideoPlayer<VideoOverlay: View>: View {
    let overlay: VideoOverlay?
    public init(player: AVPlayer?) where VideoOverlay == EmptyView { overlay = nil }
    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> VideoOverlay) { overlay = videoOverlay() }
    public var body: some View {
        ZStack {
            Color.black
            Image(systemName: "play.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.9))
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Text("0:00").font(.caption2.monospacedDigit())
                    Capsule().fill(Color.white.opacity(0.35)).frame(height: 4)
                    Text("-0:00").font(.caption2.monospacedDigit())
                }
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(10)
            }
            if let overlay { overlay }
        }
        .onAppear { ShimDiagnostics.warn("VideoPlayer: video is not decoded here; drawn as a player with nothing loaded") }
    }
}

open class AVPlayerViewController: NSObject {
    open var player: AVPlayer?
    open var showsPlaybackControls = true
    open var videoGravity = "AVLayerVideoGravityResizeAspect"
    public override init() { super.init() }
}
