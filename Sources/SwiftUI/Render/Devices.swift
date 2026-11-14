// The device table: single source of truth for screen geometry. `swiftui-screenshot devices`
// lists it (through the runner's --list-devices), `--device` resolves names through `lookup`.
//
// Values are in points. Where a number is an estimate rather than a measured value, the comment
// says so; the geometry that decides layout (point size, scale, safe-area insets) is what matters most.

package enum DeviceIdiom: Sendable { case phone, pad, tv, watch }

package enum DeviceOrientation: Sendable {
    case portrait, landscapeLeft, landscapeRight
    var isLandscape: Bool { self != .portrait }
}

/// What the front sensors look like on screen.
enum SensorHousing {
    /// No cutout in the display (iPads: the camera sits in the bezel).
    case none
    /// A physical home button below the display, a bezel above it (iPhone SE).
    case homeButton
    /// The black notch: its size from the top edge.
    case notch(size: CGSize)
    /// The pill: its size and the distance of its top edge from the top of the screen.
    case dynamicIsland(size: CGSize, top: CGFloat)

    var label: String {
        switch self {
        case .none: return "none"
        case .homeButton: return "home button"
        case .notch: return "notch"
        case .dynamicIsland: return "Dynamic Island"
        }
    }
}

package struct DeviceProfile {
    var id: String
    var name: String
    package var idiom: DeviceIdiom
    /// Portrait size in points.
    var portraitSize: CGSize
    package var scale: CGFloat
    var portraitSafeArea: EdgeInsets
    var landscapeSafeArea: EdgeInsets
    var cornerRadius: CGFloat
    var housing: SensorHousing
    var aliases: [String] = []
    package var orientation: DeviceOrientation = .portrait

    /// Size in the current orientation.
    package var size: CGSize {
        orientation.isLandscape ? CGSize(width: portraitSize.height, height: portraitSize.width) : portraitSize
    }
    /// Safe-area insets in the current orientation.
    package var safeArea: EdgeInsets { orientation.isLandscape ? landscapeSafeArea : portraitSafeArea }

    /// iPhones in landscape hide the status bar; iPads keep it. A watch shows the time in its top corner.
    var showsStatusBar: Bool { idiom == .pad || idiom == .watch || (idiom == .phone && !orientation.isLandscape) }

    /// Width size class of a full-screen app. iPads are regular. iPhones are compact in portrait, and
    /// in landscape regular when the portrait width is 414pt or more (the Plus/Max/Air sizes, and the 11).
    package var horizontalSizeClass: UserInterfaceSizeClass {
        if idiom == .watch { return .compact }
        if idiom != .phone { return .regular }
        return orientation.isLandscape && portraitSize.width >= 414 ? .regular : .compact
    }
    /// iPhones are compact in landscape, watches always; everything else is regular.
    package var verticalSizeClass: UserInterfaceSizeClass {
        idiom == .watch || (idiom == .phone && orientation.isLandscape) ? .compact : .regular
    }

    // MARK: Lookup

    /// "iPhone 16 Pro", "iphone-16-pro" and "iphone16pro" are the same key.
    static func normalize(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static let all: [String: DeviceProfile] = Dictionary(uniqueKeysWithValues: table.map { ($0.id, $0) })

    private static let byAlias: [String: DeviceProfile] = {
        var map: [String: DeviceProfile] = [:]
        for device in table {
            for key in [device.id, device.name] + device.aliases { map[normalize(key)] = device }
        }
        return map
    }()

    static func lookup(_ name: String) -> DeviceProfile? { byAlias[normalize(name)] }

    // MARK: Table

    private static func edges(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// An iPhone with a notch or island: portrait insets (top, 34), landscape (0, top, 21, top).
    /// The landscape side insets equal the portrait top inset on all of these (estimate for the older notch phones).
    private static func phone(_ id: String, _ name: String, _ width: CGFloat, _ height: CGFloat, scale: CGFloat = 3,
                              top: CGFloat, radius: CGFloat, housing: SensorHousing, aliases: [String] = []) -> DeviceProfile {
        DeviceProfile(id: id, name: name, idiom: .phone, portraitSize: CGSize(width: width, height: height), scale: scale,
                      portraitSafeArea: edges(top, 0, 34, 0), landscapeSafeArea: edges(0, top, 21, top),
                      cornerRadius: radius, housing: housing, aliases: aliases)
    }

    private static func pad(_ id: String, _ name: String, _ width: CGFloat, _ height: CGFloat, radius: CGFloat,
                            aliases: [String] = []) -> DeviceProfile {
        // iPads show the status bar (24pt) in both orientations and reserve 20pt for the home indicator.
        DeviceProfile(id: id, name: name, idiom: .pad, portraitSize: CGSize(width: width, height: height), scale: 2,
                      portraitSafeArea: edges(24, 0, 20, 0), landscapeSafeArea: edges(24, 0, 20, 0),
                      cornerRadius: radius, housing: .none, aliases: aliases)
    }

    /// An Apple Watch: watchOS apps are portrait only, and the same insets apply in both orientations.
    /// The top inset is the band the time sits in; the bottom one keeps content off the rounded corners.
    private static func watch(_ id: String, _ name: String, _ width: CGFloat, _ height: CGFloat, top: CGFloat, bottom: CGFloat,
                              radius: CGFloat, aliases: [String]) -> DeviceProfile {
        DeviceProfile(id: id, name: name, idiom: .watch, portraitSize: CGSize(width: width, height: height), scale: 2,
                      portraitSafeArea: edges(top, 0, bottom, 0), landscapeSafeArea: edges(top, 0, bottom, 0),
                      cornerRadius: radius, housing: .none, aliases: aliases)
    }

    // Notch sizes. 209x30 is the iPhone X/11/12 notch, 162x34 the narrower one of the 13 and 14.
    // Both are approximate (+-2pt).
    private static let wideNotch = SensorHousing.notch(size: CGSize(width: 209, height: 30))
    private static let narrowNotch = SensorHousing.notch(size: CGSize(width: 162, height: 34))
    // Island: 125x37 pill. Top offset 11 on the 14 Pro through 16 (top inset 59), 14 on the 16 Pro / 17
    // family (top inset 62); the 17-series and Air offsets are estimates.
    private static let island59 = SensorHousing.dynamicIsland(size: CGSize(width: 125, height: 37), top: 11)
    private static let island62 = SensorHousing.dynamicIsland(size: CGSize(width: 125, height: 37), top: 14)

    static let table: [DeviceProfile] = [
        // Home button. Landscape has no insets (status bar hidden).
        // Apple TV: a 1920x1080pt canvas (4K renders it at 2x). The safe area is the overscan
        // margin tvOS keeps clear: 60pt top and bottom, 80pt at the sides.
        DeviceProfile(id: "apple-tv-4k", name: "Apple TV 4K", idiom: .tv, portraitSize: CGSize(width: 1920, height: 1080), scale: 2,
                      portraitSafeArea: EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80),
                      landscapeSafeArea: EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80), cornerRadius: 0,
                      housing: .none, aliases: ["apple-tv", "appletv", "tv", "apple-tv-4k-3rd-generation"]),
        DeviceProfile(id: "apple-tv-hd", name: "Apple TV HD", idiom: .tv, portraitSize: CGSize(width: 1920, height: 1080), scale: 1,
                      portraitSafeArea: EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80),
                      landscapeSafeArea: EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80), cornerRadius: 0,
                      housing: .none, aliases: ["apple-tv-1080p"]),
        DeviceProfile(id: "iphone-se", name: "iPhone SE (3rd generation)", idiom: .phone, portraitSize: CGSize(width: 375, height: 667),
                      scale: 2, portraitSafeArea: edges(20, 0, 0, 0), landscapeSafeArea: edges(0, 0, 0, 0), cornerRadius: 0,
                      housing: .homeButton, aliases: ["iphone-se-2", "iphone-se-3", "iPhone SE (2nd generation)", "iphone-8"]),

        // Notch phones. Top insets: 11 = 48 (estimate; XR is 44), 11 Pro / 11 Pro Max = 44, 12 mini / 13 mini = 50 (estimate).
        phone("iphone-11", "iPhone 11", 414, 896, scale: 2, top: 48, radius: 41.5, housing: wideNotch, aliases: ["iphone-xr"]),
        phone("iphone-11-pro", "iPhone 11 Pro", 375, 812, top: 44, radius: 39, housing: wideNotch, aliases: ["iphone-xs", "iphone-x"]),
        phone("iphone-11-pro-max", "iPhone 11 Pro Max", 414, 896, top: 44, radius: 39, housing: wideNotch, aliases: ["iphone-xs-max"]),
        phone("iphone-12-mini", "iPhone 12 mini", 375, 812, top: 50, radius: 44, housing: wideNotch),
        phone("iphone-12", "iPhone 12", 390, 844, top: 47, radius: 47.33, housing: wideNotch),
        phone("iphone-12-pro", "iPhone 12 Pro", 390, 844, top: 47, radius: 47.33, housing: wideNotch),
        phone("iphone-12-pro-max", "iPhone 12 Pro Max", 428, 926, top: 47, radius: 53.33, housing: wideNotch),
        phone("iphone-13-mini", "iPhone 13 mini", 375, 812, top: 50, radius: 44, housing: narrowNotch),
        phone("iphone-13", "iPhone 13", 390, 844, top: 47, radius: 47.33, housing: narrowNotch),
        phone("iphone-13-pro", "iPhone 13 Pro", 390, 844, top: 47, radius: 47.33, housing: narrowNotch),
        phone("iphone-13-pro-max", "iPhone 13 Pro Max", 428, 926, top: 47, radius: 53.33, housing: narrowNotch),
        phone("iphone-14", "iPhone 14", 390, 844, top: 47, radius: 47.33, housing: narrowNotch),
        phone("iphone-14-plus", "iPhone 14 Plus", 428, 926, top: 47, radius: 53.33, housing: narrowNotch),
        phone("iphone-16e", "iPhone 16e", 390, 844, top: 47, radius: 47.33, housing: narrowNotch),   // notch size estimated

        // Dynamic Island phones.
        phone("iphone-14-pro", "iPhone 14 Pro", 393, 852, top: 59, radius: 55, housing: island59),
        phone("iphone-14-pro-max", "iPhone 14 Pro Max", 430, 932, top: 59, radius: 55, housing: island59),
        phone("iphone-15", "iPhone 15", 393, 852, top: 59, radius: 55, housing: island59),
        phone("iphone-15-plus", "iPhone 15 Plus", 430, 932, top: 59, radius: 55, housing: island59),
        phone("iphone-15-pro", "iPhone 15 Pro", 393, 852, top: 59, radius: 55, housing: island59),
        phone("iphone-15-pro-max", "iPhone 15 Pro Max", 430, 932, top: 59, radius: 55, housing: island59),
        phone("iphone-16", "iPhone 16", 393, 852, top: 59, radius: 55, housing: island59),
        phone("iphone-16-plus", "iPhone 16 Plus", 430, 932, top: 59, radius: 55, housing: island59),
        phone("iphone-16-pro", "iPhone 16 Pro", 402, 874, top: 62, radius: 62, housing: island62),
        phone("iphone-16-pro-max", "iPhone 16 Pro Max", 440, 956, top: 62, radius: 62, housing: island62),
        phone("iphone-17", "iPhone 17", 402, 874, top: 62, radius: 62, housing: island62),
        phone("iphone-17-pro", "iPhone 17 Pro", 402, 874, top: 62, radius: 62, housing: island62),
        phone("iphone-17-pro-max", "iPhone 17 Pro Max", 440, 956, top: 62, radius: 62, housing: island62),
        // iPhone Air: 420x912 is solid; the 68pt top inset and the 62pt corner radius are estimates.
        phone("iphone-air", "iPhone Air", 420, 912, top: 68, radius: 62, housing: .dynamicIsland(size: CGSize(width: 125, height: 37), top: 20),
              aliases: ["iphone-17-air"]),

        // Apple Watch. Screen sizes are Apple's (416x496, 374x446 and 410x502 pixels at 2x). The safe-area
        // insets and the display corner radii are estimates scaled from the 41/45mm generation.
        watch("apple-watch-series-10-46mm", "Apple Watch Series 10 (46mm)", 208, 248, top: 37, bottom: 10, radius: 52,
              aliases: ["apple-watch", "watch", "apple-watch-46mm", "apple-watch-series-11-46mm"]),
        watch("apple-watch-series-10-42mm", "Apple Watch Series 10 (42mm)", 187, 223, top: 33, bottom: 9, radius: 46,
              aliases: ["apple-watch-42mm", "apple-watch-series-11-42mm"]),
        watch("apple-watch-ultra-2", "Apple Watch Ultra 2 (49mm)", 205, 251, top: 37, bottom: 10, radius: 48,
              aliases: ["apple-watch-ultra", "apple-watch-ultra-49mm"]),

        // iPads. Corner radii are approximations (18pt for the 11/13-inch, 21.5 for the mini).
        pad("ipad", "iPad (11th generation)", 820, 1180, radius: 18, aliases: ["ipad-10", "ipad-a16", "iPad (10th generation)"]),
        pad("ipad-mini", "iPad mini (A17 Pro)", 744, 1133, radius: 21.5),
        pad("ipad-air-11", "iPad Air 11-inch", 820, 1180, radius: 18),
        pad("ipad-air-13", "iPad Air 13-inch", 1024, 1366, radius: 18),
        pad("ipad-pro-11", "iPad Pro 11-inch", 834, 1210, radius: 18),
        pad("ipad-pro-13", "iPad Pro 13-inch", 1032, 1376, radius: 18),
    ]

    /// One line per device, for `--list-devices`.
    static func listing() -> String {
        func n(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }
        var lines: [String] = []
        let idWidth = table.map(\.id.count).max()! + 2, nameWidth = table.map(\.name.count).max()! + 2
        for d in table {
            let a = d.portraitSafeArea, l = d.landscapeSafeArea
            let id = d.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            let nm = d.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let sz = "\(n(d.portraitSize.width))x\(n(d.portraitSize.height)) @\(n(d.scale))x".padding(toLength: 16, withPad: " ", startingAt: 0)
            lines.append("\(id)\(nm)\(sz)\(d.housing.label.padding(toLength: 15, withPad: " ", startingAt: 0))"
                         + "safe \(n(a.top))/\(n(a.leading))/\(n(a.bottom))/\(n(a.trailing)) land \(n(l.top))/\(n(l.leading))/\(n(l.bottom))/\(n(l.trailing))")
        }
        return lines.joined(separator: "\n")
    }
}
