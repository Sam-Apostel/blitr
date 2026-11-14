// An Apple Watch app: render with `--device apple-watch` (Series 10 46mm), `apple-watch-series-10-42mm`
// or `apple-watch-ultra-2`, or `--platform watchos`. watchOS is drawn dark, with the time in the corner.
//
//   swiftui-screenshot render Examples/Watch.swift --device apple-watch --all --out-dir out/watch
import SwiftUI

struct WatchTimerPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tea")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("3:45")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Green, 80°")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Pause") {}
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(Color.orange.opacity(0.35).gradient, for: .tabView)
    }
}

struct WatchSwatchPage: View {
    // watchOS has a small UIKit: UIImage and UIColor are visible with only `import SwiftUI`.
    private let swatch = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
    private let photo: UIImage? = UIImage(contentsOfFile: "/no/such/photo.jpg")

    var body: some View {
        VStack(spacing: 8) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(Color(uiColor: swatch)).frame(width: 64, height: 64)
            }
            Text("Steeped")
                .font(.title3)
            Button("Stop", role: .destructive) {}
        }
    }
}

struct WatchPagedApp: View {
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WatchTimerPage().tag(0)
            WatchSwatchPage().tag(1)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview("Timer") {
    WatchPagedApp()
}

#Preview("Swatch") {
    WatchSwatchPage()
}

#Preview("Text styles") {
    ScrollView {
        VStack(alignment: .leading, spacing: 2) {
            Text("Title").font(.title)
            Text("Title 3").font(.title3)
            Text("Headline").font(.headline)
            Text("Body text that wraps onto a second line").font(.body)
            Text("Footnote").font(.footnote).foregroundStyle(.secondary)
            Text("Caption 2").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
