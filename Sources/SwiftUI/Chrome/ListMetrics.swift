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
}

extension ListMetrics {
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
