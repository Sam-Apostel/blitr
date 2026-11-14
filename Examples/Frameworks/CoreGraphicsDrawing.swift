import CoreGraphics
import SwiftUI
import UIKit

// Drawing with CGContext: a plain bitmap context (origin bottom-left, y up) and a
// UIGraphicsImageRenderer (origin top-left, in points).

enum Drawings {
    /// A plain bitmap context: the sun sits at the top because y points up.
    static func landscape(width: Int = 240, height: Int = 160) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let (w, h) = (CGFloat(width), CGFloat(height))

        // Sky.
        let sky = [CGColor(red: 0.98, green: 0.80, blue: 0.55, alpha: 1), CGColor(red: 0.25, green: 0.45, blue: 0.80, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        }
        // Sun with a glow.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 18, color: CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))
        context.setFillColor(red: 1, green: 0.93, blue: 0.6, alpha: 1)
        context.fillEllipse(in: CGRect(x: w - 70, y: h - 62, width: 40, height: 40))
        context.restoreGState()

        // Hills: two filled paths.
        context.setFillColor(red: 0.20, green: 0.45, blue: 0.30, alpha: 1)
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 55))
        context.addCurve(to: CGPoint(x: w, y: 40), control1: CGPoint(x: w * 0.3, y: 110), control2: CGPoint(x: w * 0.6, y: 10))
        context.addLine(to: CGPoint(x: w, y: 0))
        context.closePath()
        context.fillPath()

        context.setFillColor(red: 0.12, green: 0.33, blue: 0.22, alpha: 1)
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 25))
        context.addQuadCurve(to: CGPoint(x: w, y: 30), control: CGPoint(x: w * 0.55, y: 75))
        context.addLine(to: CGPoint(x: w, y: 0))
        context.closePath()
        context.fillPath()

        // A dashed path, stroked through a rotated transform.
        context.saveGState()
        context.translateBy(x: 40, y: 100)
        context.rotate(by: .pi / 12)
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [1, 7])
        context.addArc(center: .zero, radius: 22, startAngle: 0, endAngle: .pi, clockwise: false)
        context.strokePath()
        context.restoreGState()

        // Clipping: stripes inside a rounded rectangle.
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 14, y: 14, width: 56, height: 30), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.clip()
        for index in 0..<8 {
            context.setFillColor(gray: index % 2 == 0 ? 1 : 0.15, alpha: 0.85)
            context.fill(CGRect(x: 14 + CGFloat(index) * 7, y: 14, width: 7, height: 30))
        }
        context.restoreGState()
        return context.makeImage()
    }

    /// UIKit's renderer: points, origin top-left.
    static func badge(count: Int) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            UIColor.systemIndigo.setFill()
            context.fillEllipse(in: CGRect(origin: .zero, size: size))
            // Dots along the top half: top is y = 0 here.
            context.setFillColor(UIColor.white.cgColor)
            for index in 0..<count {
                let angle = CGFloat.pi * (1 + CGFloat(index + 1) / CGFloat(count + 1))
                let centre = CGPoint(x: 32 + cos(angle) * 20, y: 32 + sin(angle) * 20)
                context.fillEllipse(in: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8))
            }
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
        }
    }

    /// One image drawn into another, scaled down: what an upload "normalise" step does.
    static func thumbnail(of image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

#Preview("CGContext") {
    VStack(alignment: .leading, spacing: 16) {
        Text("Bitmap context").font(.headline)
        if let image = Drawings.landscape() {
            Image(decorative: image, scale: 1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        Text("UIGraphicsImageRenderer").font(.headline)
        HStack(spacing: 12) {
            ForEach(1..<5) { count in
                Image(uiImage: Drawings.badge(count: count))
            }
        }
        Text("Round trip: PNG data, decoded, redrawn at 24 px").font(.headline)
        HStack(spacing: 12) {
            let badge = Drawings.badge(count: 3)
            if let png = badge.pngData(), let decoded = UIImage(data: png) {
                Image(uiImage: decoded)
                Image(uiImage: Drawings.thumbnail(of: decoded, side: 24))
                Text("\(Int(decoded.size.width)) x \(Int(decoded.size.height)) px, \(png.count > 0 ? "PNG ok" : "empty")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
