// Metrics of the Liquid Glass navigation bar, toolbars and search field (iOS 26 / 27).
//
// Values marked (est.) are estimates from reference screenshots, kept here so they can be
// calibrated against captures. The iOS 18 bar keeps its own `NavigationBarMetrics`.

struct NavigationGlassMetrics {
    // Bar.
    /// Height of the bar's content row (the glass items' row), under the status bar.
    var barHeight: CGFloat = 44                       // (est.)
    /// Distance of the outermost glass item from the screen edge.
    var horizontalMargin: CGFloat = 16
    /// Minimum gap between the inline title / principal item and the glass items.
    var titleItemGap: CGFloat = 8

    // Items.
    /// Height of a glass capsule in the navigation bar; a single icon item is a circle of this size.
    var itemHeight: CGFloat = 44
    /// Width each icon item takes in a shared capsule (centre-to-centre distance of icons).
    var iconCellWidth: CGFloat = 44                   // (est.)
    /// Horizontal padding around a text item inside its capsule.
    var textItemPadding: CGFloat = 14                 // (est.)
    /// Gap between separate capsules (a fixed `ToolbarSpacer`, or items that cannot share glass).
    var groupSpacing: CGFloat = 12                    // (est.)
    /// Item labels. iOS 26 bar buttons use a medium weight (text and glyphs), 17pt.
    var itemFont = Font.system(size: 17, weight: .medium)
    /// `.confirmationAction` and `.confirm` role labels.
    var prominentItemFont = Font.system(size: 17, weight: .semibold)

    // Back button: a glass circle with a chevron and no title.
    var backChevronSize = CGSize(width: 10, height: 17.5)
    var backChevronLineWidth: CGFloat = 2.5
    /// The chevron sits a little left of the circle's centre, like the glyph's optical centre.
    var backChevronOffsetX: CGFloat = -1

    // Titles.
    var inlineTitleFont = Font.system(size: 17, weight: .semibold)
    /// Inline title when a `navigationSubtitle` is shown under it.
    var inlineTitleWithSubtitleFont = Font.system(size: 15, weight: .semibold)   // (est.)
    var inlineSubtitleFont = Font.system(size: 12)
    var inlineSubtitleSpacing: CGFloat = 1
    /// Subtitle under a large title, and the height it adds to the large title region.
    var largeSubtitleFont = Font.system(size: 15)     // (est.)
    var largeSubtitleHeight: CGFloat = 20             // (est.)

    // Bottom bar.
    var bottomBarHeight: CGFloat = 48                 // (est.)
    var bottomBarSideInset: CGFloat = 16
    /// Bottom edge of the floating bar above the screen bottom (home-indicator devices).
    var bottomBarBottomInset: CGFloat = 21            // (est.)
    /// Same on devices without a home indicator (home button, or a stack that does not reach the screen bottom).
    var bottomBarBottomInsetNoIndicator: CGFloat = 8  // (est.)

    // Search under the title (`.navigationBarDrawer`).
    var drawerSearchTopGap: CGFloat = 6               // (est.)
    var drawerSearchBottomGap: CGFloat = 8            // (est.)

    // Scroll edge effect.
    /// How far the soft (progressive) edge effect fades out past the bar.
    var softEdgeFade: CGFloat = 24                    // (est.)
    var softEdgeBlurRadius: CGFloat = 12              // (est.)
    /// Opacity of the system background wash laid into the soft edge.
    var softEdgeTintOpacity: Double = 0.55            // (est.)

    /// The default scroll edge effect under bars: iOS 26 soft, iOS 27 hard.
    var defaultScrollEdgeHard = false

    static func forDesign(_ design: DesignLanguage) -> NavigationGlassMetrics {
        var m = NavigationGlassMetrics()
        if design == .liquidGlass27 { m.defaultScrollEdgeHard = true }
        return m
    }

    /// The glass search field.
    struct Search {
        var bottomHeight: CGFloat = 48                // (est.)
        var drawerHeight: CGFloat = 44                // (est.)
        var glyphCenterX: CGFloat = 22
        var glyphRadius: CGFloat = 7
        var glyphLineWidth: CGFloat = 2.1
        var textLeading: CGFloat = 38
        var textTrailing: CGFloat = 16
        var micTrailing: CGFloat = 16
    }
    static let search = Search()

    /// Drawer search region added under the title.
    var drawerSearchRegion: CGFloat { drawerSearchTopGap + NavigationGlassMetrics.search.drawerHeight + drawerSearchBottomGap }
}
