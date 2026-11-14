import AVKit
import SwiftUI

// VideoPlayer is drawn as a player with nothing loaded: a black surface, the play glyph and the
// playback bar. Nothing is decoded or played.

#Preview("Video player") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Trailer").font(.headline)
        VideoPlayer(player: AVPlayer(url: URL(string: "https://example.com/trailer.m4v")!))
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        VideoPlayer(player: nil) {
            VStack { Text("Overlay").font(.caption).padding(6).background(.ultraThinMaterial, in: Capsule()); Spacer() }.padding()
        }
        .frame(height: 140)
    }
    .padding()
}
