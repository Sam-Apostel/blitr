import SwiftUI
import UIKit

// ImageRenderer: a view rendered to an image (a share card, an export), shown again through
// Image(uiImage:) and Image(decorative:scale:). The rendered pixels are the view's own.

struct ShareCard: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "trophy.fill").font(.headline)
            Text("12.4 km in 58:21").font(.title2.bold())
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(index < 4 ? Color.green : Color.gray.opacity(0.3)).frame(width: 30, height: 6)
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [.yellow.opacity(0.5), .orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ImageRendererExample: View {
    @Environment(\.displayScale) private var displayScale
    @State private var exported: UIImage?

    var body: some View {
        VStack(spacing: 18) {
            Text("The view").font(.caption).foregroundStyle(.secondary)
            ShareCard(title: "Morning run")

            Text("ImageRenderer.uiImage at display scale").font(.caption).foregroundStyle(.secondary)
            if let exported {
                Image(uiImage: exported)
                Text("\(Int(exported.size.width)) x \(Int(exported.size.height)) pt at \(Int(exported.scale))x")
                    .font(.footnote.monospacedDigit())
            }

            Text("cgImage at 1x, drawn resizable at half size").font(.caption).foregroundStyle(.secondary)
            if let cgImage = smallRenderer.cgImage {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 50)
                    .border(.gray)
            }

            Text("proposedSize 300 x 60, opaque").font(.caption).foregroundStyle(.secondary)
            if let wide = wideImage {
                Image(uiImage: wide)
            }
        }
        .padding()
        .onAppear { exported = makeExport() }
    }

    @MainActor private func makeExport() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(title: "Morning run"))
        renderer.scale = displayScale
        return renderer.uiImage
    }

    private var smallRenderer: ImageRenderer<ShareCard> {
        ImageRenderer(content: ShareCard(title: "Evening ride"))
    }

    private var wideImage: UIImage? {
        let renderer = ImageRenderer(content: Text("Fills the proposal").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity))
        renderer.proposedSize = ProposedViewSize(width: 300, height: 60)
        renderer.isOpaque = true
        renderer.scale = 2
        renderer.colorMode = .nonLinear
        return renderer.uiImage
    }
}

#Preview("ImageRenderer") {
    ImageRendererExample()
}
