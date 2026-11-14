// Every List/Form measurement in one place (points), so they can be calibrated against real
// iOS 18 screenshots.

enum ListMetrics {
    // Rows
    static let minRowHeight: CGFloat = 44
    static let rowInsetTop: CGFloat = 11
    static let rowInsetBottom: CGFloat = 11
    /// Row content leading/trailing inset from the card edge (inset grouped / grouped).
    static let rowInsetHorizontal: CGFloat = 20
    /// Plain lists: layout margin + this.
    static let plainRowExtraInset: CGFloat = 4

    // Cards (inset grouped)
    static let cardCornerRadius: CGFloat = 10

    // Vertical rhythm, inset grouped / grouped
    /// Top of the safe area to the first card when the first section has no header.
    static let firstSectionTop: CGFloat = 16
    /// Top of the safe area to the first header's text when the first section has a header.
    static let firstHeaderTop: CGFloat = 16
    /// Between two cards when the second section has no header.
    static let sectionSpacing: CGFloat = 35
    /// `.listSectionSpacing(.compact)`.
    static let compactSectionSpacing: CGFloat = 20
    /// Previous card bottom to the top of the next header's text.
    static let headerTopSpacing: CGFloat = 22
    /// Header text baseline to the card's top edge.
    static let headerBaselineToCard: CGFloat = 7
    /// Card bottom to the top of the footer text.
    static let footerTopSpacing: CGFloat = 7
    /// Footer text bottom to the next card (no header) / next header text.
    static let afterFooterSpacing: CGFloat = 24
    static let afterFooterHeaderSpacing: CGFloat = 17
    /// Header/footer leading inset from the card edge.
    static let headerInset: CGFloat = 20
    static let bottomPadding: CGFloat = 35

    // Header/footer typography
    static let headerFontSize: CGFloat = 13
    static let footerFontSize: CGFloat = 13
    static let prominentHeaderFontSize: CGFloat = 20

    // Plain style
    static let plainHeaderFontSize: CGFloat = 13
    static let plainHeaderHeight: CGFloat = 28
    static let plainFooterVerticalPadding: CGFloat = 7

    // Separators
    static let separatorThickness: CGFloat = 1.0 / 3

    // Accessories
    static let chevronWidth: CGFloat = 7
    static let chevronHeight: CGFloat = 12
    static let chevronLineWidth: CGFloat = 2
    /// Width reserved for the chevron at the trailing inset, plus the gap before it.
    static let chevronBox: CGFloat = 12
    static let chevronGap: CGFloat = 8
    static let badgeGap: CGFloat = 8
    static let badgeFontSize: CGFloat = 17
    /// Safe area pushed down by more than this (below the screen's top inset) means a large title is above.
    static let largeTitleDepthThreshold: CGFloat = 80
}

/// The measurements of a List that differ between design languages. `.flat` is exactly the
/// `ListMetrics` constants (iOS 18); the glass values are estimates to calibrate later.
struct ListDesignMetrics {
    var minRowHeight: CGFloat
    var rowInsetVertical: CGFloat
    var rowInsetHorizontal: CGFloat
    var cardCornerRadius: CGFloat
    /// Distance between the trailing end of a separator and the card's trailing edge.
    var separatorTrailingInset: CGFloat
    var headerFontSize: CGFloat
    var headerWeight: Font.Weight?
    var headerUppercased: Bool
    var headerBaselineToCard: CGFloat
    /// Header/footer leading inset from the card edge.
    var headerInset: CGFloat = ListMetrics.headerInset
    var separatorThickness: CGFloat = ListMetrics.separatorThickness
    /// Separator colour (light, dark); nil uses `SystemColor.separator`.
    var separatorColors: (light: RGBA, dark: RGBA)? = nil
    /// Glass: sections are spaced as boxes (see `GlassSectionMetrics`); nil keeps the iOS 18 rhythm.
    var sections: GlassSectionMetrics? = nil
    /// Vertical row inset of a row that holds a switch (the switch and a label icon may overhang it).
    var switchRowInsetVertical: CGFloat? = nil
    /// The disclosure chevron: path size and the gap between its right end and the row's trailing inset.
    var chevronSize = CGSize(width: ListMetrics.chevronWidth, height: ListMetrics.chevronHeight)
    var chevronTrailingPad: CGFloat = 0
    /// Width kept free for the chevron at the trailing inset, the gap before it included.
    var chevronReserve: CGFloat = ListMetrics.chevronBox + ListMetrics.chevronGap
    /// Plain lists: row inset beyond the layout margin.
    var plainExtraInset: CGFloat = ListMetrics.plainRowExtraInset
    /// Glass plain lists: headers are boxes (text with this padding above and below), sections after the
    /// first start `gap` below the previous row; nil keeps the iOS 18 header bands.
    var plainSections: (headerPadding: CGFloat, gap: CGFloat)? = nil
    /// Plain header font size.
    var plainHeaderFontSize: CGFloat = ListMetrics.plainHeaderFontSize
}

/// Inset grouped sections on iOS 26 and 27, measured as boxes: a section is preceded by its header box
/// (the header text with `headerPadding` above and below) or by `sectionTop`, and followed by its footer
/// box or by `sectionBottom`. Two sections without header and footer are therefore 35pt apart.
struct GlassSectionMetrics {
    /// Safe area top to the first card when the first section has no header and no navigation bar is above.
    var firstSectionTop: CGFloat
    /// The same under a large title: the card starts at the bar's bottom edge (an inline bar keeps `firstSectionTop`).
    var firstSectionTopUnderLargeTitle: CGFloat
    var sectionTop: CGFloat
    var sectionBottom: CGFloat
    var headerPaddingTop: CGFloat
    var headerPaddingBottom: CGFloat
    var footerPaddingTop: CGFloat
    var footerPaddingBottom: CGFloat
}

extension ListMetrics {
    static func forDesign(_ design: DesignLanguage) -> ListDesignMetrics {
        guard design.isGlass else {
            return ListDesignMetrics(minRowHeight: minRowHeight, rowInsetVertical: rowInsetTop, rowInsetHorizontal: rowInsetHorizontal,
                                     cardCornerRadius: cardCornerRadius, separatorTrailingInset: 0, headerFontSize: headerFontSize,
                                     headerWeight: nil, headerUppercased: true, headerBaselineToCard: headerBaselineToCard)
        }
        // iOS 26 and 27 share these values (iOS 27 did not change lists).
        // measured: iOS 27.0 simulator (26.5 identical): Lists, 01_Settings, SplitView, Presentations.
        var m = ListDesignMetrics(minRowHeight: 52,                // measured: iOS 27.0 simulator (text rows 52, 29pt icon rows 59)
                                  rowInsetVertical: 15,
                                  rowInsetHorizontal: 16,          // measured: iOS 27.0 simulator
                                  cardCornerRadius: 26,
                                  separatorTrailingInset: 16,      // measured: iOS 27.0 simulator
                                  headerFontSize: 17,              // measured: iOS 27.0 simulator (17pt semibold)
                                  headerWeight: .semibold,
                                  headerUppercased: false,
                                  headerBaselineToCard: 12)        // unused: glass headers are boxes
        m.headerInset = 16                                         // measured: iOS 27.0 simulator
        m.separatorThickness = 1                                   // measured: iOS 27.0 simulator (3px at 3x)
        m.separatorColors = (RGBA(0, 0, 0, 0.09), RGBA(84 / 255, 84 / 255, 88 / 255, 0.5)) // measured: #E8E8E8 on white, #38383B on #1C1C1E
        m.sections = GlassSectionMetrics(firstSectionTop: 35,      // measured: iOS 27.0 simulator
                                         firstSectionTopUnderLargeTitle: 0, // measured: card at the large title's bottom (165pt); 35 under an inline bar (10_Agenda sheet)
                                         sectionTop: 17.33,         // measured: footer box to the next card
                                         sectionBottom: 17.67,      // measured: card to the next header box
                                         headerPaddingTop: 10,      // measured: header box 40.33 = 10 + 20.33 + 10
                                         headerPaddingBottom: 10,
                                         footerPaddingTop: 8,       // measured: footer box 45.67 = 8 + 31.33 + 6.33
                                         footerPaddingBottom: 6.33)
        m.switchRowInsetVertical = 11.5                            // measured: toggle rows 52, with a 29pt label icon too
        m.chevronSize = CGSize(width: 5, height: 10)               // measured: 7x12 with the 2pt stroke
        m.chevronTrailingPad = 3.33                                // measured: chevron ink ends 18.33 from the card edge
        m.chevronReserve = 22                                      // measured: trailing value ends 22 before the row inset
        return m
    }

    /// The metrics a List of `style` is drawn with: glass looks for inset grouped and plain lists; grouped
    /// and inset lists keep the iOS 18 geometry.
    static func forDesign(_ design: DesignLanguage, style: ListStyleKind) -> ListDesignMetrics {
        switch style {
        case .insetGrouped: return forDesign(design)
        case .plain where design.isGlass: return glassPlain(design)
        default: return forDesign(.flat)
        }
    }

    /// Plain lists on iOS 26 and 27: the inset grouped row and separator metrics without cards.
    static func glassPlain(_ design: DesignLanguage) -> ListDesignMetrics {
        let glass = forDesign(design)
        var m = forDesign(.flat)
        m.minRowHeight = glass.minRowHeight
        m.rowInsetVertical = glass.rowInsetVertical           // measured: iOS 27.0 simulator (10_Agenda rows 93 = 63 + 2 * 15)
        m.rowInsetHorizontal = glass.rowInsetHorizontal
        m.plainExtraInset = 0                                 // measured: iOS 27.0 simulator (rows and headers at 16)
        m.separatorTrailingInset = 16                         // measured: iOS 27.0 simulator
        m.separatorThickness = glass.separatorThickness
        m.separatorColors = glass.separatorColors
        m.plainSections = (headerPadding: 10, gap: 22)        // measured: iOS 27.0 simulator (header box 40.33, 22 below the last row)
        m.plainHeaderFontSize = 17                            // measured: iOS 27.0 simulator (17pt semibold)
        m.switchRowInsetVertical = glass.switchRowInsetVertical
        m.chevronSize = glass.chevronSize
        m.chevronTrailingPad = glass.chevronTrailingPad
        m.chevronReserve = glass.chevronReserve
        return m
    }

    /// tvOS rows: full-width platters without cards or separators (values in TVMetrics, est.).
    static func forTV() -> ListDesignMetrics {
        ListDesignMetrics(minRowHeight: TVMetrics.rowMinHeight, rowInsetVertical: TVMetrics.rowVerticalInset,
                          rowInsetHorizontal: TVMetrics.rowHorizontalInset, cardCornerRadius: TVMetrics.rowCornerRadius,
                          separatorTrailingInset: 0, headerFontSize: TVMetrics.headerFontSize, headerWeight: .semibold,
                          headerUppercased: false, headerBaselineToCard: TVMetrics.headerBottomGap)
    }

    @MainActor static func colors(_ env: EnvironmentValues, style: ListStyleKind) -> (background: RGBA, card: RGBA) {
        let scheme = env.colorScheme
        let elevated = env.isElevatedPresentation && scheme == .dark
        switch style {
        case .insetGrouped, .grouped:
            return elevated
                ? (SystemColor.secondaryBackground.resolve(scheme), SystemColor.tertiaryBackground.resolve(scheme))
                : (SystemColor.groupedBackground.resolve(scheme), SystemColor.secondaryGroupedBackground.resolve(scheme))
        case .plain, .inset:
            let bg = elevated ? SystemColor.secondaryBackground.resolve(scheme) : SystemColor.background.resolve(scheme)
            return (bg, bg)
        }
    }
}
