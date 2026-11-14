import PDFKit
import SwiftUI
import UIKit

// UIViewRepresentable and UIViewControllerRepresentable: image views, labels, spinners, blur views and
// hosting controllers are drawn; anything else is a placeholder of its proposed size that names the
// wrapped class (and warns once).

struct PhotoView: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {}
}

struct CaptionLabel: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {}
}

struct Spinner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .large)
        view.startAnimating()
        return view
    }
    func updateUIView(_ view: UIActivityIndicatorView, context: Context) {}
}

struct BlurBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)) }
    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}

struct Hosted: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIHostingController<Text> { UIHostingController(rootView: Text("Hosted SwiftUI text")) }
    func updateUIViewController(_ controller: UIHostingController<Text>, context: Context) {}
}

struct DocumentView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

/// A gradient drawn with UIGraphicsImageRenderer, as the photo.
let samplePhoto: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { context in
    let colors = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor, UIColor.systemIndigo.cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1])!
    context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 200), options: [])
    UIColor.white.withAlphaComponent(0.8).setFill()
    context.cgContext.fillEllipse(in: CGRect(x: 200, y: 30, width: 50, height: 50))
}

#Preview("Representables") {
    VStack(spacing: 16) {
        ZStack(alignment: .bottomLeading) {
            PhotoView(image: samplePhoto).frame(height: 160)
            BlurBackdrop().frame(height: 44).overlay(Text("Blur over the photo").font(.subheadline))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        CaptionLabel(text: "A UILabel, measured and drawn as text").frame(height: 24)
        HStack { Spinner(); Hosted() }
        DocumentView().frame(height: 120)
    }
    .padding()
}
