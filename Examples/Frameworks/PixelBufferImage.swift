import CoreGraphics
import SwiftUI

// A placeholder image computed into a pixel buffer and handed to SwiftUI as a CGImage,
// the way blur-hash style placeholders are made: a few cosine terms per channel, 32 x 32 pixels,
// stretched to fill its slot.

enum SoftPlaceholder {
    static func image(seed: Int, side: Int = 32) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        // Three low-frequency terms per channel, chosen from the seed.
        func weight(_ channel: Int, _ term: Int) -> Double {
            let v = sin(Double(seed * 31 + channel * 17 + term * 7) * 12.9898) * 43758.5453
            return (v - v.rounded(.down)) - 0.5
        }
        for y in 0..<side {
            for x in 0..<side {
                let (u, v) = (Double(x) / Double(side - 1), Double(y) / Double(side - 1))
                for channel in 0..<3 {
                    var value = 0.55 + weight(channel, 0) * 0.4
                    value += weight(channel, 1) * cos(.pi * u)
                    value += weight(channel, 2) * cos(.pi * v)
                    value += weight(channel, 3) * cos(.pi * u) * cos(.pi * v)
                    pixels[(y * side + x) * 4 + channel] = UInt8(max(0, min(255, value * 255)))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct PlaceholderTile: View {
    let seed: Int
    var body: some View {
        if let image = SoftPlaceholder.image(seed: seed) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
        } else {
            Color.gray
        }
    }
}

/// Four pixels, shown unsmoothed: red, green / blue, white, in an RGBA buffer with straight alpha.
struct FourPixels: View {
    var body: some View {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                              0, 0, 255, 255, 255, 255, 255, 128]
        if let provider = CGDataProvider(data: Data(bytes) as CFData),
           let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            Image(image, scale: 1, label: Text("Four pixels"))
                .resizable()
                .interpolation(.none)
        }
    }
}

#Preview("Pixel buffers") {
    VStack(alignment: .leading, spacing: 16) {
        Text("Placeholders from pixel buffers").font(.headline)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(1..<7) { seed in
                PlaceholderTile(seed: seed)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        Text("Unsmoothed 2 x 2").font(.headline)
        FourPixels()
            .frame(width: 120, height: 120)
            .border(Color.secondary)
    }
    .padding()
}
