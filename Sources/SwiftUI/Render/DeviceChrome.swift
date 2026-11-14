// The parts of the screen iOS draws itself: status bar, home indicator, and (on request) the
// notch or Dynamic Island. All vector drawing, so it is crisp at any `--scale`.

@MainActor
enum DeviceChrome {
    static func draw(_ p: Painter, device: DeviceProfile, size: CGSize, statusBarScheme scheme: ColorScheme,
                     homeIndicatorScheme: ColorScheme, showsHousing: Bool = false) {
        let color = _Paint.color(scheme == .dark ? .white : .black)
        if device.safeArea.bottom > 0 {
            // iPhone: 139x5, 8pt above the bottom edge. iPad: longer; 219pt is an estimate.
            let width: CGFloat = device.idiom == .pad ? 219 : 139
            let bar = CGRect(x: (size.width - width) / 2, y: size.height - 8 - 5, width: width, height: 5)
            p.fill(Path(roundedRect: bar, cornerRadius: 2.5, style: .circular),
                   with: .color(homeIndicatorScheme == .dark ? .white : .black), in: bar)
        }
        if device.safeArea.top > 0, device.showsStatusBar {
            switch (device.idiom, device.housing) {
            case (.pad, _): drawPadStatusBar(p, size: size, scheme: scheme, color: color)
            case (_, .homeButton): drawHomeButtonStatusBar(p, device: device, size: size, scheme: scheme, color: color)
            case (_, .notch(let notch)): drawPhoneStatusBar(p, device: device, size: size, scheme: scheme, color: color, notchWidth: notch.width)
            default: drawPhoneStatusBar(p, device: device, size: size, scheme: scheme, color: color, notchWidth: nil)
            }
        }
        if showsHousing { drawHousing(p, device: device, size: size) }
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
                                 anchor: HorizontalAlignment, canvas: CGSize, scheme: ColorScheme) {
        let text = Text(string).font(.system(size: fontSize, weight: weight)).makeNode(statusEnv(scheme))
        let s = text.sizeThatFits(.unspecified)
        let originX = anchor == .leading ? x : anchor == .trailing ? x - s.width : x - s.width / 2
        let ctx = PlaceContext(origin: .zero, container: CGRect(origin: .zero, size: canvas), safeRect: CGRect(origin: .zero, size: canvas), scale: p.scale)
        text.place(at: CGPoint(x: originX, y: centerY - s.height / 2), size: s, ctx)
        text.draw(p)
    }

    /// Notch and Dynamic Island phones: time in the left ear, indicators in the right one.
    private static func drawPhoneStatusBar(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme, color: _Paint, notchWidth: CGFloat?) {
        let island = notchWidth == nil
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
        painter.clip(Path(roundedRect: rect, cornerRadius: device.cornerRadius * scale, style: .continuous))
    }
}
