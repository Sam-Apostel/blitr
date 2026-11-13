// Hand-authored SF-proportioned glyphs for system chrome. All are drawn in a viewBox 24 units tall
// (width varies) as centre-line strokes with round caps and joins; stroke width follows font weight.

enum HandDrawnSymbols {
    /// Stroke width in viewBox units for a font weight (100...900); 400 is roughly SF "regular".
    static func strokeWidth(for weight: CGFloat) -> CGFloat {
        min(3.4, max(1.1, 1.1 + (weight - 100) / 800 * 2.1 + 0.2))
    }

    static func make(_ name: String, weight: CGFloat) -> SymbolArt? {
        let w = strokeWidth(for: weight)
        let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        func pts(_ points: [(CGFloat, CGFloat)], close: Bool = false) -> Path {
            var p = Path()
            for (i, q) in points.enumerated() {
                let pt = CGPoint(x: q.0, y: q.1)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            if close { p.closeSubpath() }
            return p
        }
        func stroked(_ paths: Path..., width: CGFloat, height: CGFloat = 24) -> SymbolArt {
            (CGSize(width: width, height: height), paths.map { .init(path: $0, stroke: style, evenOdd: false) })
        }
        func solid(_ path: Path, width: CGFloat = 24) -> SymbolArt {
            (CGSize(width: width, height: 24), [.init(path: path, stroke: nil, evenOdd: false)])
        }
        func arrow(shaft: [(CGFloat, CGFloat)], head: [(CGFloat, CGFloat)]) -> SymbolArt {
            stroked(pts(shaft), pts(head), width: 24)
        }

        switch name {
        // Chevrons: ~6 x 14 units of ink, like the list disclosure indicator.
        case "chevron.right", "chevron.forward", "chevron.right.fill":
            return stroked(pts([(3.5, 5), (9.5, 12), (3.5, 19)]), width: 13)
        case "chevron.left", "chevron.backward":
            return stroked(pts([(9.5, 5), (3.5, 12), (9.5, 19)]), width: 13)
        case "chevron.up":
            return stroked(pts([(3, 14.5), (10, 8.5), (17, 14.5)]), width: 20)
        case "chevron.down":
            return stroked(pts([(3, 9.5), (10, 15.5), (17, 9.5)]), width: 20)
        case "chevron.up.chevron.down":
            return stroked(pts([(7, 9.5), (12, 5), (17, 9.5)]), pts([(7, 14.5), (12, 19), (17, 14.5)]), width: 24)
        case "chevron.compact.down":
            return stroked(pts([(3.5, 10), (12, 14), (20.5, 10)]), width: 24)
        case "chevron.compact.up":
            return stroked(pts([(3.5, 14), (12, 10), (20.5, 14)]), width: 24)
        case "chevron.compact.right":
            return stroked(pts([(9, 3.5), (13, 12), (9, 20.5)]), width: 24)
        case "chevron.compact.left":
            return stroked(pts([(15, 3.5), (11, 12), (15, 20.5)]), width: 24)

        case "checkmark":
            return stroked(pts([(4.5, 12.8), (9.4, 18), (19.5, 5.8)]), width: 24)
        case "xmark":
            return stroked(pts([(6, 6), (18, 18)]), pts([(18, 6), (6, 18)]), width: 24)
        case "plus":
            return stroked(pts([(12, 4.5), (12, 19.5)]), pts([(4.5, 12), (19.5, 12)]), width: 24)
        case "minus":
            return stroked(pts([(4.5, 12), (19.5, 12)]), width: 24)
        case "ellipsis":
            var dots = Path()
            let r = w * 0.62
            for x: CGFloat in [4.5, 12, 19.5] { dots.addEllipse(in: CGRect(x: x - r, y: 12 - r, width: 2 * r, height: 2 * r)) }
            return solid(dots)
        case "circle":
            return stroked(Path(ellipseIn: CGRect(x: 2.9, y: 2.9, width: 18.2, height: 18.2)), width: 24)
        case "circle.fill":
            return solid(Path(ellipseIn: CGRect(x: 1.9, y: 1.9, width: 20.2, height: 20.2)))
        case "square":
            return stroked(Path(roundedRect: CGRect(x: 3.4, y: 3.4, width: 17.2, height: 17.2), cornerRadius: 4, style: .continuous), width: 24)
        case "square.fill":
            return solid(Path(roundedRect: CGRect(x: 2.4, y: 2.4, width: 19.2, height: 19.2), cornerRadius: 4.6, style: .continuous))

        case "arrow.right":
            return arrow(shaft: [(4, 12), (20, 12)], head: [(13.5, 5.5), (20, 12), (13.5, 18.5)])
        case "arrow.left":
            return arrow(shaft: [(20, 12), (4, 12)], head: [(10.5, 5.5), (4, 12), (10.5, 18.5)])
        case "arrow.up":
            return arrow(shaft: [(12, 20), (12, 4)], head: [(5.5, 10.5), (12, 4), (18.5, 10.5)])
        case "arrow.down":
            return arrow(shaft: [(12, 4), (12, 20)], head: [(5.5, 13.5), (12, 20), (18.5, 13.5)])
        case "arrow.up.right":
            return arrow(shaft: [(6, 18), (18, 6)], head: [(8.5, 6), (18, 6), (18, 15.5)])
        case "arrow.clockwise", "arrow.counterclockwise":
            let art = clockwiseArrow(style: style)
            if name == "arrow.clockwise" { return art }
            let mirror = CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: 24, y: 0))
            return (art.viewBox, art.layers.map { var l = $0; l.path = l.path.applying(mirror); return l })

        case "line.3.horizontal":
            return stroked(pts([(4, 6.5), (20, 6.5)]), pts([(4, 12), (20, 12)]), pts([(4, 17.5), (20, 17.5)]), width: 24)
        case "magnifyingglass":
            return stroked(Path(ellipseIn: CGRect(x: 3.6, y: 3.6, width: 12.8, height: 12.8)), pts([(14.8, 14.8), (20.4, 20.4)]), width: 24)
        default:
            return nil
        }
    }

    /// An open circular arc with a chevron arrowhead (SF `arrow.clockwise`).
    private static func clockwiseArrow(style: StrokeStyle) -> SymbolArt {
        let c = CGPoint(x: 12, y: 12), r: CGFloat = 8
        let start = 20.0 * .pi / 180, sweep = 290.0 * .pi / 180
        var arc = Path()
        let steps = 48
        for i in 0...steps {
            let a = start + sweep * Double(i) / Double(steps)
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
        }
        let end = start + sweep
        let tip = CGPoint(x: c.x + r * CGFloat(cos(end)), y: c.y + r * CGFloat(sin(end)))
        let tangent = CGPoint(x: -CGFloat(sin(end)), y: CGFloat(cos(end)))   // direction of travel
        let normal = CGPoint(x: CGFloat(cos(end)), y: CGFloat(sin(end)))     // radial
        // Chevron head sitting on the arc end, opening backwards.
        func arm(_ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - tangent.x * 4.2 + normal.x * 4.4 * side + tangent.x * 1.2,
                    y: tip.y - tangent.y * 4.2 + normal.y * 4.4 * side + tangent.y * 1.2)
        }
        let apex = CGPoint(x: tip.x + tangent.x * 1.2, y: tip.y + tangent.y * 1.2)
        var head = Path()
        head.move(to: arm(1)); head.addLine(to: apex); head.addLine(to: arm(-1))
        return (CGSize(width: 24, height: 24),
                [.init(path: arc, stroke: style, evenOdd: false), .init(path: head, stroke: style, evenOdd: false)])
    }
}
