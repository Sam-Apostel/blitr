// Drawing a `Map`: placeholder surface, overlays, pins, controls and attribution.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// Colours of the placeholder surface, after Apple Maps' palettes.
struct MapPalette {
    var land: Color
    var grid: Color
    var label: Color
    var halo: Color
    var attribution: Color

    static func resolve(_ style: MapStyle, _ scheme: ColorScheme) -> MapPalette {
        let dark = scheme == .dark
        switch style.base {
        case .imagery, .hybrid:
            return MapPalette(land: Color(red: 0.235, green: 0.255, blue: 0.227), grid: Color.white.opacity(0.07),
                              label: .white, halo: Color.black.opacity(0.55), attribution: Color.white.opacity(0.85))
        case .standard:
            if dark {
                let land = style.emphasis.muted ? Color(red: 0.157, green: 0.161, blue: 0.169) : Color(red: 0.176, green: 0.180, blue: 0.192)
                return MapPalette(land: land, grid: Color.white.opacity(0.055), label: Color(white: 0.92),
                                  halo: Color.black.opacity(0.75), attribution: Color.white.opacity(0.6))
            }
            let land = style.emphasis.muted ? Color(red: 0.961, green: 0.957, blue: 0.945) : Color(red: 0.969, green: 0.957, blue: 0.929)
            return MapPalette(land: land, grid: Color.black.opacity(0.05), label: Color(white: 0.18),
                              halo: Color.white.opacity(0.95), attribution: Color.black.opacity(0.55))
        }
    }
}

struct MapSurface: View {
    let config: MapConfiguration
    @Environment(\.mapStyle) private var style
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mapControls) private var controls
    @Environment(\.mapCameraChangeActions) private var cameraActions
    @Environment(\.mapProxyStorage) private var proxyStorage
    @Environment(\.designLanguage) private var design
    @Environment(\.renderPlatform) private var platform

    var body: some View {
        // The surface runs under the bars like MapKit's; controls and framing keep to the safe area.
        // The safe area is measured as the difference between the two readers' frames.
        GeometryReader { safe in
            GeometryReader { full in
                surface(full, safeArea: Self.insets(of: safe.frame(in: .global), within: full.frame(in: .global)))
            }
            .ignoresSafeArea()
        }
    }

    static func insets(of safe: CGRect, within full: CGRect) -> EdgeInsets {
        EdgeInsets(top: max(0, safe.minY - full.minY), leading: max(0, safe.minX - full.minX),
                   bottom: max(0, full.maxY - safe.maxY), trailing: max(0, full.maxX - safe.maxX))
    }

    private var markerScale: Double { platform == .tvOS ? 1.6 : 1 }

    private func surface(_ geo: GeometryProxy, safeArea: EdgeInsets) -> some View {
        let elements = config.collect()
        let projection = MapProjection.resolve(config.position, elements: elements, size: geo.size, bounds: config.bounds,
                                               markerScale: markerScale, safeArea: safeArea)
        proxyStorage?.projection = projection
        proxyStorage?.geometry = geo
        Runtime.current?.warn("Map: map tiles are not drawn (no map data on Linux); the app's markers, annotations and overlays are drawn on a placeholder surface.")
        let palette = MapPalette.resolve(style, scheme)
        let pins = MapPins.build(elements, projection: projection, selection: config.selection, palette: palette, scale: markerScale)
        let actions = cameraActions
        let context = projection.context
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                MapPainter(projection: projection, palette: palette).draw(elements, in: &ctx, size: size)
            }
            MapPinLayout {
                ForEach(pins.indices, id: \.self) { i in
                    pins[i].view.layoutValue(key: MapPinKey.self, value: pins[i].placement)
                }
            }
            if platform != .tvOS, let controls {
                MapControlsOverlay(controls: controls, projection: projection, safeArea: safeArea)
            }
            MapAttribution(palette: palette, glass: design.isGlass, scale: markerScale)
                .padding(.leading, 8 + safeArea.leading)
                .padding(.bottom, 6 + safeArea.bottom)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .clipped()
        .onAppear { for action in actions { action(context) } }
    }
}

// MARK: - Overlays

struct MapPainter {
    let projection: MapProjection
    let palette: MapPalette

    func draw(_ elements: [MapElement], in ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.land))
        drawGraticule(in: &ctx, size: size)
        for level in [MKOverlayLevel.aboveRoads, .aboveLabels] {
            for element in elements where element.isOverlay && element.overlayLevel == level { drawOverlay(element, in: &ctx) }
        }
    }

    /// Faint parallels and meridians at a round spacing of roughly 90-180 points.
    private func drawGraticule(in ctx: inout GraphicsContext, size: CGSize) {
        let degreesPerPoint = 360 / (MapProjection.world * projection.scale)
        let steps: [Double] = [0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30]
        let step = steps.first { $0 / degreesPerPoint >= 64 } ?? 30
        let rect = projection.visibleRect
        let nw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate, se = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        var path = Path()
        let lonStart = (rect.minX / MapProjection.world * 360 - 180) / step
        let lonEnd = (rect.maxX / MapProjection.world * 360 - 180) / step
        for i in Int(floor(lonStart))...Int(ceil(lonEnd)) {
            let x = (Double(i) * step + 180) / 360 * MapProjection.world
            let line = projection.points([MKMapPoint(x: x, y: rect.minY), MKMapPoint(x: x, y: rect.maxY)])
            path.move(to: line[0]); path.addLine(to: line[1])
        }
        let latLow = max(-85, se.latitude), latHigh = min(85, nw.latitude)
        if latLow < latHigh {
            for i in Int(floor(latLow / step))...Int(ceil(latHigh / step)) {
                let y = MKMapPoint(CLLocationCoordinate2D(latitude: Double(i) * step, longitude: 0)).y
                let line = projection.points([MKMapPoint(x: rect.minX, y: y), MKMapPoint(x: rect.maxX, y: y)])
                path.move(to: line[0]); path.addLine(to: line[1])
            }
        }
        ctx.stroke(path, with: .color(palette.grid), lineWidth: 0.75)
    }

    private func path(_ run: [MKMapPoint], closed: Bool) -> Path {
        var p = Path()
        let pts = projection.points(run)
        guard let first = pts.first else { return p }
        p.move(to: first)
        for q in pts.dropFirst() { p.addLine(to: q) }
        if closed { p.closeSubpath() }
        return p
    }

    private func drawOverlay(_ e: MapElement, in ctx: inout GraphicsContext) {
        let accent = Color.accentColor
        switch e.kind {
        case .polyline(let pts):
            let shape = path(pts, closed: false)
            let style = e.strokeStyle ?? StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            ctx.stroke(shape, with: .style(e.stroke ?? e.fill ?? e.tintStyle ?? AnyShapeStyle(e.tintColor ?? accent)), style: style)
        case .polygon(let pts, let holes):
            var shape = path(pts, closed: true)
            for hole in holes { shape.addPath(path(hole, closed: true)) }
            fillAndStroke(shape, e, in: &ctx, accent: accent)
        case .circle(let center, let radius):
            let ring = MKCircle(center: center, radius: radius).ring().map(MKMapPoint.init)
            fillAndStroke(path(ring, closed: true), e, in: &ctx, accent: accent)
        default: break
        }
    }

    private func fillAndStroke(_ shape: Path, _ e: MapElement, in ctx: inout GraphicsContext, accent: Color) {
        let fill = e.fill ?? e.tintStyle ?? AnyShapeStyle((e.tintColor ?? accent).opacity(e.stroke == nil ? 0.3 : 0.2))
        ctx.fill(shape, with: .style(fill), style: FillStyle(eoFill: true))
        if let stroke = e.stroke {
            ctx.stroke(shape, with: .style(stroke), style: e.strokeStyle ?? StrokeStyle(lineWidth: 1))
        } else if let style = e.strokeStyle {
            ctx.stroke(shape, with: .style(e.tintColor ?? accent), style: style)
        }
    }
}

// MARK: - Pins

struct MapPinPlacement {
    enum Role { case content, titleBelowPrevious }
    var point: CGPoint
    var anchor: UnitPoint
    var role: Role
    var maxWidth: CGFloat?
}

enum MapPinKey: LayoutValueKey {
    static let defaultValue = MapPinPlacement(point: .zero, anchor: .center, role: .content)
}

/// Places each subview with its anchor on its projected point; titles go centered below the
/// view placed just before them.
struct MapPinLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Pass 1: where every pin goes. Pass 2: titles below their pin, left out (as MapKit does)
        // when they would cover another pin or a title already shown.
        var frames: [CGRect] = []
        var proposals: [ProposedViewSize] = []
        var owner: [Int] = []
        var previous = -1
        for (index, subview) in subviews.enumerated() {
            let placement = subview[MapPinKey.self]
            var size = subview.sizeThatFits(.unspecified)
            if let maxWidth = placement.maxWidth, size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            proposals.append(ProposedViewSize(size))
            switch placement.role {
            case .content:
                frames.append(CGRect(x: placement.point.x - placement.anchor.x * size.width,
                                     y: placement.point.y - placement.anchor.y * size.height, width: size.width, height: size.height))
                owner.append(index)
                previous = index
            case .titleBelowPrevious:
                let pin = previous >= 0 ? frames[previous] : .zero
                frames.append(CGRect(x: pin.midX - size.width / 2, y: pin.maxY + 1, width: size.width, height: size.height))
                owner.append(previous)
            }
        }
        var shownTitles: [CGRect] = []
        for (index, subview) in subviews.enumerated() {
            var rect = frames[index]
            if subview[MapPinKey.self].role == .titleBelowPrevious {
                let padded = rect.insetBy(dx: -2, dy: -1)
                let coversPin = subviews.indices.contains { other in
                    other != owner[index] && subviews[other][MapPinKey.self].role == .content
                        && frames[other].insetBy(dx: 3, dy: 3).intersects(padded)
                }
                if coversPin || shownTitles.contains(where: { $0.intersects(padded) }) {
                    rect.origin = CGPoint(x: -100_000, y: -100_000)
                } else {
                    shownTitles.append(rect)
                }
            }
            subview.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading, proposal: proposals[index])
        }
    }
}

struct MapPinItem {
    var view: AnyView
    var placement: MapPinPlacement
}

enum MapPins {
    @MainActor
    static func build(_ elements: [MapElement], projection: MapProjection, selection: AnyHashable?, palette: MapPalette,
                      scale: Double) -> [MapPinItem] {
        var pins: [MapPinItem] = []
        let center = CGPoint(x: projection.size.width / 2, y: projection.size.height / 2)
        for e in elements where !e.isOverlay {
            let point: CGPoint
            if case .userLocation = e.kind { point = center } else if let c = e.coordinate { point = projection.point(c) } else { continue }
            // Skip pins far outside the frame (they would only cost layout time).
            let margin = 200.0
            guard point.x > -margin, point.y > -margin, point.x < projection.size.width + margin,
                  point.y < projection.size.height + margin else { continue }
            let selected = selection != nil && e.tag == selection
            switch e.kind {
            case .marker(let glyph):
                let tint = e.tintColor ?? Color(red: 1, green: 0.231, blue: 0.188)
                pins.append(MapPinItem(view: AnyView(MarkerBalloon(tint: tint, style: e.tintStyle, glyph: glyph,
                                                               size: (selected ? 1.4 : 1) * scale)),
                                   placement: MapPinPlacement(point: point, anchor: .bottom, role: .content)))
            case .legacyPin:
                pins.append(MapPinItem(view: AnyView(LegacyPin(tint: e.tintColor ?? .red, scale: scale)),
                                   placement: MapPinPlacement(point: point, anchor: UnitPoint(x: 0.5, y: 1), role: .content)))
            case .annotation(let anchor, let content):
                pins.append(MapPinItem(view: content, placement: MapPinPlacement(point: point, anchor: anchor, role: .content)))
            case .userLocation(let anchor, let content):
                pins.append(MapPinItem(view: content ?? AnyView(UserLocationDot()),
                                   placement: MapPinPlacement(point: point, anchor: anchor, role: .content)))
            default: continue
            }
            if e.hasTitle, e.titles != .hidden {
                let label: AnyView
                if let title = e.title {
                    label = AnyView(MapLabel(text: title, palette: palette, bold: selected, scale: scale))
                } else if let view = e.titleView {
                    label = AnyView(view.font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(palette.label))
                } else { continue }
                pins.append(MapPinItem(view: label, placement: MapPinPlacement(point: point, anchor: .top, role: .titleBelowPrevious,
                                                                           maxWidth: 120 * scale)))
            }
        }
        return pins
    }
}

/// A map label: semibold text with a halo in the surface colour, as MapKit draws titles.
struct MapLabel: View {
    let text: Text
    let palette: MapPalette
    var bold = false
    var scale: Double = 1
    var body: some View {
        let styled = text.font(.system(size: 12 * scale, weight: bold ? .bold : .semibold))
        let offsets: [CGSize] = [CGSize(width: -1, height: 0), CGSize(width: 1, height: 0), CGSize(width: 0, height: -1), CGSize(width: 0, height: 1),
                                 CGSize(width: -0.7, height: -0.7), CGSize(width: 0.7, height: -0.7), CGSize(width: -0.7, height: 0.7),
                                 CGSize(width: 0.7, height: 0.7)]
        return ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                styled.foregroundStyle(palette.halo).offset(offsets[i])
            }
            styled.foregroundStyle(palette.label)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
}

/// Apple's balloon marker: a teardrop with a top-to-bottom gradient of the tint and a white glyph.
struct BalloonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let c = CGPoint(x: rect.midX, y: rect.minY + r)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let d = tip.y - c.y
        let alpha = acos(r / d)
        let right = CGPoint(x: c.x + r * sin(alpha), y: c.y + r * cos(alpha))
        let left = CGPoint(x: c.x - r * sin(alpha), y: c.y + r * cos(alpha))
        var p = Path()
        p.move(to: CGPoint(x: tip.x + 1.2, y: tip.y - 1.6))
        p.addLine(to: right)
        // Around the top, from the right tangent point to the left one.
        p.addArc(center: c, radius: r, startAngle: .radians(Double.pi / 2 - alpha), endAngle: .radians(Double.pi / 2 + alpha), clockwise: true)
        p.addLine(to: CGPoint(x: tip.x - 1.2, y: tip.y - 1.6))
        p.addQuadCurve(to: CGPoint(x: tip.x + 1.2, y: tip.y - 1.6), control: tip)
        p.closeSubpath()
        return p
    }
}

/// The small pin glyph of a default marker.
struct MarkerPinGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width * 0.32
        let c = CGPoint(x: rect.midX, y: rect.minY + r)
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        p.addRoundedRect(in: CGRect(x: rect.midX - rect.width * 0.07, y: c.y, width: rect.width * 0.14, height: rect.maxY - c.y),
                         cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07))
        return p
    }
}

struct MarkerBalloon: View {
    let tint: Color
    let style: AnyShapeStyle?
    let glyph: MarkerGlyph
    var size: Double = 1

    var body: some View {
        let w = 30 * size, h = 39 * size
        let fill: AnyShapeStyle = style ?? AnyShapeStyle(LinearGradient(
            colors: [tint.mix(with: .white, by: 0.18), tint, tint.mix(with: .black, by: 0.12)],
            startPoint: .top, endPoint: .bottom))
        return ZStack(alignment: .top) {
            BalloonShape().fill(fill)
                .shadow(color: .black.opacity(0.25), radius: 1.5 * size, x: 0, y: 1 * size)
            BalloonShape().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            glyphView
                .foregroundStyle(.white)
                .frame(width: w, height: w)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .pin:
            MarkerPinGlyph().fill(Color.white).frame(width: 10 * size, height: 15 * size)
        case .system(let name):
            Image(systemName: name).font(.system(size: 14 * size, weight: .semibold))
        case .image(let name):
            Image(name).renderingMode(.template).resizable().scaledToFit().frame(width: 16 * size, height: 16 * size)
        case .monogram(let text):
            text.font(.system(size: 13 * size, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 24 * size)
        case .label(let view):
            view
        }
    }
}

/// The pre-iOS 17 `MapPin`: a round head on a needle.
struct LegacyPin: View {
    let tint: Color
    let scale: Double
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.35), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 14 * scale, height: 14 * scale)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Rectangle().fill(Color(white: 0.55)).frame(width: 2 * scale, height: 18 * scale)
        }
    }
}

/// The blue user-location dot with its white ring and accuracy halo.
struct UserLocationDot: View {
    var body: some View {
        let blue = Color(red: 0, green: 0.478, blue: 1)
        ZStack {
            Circle().fill(blue.opacity(0.12)).frame(width: 64, height: 64)
            Circle().fill(Color.white).frame(width: 23, height: 23)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle().fill(blue).frame(width: 16, height: 16)
        }
        .frame(width: 64, height: 64)
    }
}

// MARK: - Attribution

/// The "Maps" logo (without the Apple logo glyph) and "Legal" link MapKit draws in the bottom-leading corner.
struct MapAttribution: View {
    let palette: MapPalette
    let glass: Bool
    let scale: Double
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
            Text(verbatim: "Maps").font(.system(size: 12 * scale, weight: .semibold))
            Text(verbatim: "Legal").font(.system(size: 9 * scale, weight: .regular)).underline()
        }
        .foregroundStyle(palette.attribution)
    }
}
