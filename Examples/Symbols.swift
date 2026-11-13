import SwiftUI

struct SymbolCell: View {
    let name: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: name)
                .font(.title)
                .frame(height: 36)
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SymbolRow: View {
    let names: [String]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(names, id: \.self) { SymbolCell(name: $0) }
        }
    }
}

struct SymbolsShowcase: View {
    let outline = [
        ["house", "gearshape", "magnifyingglass", "bell", "person", "heart"],
        ["star", "bookmark", "trash", "pencil", "square.and.pencil", "square.and.arrow.up"],
        ["paperplane", "envelope", "phone", "message", "bubble.left", "camera"],
        ["photo", "video", "mic", "play", "pause", "stop"],
        ["calendar", "clock", "map", "mappin", "location", "globe"],
        ["link", "lock", "key", "eye", "eye.slash", "cart"],
        ["bag", "creditcard", "tag", "gift", "folder", "doc"],
        ["doc.text", "tray", "archivebox", "paperclip", "cloud", "sun.max"],
        ["moon", "bolt", "flame", "drop", "leaf", "wifi"],
        ["battery.100", "airplane", "car", "bicycle", "figure.walk", "flag"],
    ]
    let filled = [
        ["house.fill", "gearshape.fill", "bell.fill", "person.fill", "heart.fill", "star.fill"],
        ["bookmark.fill", "trash.fill", "pencil.circle.fill", "envelope.fill", "phone.fill", "message.fill"],
        ["camera.fill", "photo.fill", "video.fill", "mic.fill", "play.fill", "pause.fill"],
        ["calendar.circle.fill", "clock.fill", "map.fill", "mappin.circle.fill", "location.fill", "lock.fill"],
        ["key.fill", "eye.fill", "cart.fill", "bag.fill", "tag.fill", "gift.fill"],
        ["folder.fill", "doc.fill", "tray.fill", "cloud.fill", "moon.fill", "bolt.fill"],
        ["flame.fill", "drop.fill", "leaf.fill", "car.fill", "flag.fill", "hand.thumbsup.fill"],
    ]
    let circles = [
        ["info.circle", "questionmark.circle", "exclamationmark.triangle", "checkmark.circle", "xmark.circle", "plus.circle"],
        ["minus.circle", "ellipsis.circle", "line.3.horizontal", "slider.horizontal.3", "list.bullet", "square.grid.2x2"],
        ["chart.bar", "qrcode", "faceid", "hand.thumbsup", "checkmark.circle.fill", "xmark.circle.fill"],
        ["heart.circle", "star.circle.fill", "bell.slash", "person.crop.circle", "house.circle.fill", "wifi.slash"],
    ]
    let chrome = [
        ["chevron.right", "chevron.left", "chevron.up", "chevron.down", "chevron.up.chevron.down", "chevron.compact.down"],
        ["checkmark", "xmark", "plus", "minus", "ellipsis", "circle"],
        ["circle.fill", "square", "square.fill", "arrow.right", "arrow.left", "arrow.up"],
        ["arrow.down", "arrow.up.right", "arrow.clockwise", "line.3.horizontal", "magnifyingglass", "chevron.backward"],
    ]

    var body: some View {
        VStack(spacing: 10) {
            Text("Outline").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(outline, id: \.self) { SymbolRow(names: $0) }
            Text("Fill").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(filled, id: \.self) { SymbolRow(names: $0) }
            Text("Status and variants").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(circles, id: \.self) { SymbolRow(names: $0) }
            Text("Hand-drawn chrome").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(chrome, id: \.self) { SymbolRow(names: $0) }

            Text("Sizes and weights").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                Image(systemName: "heart.fill").font(.caption)
                Image(systemName: "heart.fill").font(.footnote)
                Image(systemName: "heart.fill").font(.body)
                Image(systemName: "heart.fill").font(.title2)
                Image(systemName: "heart.fill").font(.largeTitle)
                Image(systemName: "gearshape").font(.system(size: 28, weight: .light))
                Image(systemName: "gearshape").font(.system(size: 28, weight: .regular))
                Image(systemName: "gearshape").font(.system(size: 28, weight: .bold))
            }
            HStack(spacing: 14) {
                Image(systemName: "chevron.right").font(.system(size: 28, weight: .light))
                Image(systemName: "chevron.right").font(.system(size: 28, weight: .regular))
                Image(systemName: "chevron.right").font(.system(size: 28, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 28, weight: .bold))
                Image(systemName: "checkmark").font(.system(size: 28, weight: .regular))
                Image(systemName: "checkmark").font(.system(size: 28, weight: .bold))
            }
            HStack(spacing: 14) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Image(systemName: "bolt.fill").foregroundStyle(.orange)
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Image(systemName: "moon.stars.fill").foregroundStyle(.purple)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.title2)

            Text("Inline with text").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Image(systemName: "location.fill"); Text("Brussels, Belgium") }
                HStack(spacing: 6) { Image(systemName: "clock"); Text("Updated 5 minutes ago").foregroundStyle(.secondary) }
                HStack(spacing: 6) { Image(systemName: "gearshape"); Text("Settings") }
                HStack(spacing: 6) { Image(systemName: "heart.fill"); Text("Favourites") }.foregroundStyle(.pink)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

#Preview {
    SymbolsShowcase()
}
