// watchOS chrome measurements per watch screen: buttons, list rows, the navigation title and the
// vertical page indicator. Every value is in points.
//
// measured: watchOS 26.5 simulator (Examples/Watch.swift and Examples/WatchList.swift on the Series 10 46mm,
// Series 10 42mm and Ultra 2 49mm). Earlier watchOS versions are drawn with the same values.

struct WatchMetrics {
    /// Bordered buttons: a capsule this tall and at most this wide (it does not fill a 204pt wide screen).
    var buttonHeight: CGFloat
    var buttonMaxWidth: CGFloat
    /// List rows: each row is its own card, at least this tall, the cards `rowSpacing` apart.
    var rowMinHeight: CGFloat
    var rowSpacing: CGFloat = 5
    /// Row content's leading and trailing inset from the card's edge.
    var rowInset: CGFloat
    /// Row content's vertical padding inside the card (estimate: rows of two lines are 56pt tall with 39.5pt of text).
    var rowPaddingVertical: CGFloat = 6
    var cardCornerRadius: CGFloat = 14
    /// Between sections, and between a section header or footer and its cards (estimates).
    var sectionSpacing: CGFloat = 12
    var headerGap: CGFloat = 4
    /// The card: #222223 on the black screen.
    var cardColor = RGBA(34 / 255, 34 / 255, 35 / 255, 1)
    /// Navigation title: grey, regular, at the top leading edge in the clock's row. The first list row starts at `barBottom`.
    var titleTop: CGFloat
    var titleLeading: CGFloat
    var titleFontSize: CGFloat
    var titleColor = RGBA(0.5, 0.5, 0.5, 1)
    var barBottom: CGFloat
    /// `.verticalPage` dots: 6pt across, 8pt apart, centred `pageDotsCenterFromTrailing` from the right edge, the
    /// stack centred on `pageDotsCenterY`; the other pages' dots at 36% white.
    var pageDotDiameter: CGFloat = 6
    var pageDotPitch: CGFloat = 8
    var pageDotsCenterFromTrailing: CGFloat = 5
    var pageDotsCenterY: CGFloat
    var pageDotInactiveOpacity: Double = 0.36

    /// The metrics of the watch with this screen width (42mm 187pt, Ultra 2 205pt, 46mm 208pt).
    static func forScreen(width: CGFloat) -> WatchMetrics {
        switch width {
        case ..<200:   // Series 10 42mm
            return WatchMetrics(buttonHeight: 48, buttonMaxWidth: 161, rowMinHeight: 51, rowInset: 11,
                                titleTop: 23, titleLeading: 13, titleFontSize: 25, barBottom: 56, pageDotsCenterY: 60.5)
        case ..<207:   // Ultra 2 49mm
            return WatchMetrics(buttonHeight: 54, buttonMaxWidth: 174, rowMinHeight: 57, rowInset: 13.5,
                                titleTop: 28, titleLeading: 15.5, titleFontSize: 26, barBottom: 64, pageDotsCenterY: 85.25)
        default:       // Series 10 46mm
            return WatchMetrics(buttonHeight: 52.5, buttonMaxWidth: 178, rowMinHeight: 56, rowInset: 13,
                                titleTop: 26.5, titleLeading: 15, titleFontSize: 26, barBottom: 62, pageDotsCenterY: 67.5)
        }
    }

    /// The metrics of the watch being rendered.
    @MainActor static var current: WatchMetrics { forScreen(width: _currentConfiguration().device.portraitSize.width) }
}
