// The parts of the screen iOS draws itself: status bar, home indicator, and (on request) the
// notch or Dynamic Island. All vector drawing, so it is crisp at any `--scale`.

@MainActor
enum DeviceChrome {
    static func draw(_ p: Painter, device: DeviceProfile, size: CGSize, statusBarScheme scheme: ColorScheme,
                     homeIndicatorScheme: ColorScheme, osVersion: Int = RenderedPlatform.defaultVersion,
                     showsHousing: Bool = false) {
        let color = _Paint.color(scheme == .dark ? .white : .black)
        // Apple TV has an overscan margin but no home indicator or status bar.
        if device.safeArea.bottom > 0, device.idiom != .tv, device.idiom != .watch, showsHomeIndicator(device: device, osVersion: osVersion) {
            // iPhone: 139x5, 8pt above the bottom edge. iPad: longer; 219pt is an estimate.
            let width: CGFloat = device.idiom == .pad ? 219 : 139
            let bar = CGRect(x: (size.width - width) / 2, y: size.height - 8 - 5, width: width, height: 5)
            p.fill(Path(roundedRect: bar, cornerRadius: 2.5, style: .circular),
                   with: .color(homeIndicatorScheme == .dark ? .white : .black), in: bar)
        }
        if let ring = device.ringStatusBar {
            if device.showsStatusBar { drawRingStatusBar(p, ring, device: device, size: size, scheme: scheme, color: color) }
        } else if device.safeArea.top > 0, device.showsStatusBar {
            switch (device.idiom, device.housing) {
            case (.pad, _): drawPadStatusBar(p, size: size, scheme: scheme, color: color)
            case (.watch, _): drawWatchTime(p, device: device, size: size, scheme: scheme)
            case (_, .homeButton): drawHomeButtonStatusBar(p, device: device, size: size, scheme: scheme, color: color)
            case (_, .notch(let notch)): drawPhoneStatusBar(p, device: device, size: size, scheme: scheme, color: color, notchWidth: notch.width)
            default: drawPhoneStatusBar(p, device: device, size: size, scheme: scheme, color: color, notchWidth: nil)
            }
        }
        if showsHousing { drawHousing(p, device: device, size: size) }
    }

    /// The iOS 27.0 simulator draws no home indicator on iPhone screenshots (Apple's own apps included);
    /// iOS 26.5 and earlier draw it.
    static func showsHomeIndicator(device: DeviceProfile, osVersion: Int) -> Bool {
        !(device.idiom == .phone && osVersion >= 27)
    }

    // MARK: Status bars

    private static func statusEnv(_ scheme: ColorScheme) -> EnvironmentValues {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        env.foregroundStyle = AnyShapeStyle(scheme == .dark ? Color.white : Color.black)
        return env
    }

    /// Draws `string` so its vertical centre is `centerY` and its horizontal anchor (leading, center or trailing) is `x`.
    private static func drawText(_ p: Painter, _ string: String, size fontSize: CGFloat, weight: Font.Weight, x: CGFloat, centerY: CGFloat,
                                 anchor: HorizontalAlignment, canvas: CGSize, scheme: ColorScheme, design: Font.Design = .default) {
        let text = Text(string).font(.system(size: fontSize, weight: weight, design: design)).makeNode(statusEnv(scheme))
        let s = text.sizeThatFits(.unspecified)
        let originX = anchor == .leading ? x : anchor == .trailing ? x - s.width : x - s.width / 2
        let ctx = PlaceContext(origin: .zero, container: CGRect(origin: .zero, size: canvas), safeRect: CGRect(origin: .zero, size: canvas), scale: p.scale)
        text.place(at: CGPoint(x: originX, y: centerY - s.height / 2), size: s, ctx)
        text.draw(p)
    }

    /// Apple Watch: the time in the top trailing corner, clear of the rounded display corner, as watchOS
    /// draws it over an app (10:09, the watch simulator's time).
    private static func drawWatchTime(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme) {
        let m = WatchClock.metrics(screenWidth: size.width)
        drawText(p, "10:09", size: m.fontSize, weight: .semibold, x: size.width - m.trailing, centerY: m.centerY,
                 anchor: .trailing, canvas: size, scheme: scheme)
    }

    /// The watch's clock. measured: watchOS 26.5 simulator, the digits' ink: 12pt tall centred on y 26, ending
    /// 16pt from the right edge on the 46mm screen; 11pt on y 22.5, 14pt from the edge on the 42mm one; 12pt
    /// on y 27.5, 16.5pt from the edge on the Ultra 2. `trailing` is the text frame's distance from the edge.
    enum WatchClock {
        static func metrics(screenWidth width: CGFloat) -> (fontSize: CGFloat, trailing: CGFloat, centerY: CGFloat) {
            switch width {
            case ..<200: return (15.5, 13, 22)      // 42mm
            case ..<207: return (17, 15.5, 27)      // Ultra 2
            default: return (17, 15, 25.5)          // 46mm
            }
        }
    }

    /// Notch and Dynamic Island phones: time in the left ear, indicators in the right one.
    /// Dynamic Island status bar. measured: iOS 27.0 simulator, iPhone 16 (393pt wide): the
    /// time in 18pt semibold centred at x 70.17 (0.1785 of the width), its digits centred on
    /// y 29 (top inset - 30); signal bars from x 278.33 (width - 114.67), 3.33pt wide, 5.67pt
    /// apart, 6.33/8.67/11/13.67pt tall on a common bottom at y 36.33; Wi-Fi 19 x 14.33pt from
    /// x 307 with 2.67pt arcs; battery 27 x 13.67pt from x 334.33 plus a 1.5pt cap.
    enum IslandStatusBar {
        static let timeSize: CGFloat = 18
        static let timeCenterX: CGFloat = 0.1802   // frame centre; the ink lands at 70.17
        static let centerFromTop: CGFloat = 30
        static let signalFromRight: CGFloat = 114.67
        static let signalBar = CGSize(width: 3.33, height: 13.67)
        static let signalPitch: CGFloat = 5.67
        static let signalHeights: [CGFloat] = [6.33, 8.67, 11, 13.67]
        static let wifiOffset: CGFloat = 28.67
        static let wifiSize = CGSize(width: 19, height: 14.33)
        static let wifiLine: CGFloat = 2.67
        static let batteryOffset: CGFloat = 27.33
        static let battery = CGSize(width: 27, height: 13.67)
    }

    private static func drawIslandStatusBar(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme, color: _Paint) {
        let m = IslandStatusBar.self
        let centerY = device.safeArea.top - m.centerFromTop
        drawText(p, "9:41", size: m.timeSize, weight: .semibold, x: size.width * m.timeCenterX, centerY: centerY + 0.33, anchor: .center, canvas: size, scheme: scheme)
        let bottom = centerY + 7.33
        var x = size.width - m.signalFromRight
        for (i, h) in m.signalHeights.enumerated() {
            let bar = CGRect(x: x + CGFloat(i) * m.signalPitch, y: bottom - h, width: m.signalBar.width, height: h)
            p.fill(Path(roundedRect: bar, cornerRadius: 1.1, style: .circular), with: color, in: bar)
        }
        x += m.wifiOffset
        // Three sectors of one circle centred at the bottom: two arcs and the dot.
        let apex = CGPoint(x: x + m.wifiSize.width / 2, y: bottom)
        let outer = m.wifiSize.height
        let half = asin(min(1, (m.wifiSize.width / 2) / outer)) * 180 / .pi
        let start = Angle.degrees(-90 - half), end = Angle.degrees(-90 + half)
        for (i, r) in [outer, outer - 2 * m.wifiLine + 0.33, outer - 4 * m.wifiLine + 0.66].enumerated() {
            if i == 2 {
                var dot = Path()
                dot.move(to: apex)
                dot.addArc(center: apex, radius: r, startAngle: start, endAngle: end, clockwise: false)
                dot.closeSubpath()
                p.fill(dot, with: color, in: .zero)
            } else {
                var arc = Path()
                arc.addArc(center: apex, radius: r - m.wifiLine / 2, startAngle: start, endAngle: end, clockwise: false)
                p.stroke(arc, with: color, style: StrokeStyle(lineWidth: m.wifiLine, lineCap: .butt), in: .zero)
            }
        }
        x += m.batteryOffset
        let body = CGRect(x: x, y: centerY - 7, width: m.battery.width, height: m.battery.height)
        p.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4.3, style: .continuous),
                 with: _Paint(.opacity(color.kind, 0.4)), style: StrokeStyle(lineWidth: 1), in: body)
        let fill = body.insetBy(dx: 2, dy: 2)
        p.fill(Path(roundedRect: fill, cornerRadius: 2.6, style: .continuous), with: color, in: fill)
        let cap = CGRect(x: body.maxX + 0.5, y: body.midY - 2.2, width: 1.5, height: 4.4)
        p.fill(Path(roundedRect: cap, cornerRadius: 0.75, style: .circular), with: _Paint(.opacity(color.kind, 0.4)), in: cap)
    }

    /// iPhone Duo. measured: iOS 27.2 simulator, both displays: the ring is 41pt across (3.33pt line) with a
    /// 120 degree gap at the bottom, centred 47.83pt from the trailing edge in the column (47.5 in the row);
    /// the column's ring top is 23pt below the top of the time's digits. The Wi-Fi glyph is 18 x 13.33pt,
    /// its top 6.83pt above the ring's centre, 3pt arcs; the cellular dots are 4pt, on the ring's centre line
    /// at 10.5 and 31.5 degrees either side of straight down. The time is in rounded digits 12 x 32pt (16pt
    /// SF Pro Rounded bold matches), centred 1.17pt left of the ring in the column; in the row centred 52.5pt
    /// left of the ring (its ink ends 16pt before the ring), level with the ring's centre, 48.17pt from the top.
    /// The offsets below are the text frame's, which with SF sits 0.83pt left of the ink's centre.
    enum RingMetrics {
        static let timeSize: CGFloat = 16
        static let outerRadius: CGFloat = 20.5
        static let line: CGFloat = 3.33
        static let gapHalfAngle: Double = 60
        static let columnFromRight: CGFloat = 47.83
        static let rowFromRight: CGFloat = 47.5
        static let rowCenterY: CGFloat = 48.17
        static let columnRingBelowTime: CGFloat = 23
        static let columnTimeOffsetX: CGFloat = -0.33
        static let rowTimeOffsetX: CGFloat = -51.67
        static let digitHeight: CGFloat = 12
        static let wifiSize = CGSize(width: 18, height: 13.33)
        static let wifiTopAboveCenter: CGFloat = 6.83
        static let wifiLine: CGFloat = 3
        static let dotDiameter: CGFloat = 4
        static let dotAngles: [Double] = [58.5, 79.5, 100.5, 121.5]   // from +x, clockwise (y down)
    }

    private static func drawRingStatusBar(_ p: Painter, _ ring: DeviceProfile.RingStatusBar, device: DeviceProfile, size: CGSize,
                                          scheme: ColorScheme, color: _Paint) {
        let m = RingMetrics.self
        let center: CGPoint
        if device.orientation.isLandscape {
            center = CGPoint(x: size.width - m.rowFromRight, y: m.rowCenterY)
            drawDigits(p, x: center.x + m.rowTimeOffsetX, inkMidY: center.y - 0.17, canvas: size, scheme: scheme)
        } else {
            let ringTop = ring.columnTop + m.columnRingBelowTime
            center = CGPoint(x: size.width - m.columnFromRight, y: ringTop + m.outerRadius)
            drawDigits(p, x: center.x + m.columnTimeOffsetX, inkMidY: ring.columnTop + m.digitHeight / 2, canvas: size, scheme: scheme)
        }
        // The ring: open at the bottom, round ends.
        var arc = Path()
        let r = m.outerRadius - m.line / 2
        arc.addArc(center: center, radius: r, startAngle: .degrees(90 + m.gapHalfAngle), endAngle: .degrees(90 - m.gapHalfAngle), clockwise: false)
        p.stroke(arc, with: color, style: StrokeStyle(lineWidth: m.line, lineCap: .round), in: .zero)
        // Cellular: four dots on the ring's centre line in the gap.
        for angle in m.dotAngles {
            let a = angle * .pi / 180
            let c = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
            let dot = CGRect(x: c.x - m.dotDiameter / 2, y: c.y - m.dotDiameter / 2, width: m.dotDiameter, height: m.dotDiameter)
            p.fill(Path(ellipseIn: dot), with: color, in: dot)
        }
        // Wi-Fi: two arcs and a wedge of one circle centred at the glyph's bottom.
        let apex = CGPoint(x: center.x, y: center.y - m.wifiTopAboveCenter + m.wifiSize.height)
        let outer = m.wifiSize.height
        let half = asin(min(1, (m.wifiSize.width / 2) / outer)) * 180 / .pi
        let start = Angle.degrees(-90 - half), end = Angle.degrees(-90 + half)
        for (i, radius) in [outer, outer - 4.67, outer - 9.33].enumerated() {
            if i == 2 {
                var wedge = Path()
                wedge.move(to: apex)
                wedge.addArc(center: apex, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                wedge.closeSubpath()
                p.fill(wedge, with: color, in: .zero)
            } else {
                var a = Path()
                a.addArc(center: apex, radius: radius - m.wifiLine / 2, startAngle: start, endAngle: end, clockwise: false)
                p.stroke(a, with: color, style: StrokeStyle(lineWidth: m.wifiLine, lineCap: .round), in: .zero)
            }
        }
    }

    /// "9:41" in the ring status bar's font, centred on x; with SF its digits' ink is centred on (x, inkMidY).
    private static func drawDigits(_ p: Painter, x: CGFloat, inkMidY: CGFloat, canvas: CGSize, scheme: ColorScheme) {
        drawText(p, "9:41", size: RingMetrics.timeSize, weight: .bold, x: x, centerY: inkMidY,
                 anchor: .center, canvas: canvas, scheme: scheme, design: .rounded)
    }

    private static func drawPhoneStatusBar(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme, color: _Paint, notchWidth: CGFloat?) {
        let island = notchWidth == nil
        if island, device.orientation == .portrait {
            drawIslandStatusBar(p, device: device, size: size, scheme: scheme, color: color)
            return
        }
        let top = device.safeArea.top
        let centerY: CGFloat = island ? top - 27 : top - 23
        let fontSize: CGFloat = island ? 17 : 15
        // The ears are the screen minus the cutout; the content is centred in each.
        let leftCenter: CGFloat = notchWidth.map { (size.width - $0) / 4 } ?? size.width * 0.19
        drawText(p, "9:41", size: fontSize, weight: .semibold, x: leftCenter, centerY: centerY, anchor: .center, canvas: size, scheme: scheme)

        // Right cluster: signal bars, Wi-Fi, battery.
        let right: CGFloat = notchWidth.map { size.width - (size.width - $0) / 4 } ?? size.width * 0.81
        var x = right - 38
        drawSignal(p, x: x, centerY: centerY, color: color)
        x += 23
        drawWifi(p, x: x, centerY: centerY, color: color)
        x += 23
        drawBattery(p, x: x, centerY: centerY, color: color)
    }

    /// iPhone SE: 20pt bar, signal dots and Wi-Fi at the left, time centred, battery with percentage at the right.
    private static func drawHomeButtonStatusBar(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme, color: _Paint) {
        let centerY = device.safeArea.top / 2
        drawText(p, "9:41 AM", size: 12, weight: .semibold, x: size.width / 2, centerY: centerY, anchor: .center, canvas: size, scheme: scheme)
        for i in 0..<5 {
            let dot = CGRect(x: 7 + CGFloat(i) * 6.2, y: centerY - 2.3, width: 4.6, height: 4.6)
            p.fill(Path(ellipseIn: dot), with: i < 4 ? color : _Paint(.opacity(color.kind, 0.4)), in: dot)
        }
        p.save()
        p.translate(45, centerY - 0.5)
        p.scale(0.78, 0.78)
        drawWifi(p, x: 0, centerY: 0, color: color)
        p.restore()
        // Battery at 0.8 scale, its right edge 6pt from the screen edge, percentage to its left.
        let batteryX = size.width - 6 - 0.8 * 27
        p.save()
        p.translate(batteryX, centerY)
        p.scale(0.8, 0.8)
        drawBattery(p, x: 0, centerY: 0, color: color)
        p.restore()
        drawText(p, "100%", size: 12, weight: .semibold, x: batteryX - 4, centerY: centerY, anchor: .trailing, canvas: size, scheme: scheme)
    }

    /// iPad: 24pt bar, time and date at the left, Wi-Fi, percentage and battery at the right.
    private static func drawPadStatusBar(_ p: Painter, size: CGSize, scheme: ColorScheme, color: _Paint) {
        let centerY: CGFloat = 13   // the content sits a little below the middle of the 24pt bar
        drawText(p, "9:41 AM", size: 15, weight: .semibold, x: 26, centerY: centerY, anchor: .leading, canvas: size, scheme: scheme)
        drawText(p, "Tue Jan 9", size: 15, weight: .semibold, x: 26 + 70, centerY: centerY, anchor: .leading, canvas: size, scheme: scheme)
        let batteryX = size.width - 26 - 27
        drawBattery(p, x: batteryX, centerY: centerY, color: color)
        drawText(p, "100%", size: 15, weight: .semibold, x: batteryX - 5, centerY: centerY, anchor: .trailing, canvas: size, scheme: scheme)
        drawWifi(p, x: batteryX - 5 - 44 - 26, centerY: centerY, color: color)
    }

    // MARK: Indicators

    private static func drawSignal(_ p: Painter, x: CGFloat, centerY: CGFloat, color: _Paint) {
        for i in 0..<4 {
            let h = 4.5 + CGFloat(i) * 2.5
            let bar = CGRect(x: x + CGFloat(i) * 4.5, y: centerY + 6 - h, width: 3, height: h)
            p.fill(Path(roundedRect: bar, cornerRadius: 1, style: .circular), with: color, in: bar)
        }
    }

    private static func drawWifi(_ p: Painter, x: CGFloat, centerY: CGFloat, color: _Paint) {
        let wifiCenter = CGPoint(x: x + 8, y: centerY + 5.5)
        for (i, r) in [CGFloat(11.5), 7.5, 3.5].enumerated() {
            var arc = Path()
            arc.addArc(center: wifiCenter, radius: r, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            if i == 2 {
                arc.addLine(to: wifiCenter); arc.closeSubpath()
                p.fill(arc, with: color, in: .zero)
            } else {
                p.stroke(arc, with: color, style: StrokeStyle(lineWidth: 2.2, lineCap: .butt), in: .zero)
            }
        }
    }

    private static func drawBattery(_ p: Painter, x: CGFloat, centerY: CGFloat, color: _Paint) {
        let body = CGRect(x: x, y: centerY - 6.5, width: 25, height: 13)
        p.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4, style: .continuous),
                 with: _Paint(.opacity(color.kind, 0.4)), style: StrokeStyle(lineWidth: 1), in: body)
        let fill = body.insetBy(dx: 2, dy: 2)
        p.fill(Path(roundedRect: fill, cornerRadius: 2.5, style: .continuous), with: color, in: fill)
        let cap = CGRect(x: body.maxX + 1, y: centerY - 2, width: 1.5, height: 4)
        p.fill(Path(roundedRect: cap, cornerRadius: 0.75, style: .circular), with: _Paint(.opacity(color.kind, 0.4)), in: cap)
    }

    // MARK: Sensor housing

    /// The black pill or notch. In landscape it sits on the left (landscapeLeft) or right edge, rotated.
    private static func drawHousing(_ p: Painter, device: DeviceProfile, size: CGSize) {
        // (extent along the edge, depth into the screen, distance of the near side from the edge, corner radius)
        if case .punchHole(let d, let offset) = device.housing {
            // Placed on the portrait screen, then turned with the device.
            let pw = device.portraitSize.width, ph = device.portraitSize.height
            let c = CGPoint(x: pw - offset.x, y: offset.y)
            let center: CGPoint
            switch device.orientation {
            case .portrait: center = c
            case .landscapeLeft: center = CGPoint(x: c.y, y: pw - c.x)
            case .landscapeRight: center = CGPoint(x: ph - c.y, y: c.x)
            }
            let rect = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            p.fill(Path(ellipseIn: rect), with: .color(.black), in: rect)
            return
        }
        let along: CGFloat, depth: CGFloat, inset: CGFloat, radius: CGFloat
        switch device.housing {
        case .dynamicIsland(let s, let top): (along, depth, inset, radius) = (s.width, s.height, top, s.height / 2)
        case .notch(let s): (along, depth, inset, radius) = (s.width, s.height, -24, 20)   // extended past the edge: only the inner corners show
        default: return
        }
        let rect: CGRect
        switch device.orientation {
        case .portrait:
            rect = CGRect(x: (size.width - along) / 2, y: inset, width: along, height: depth + (inset < 0 ? -inset : 0))
        case .landscapeLeft:
            rect = CGRect(x: inset, y: (size.height - along) / 2, width: depth + (inset < 0 ? -inset : 0), height: along)
        case .landscapeRight:
            let w = depth + (inset < 0 ? -inset : 0)
            rect = CGRect(x: size.width - inset - w, y: (size.height - along) / 2, width: w, height: along)
        }
        p.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(.black), in: rect)
    }

    // MARK: Display shape

    /// Clips the canvas (pixel coordinates) to the device's rounded display; corners stay transparent.
    static func clipToDisplay(canvas: OpaquePointer, device: DeviceProfile, size: CGSize, scale: CGFloat) {
        guard device.cornerRadius > 0 else { return }
        let painter = Painter(canvas: canvas, scale: scale)
        let rect = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        if device.leadingCornerRadius != nil {
            let r = device.displayCornerRadii
            painter.clip(Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                topLeading: r.topLeading * scale, bottomLeading: r.bottomLeading * scale,
                bottomTrailing: r.bottomTrailing * scale, topTrailing: r.topTrailing * scale), style: .continuous))
        } else {
            painter.clip(Path(roundedRect: rect, cornerRadius: device.cornerRadius * scale, style: .continuous))
        }
    }
}
