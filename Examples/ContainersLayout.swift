import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.indigo.opacity(0.15), in: Capsule())
    }
}

struct Demo: View {
    let tags = ["Swift", "SwiftUI", "Linux", "Skia", "Layout", "Rendering", "Headless", "PNG", "Containers", "Grid"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Flow layout").font(.headline)
                FlowLayout { ForEach(tags, id: \.self) { Tag(text: $0) } }

                Text("ViewThatFits").font(.headline)
                ViewThatFits {
                    HStack { Text("This is a rather long wide label that cannot fit"); Image(systemName: "star") }
                    HStack { Text("Medium label that also is too wide for it") }
                    VStack { Text("Compact"); Text("variant") }
                }
                .padding(8).background(Color.green.opacity(0.2))

                Text("AnyLayout").font(.headline)
                let layout = AnyLayout(HStackLayout(spacing: 20))
                layout { Circle().fill(.red).frame(width: 40, height: 40); Circle().fill(.blue).frame(width: 40, height: 40); Text("hi") }

                Text("Canvas").font(.headline)
                Canvas { ctx, size in
                    ctx.fill(Path(ellipseIn: CGRect(x: 10, y: 10, width: 80, height: 80)), with: .color(.orange))
                    ctx.stroke(Path(roundedRect: CGRect(x: 100, y: 10, width: 100, height: 80), cornerRadius: 12), with: .color(.blue), lineWidth: 4)
                    ctx.fill(Path(CGRect(x: 210, y: 10, width: 100, height: 80)),
                             with: .linearGradient(Gradient(colors: [.pink, .purple]), startPoint: CGPoint(x: 210, y: 10), endPoint: CGPoint(x: 310, y: 90)))
                    ctx.draw(Text("Canvas text").font(.headline), at: CGPoint(x: size.width / 2, y: 120))
                    var c2 = ctx
                    c2.translateBy(x: 40, y: 140)
                    c2.rotate(by: .degrees(15))
                    c2.opacity = 0.5
                    c2.fill(Path(CGRect(x: 0, y: 0, width: 60, height: 30)), with: .color(.green))
                    var c3 = ctx
                    c3.addFilter(.blur(radius: 4))
                    c3.fill(Path(ellipseIn: CGRect(x: 200, y: 130, width: 60, height: 40)), with: .color(.red))
                }
                .frame(height: 190)
                .background(Color.gray.opacity(0.1))

                TimelineView(.everyMinute) { context in
                    Text(context.date, style: .time)
                }
            }
            .padding()
        }
    }
}

#Preview { Demo() }
