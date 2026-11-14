import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// QR codes and Code 128 barcodes from Core Image's generators, scaled by whole numbers so the
// modules stay crisp, as ticket and boarding-pass screens draw them.

enum Barcode {
    static let context = CIContext()

    static func qr(_ text: String, level: String = "M", side: CGFloat = 200) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = level
        return image(filter.outputImage, side: side)
    }

    static func code128(_ text: String, side: CGFloat = 300) -> UIImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(text.utf8)
        filter.quietSpace = 4
        return image(filter.outputImage, side: side)
    }

    /// The generator's one-pixel-per-module output, scaled up by a whole number.
    static func image(_ output: CIImage?, side: CGFloat) -> UIImage? {
        guard let output, output.extent.width > 0 else { return nil }
        let scale = max(1, (side / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The same generator through `CIFilter(name:)` and key-value parameters.
func namedQR(_ text: String) -> CGImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)) else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
}

struct BarcodeTile: View {
    let title: String
    let image: UIImage?
    var body: some View {
        VStack(spacing: 6) {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            }
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

#Preview("Barcodes") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("QR codes").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                BarcodeTile(title: "L, short", image: Barcode.qr("HELLO", level: "L", side: 90))
                    .frame(width: 90)
                BarcodeTile(title: "M, URL", image: Barcode.qr("https://example.com/trip/2026/boarding?seat=12A", side: 120))
                    .frame(width: 120)
                if let named = namedQR("CIFilter(name:) with H") {
                    BarcodeTile(title: "H, by name", image: UIImage(cgImage: named)).frame(width: 110)
                }
            }
            BarcodeTile(title: "Q, 300 bytes (version 13)", image: Barcode.qr(String(repeating: "Gate B12 seat 14C ", count: 17), level: "Q", side: 330))
                .frame(width: 330)
            Text("Code 128").font(.headline)
            BarcodeTile(title: "letters and digits", image: Barcode.code128("TICKET-2026-0042", side: 330))
                .frame(height: 70)
            BarcodeTile(title: "digits (code set C)", image: Barcode.code128("123456789012", side: 200))
                .frame(height: 60)
        }
        .padding()
    }
}
