// Metrics of the Liquid Glass navigation bar, toolbars and search field (iOS 26 / 27).
//
// Values marked (est.) are estimates from reference screenshots, kept here so they can be
// calibrated against captures. The iOS 18 bar keeps its own `NavigationBarMetrics`.

struct NavigationGlassMetrics {
    // Bar.
    /// Height of the bar's content row (the glass items' row), under the status bar.
    var barHeight: CGFloat = 44                       // measured: iOS 27.0 simulator (items y 59...103)
    /// Space the bar adds under its item row before content starts (safe area top = status bar + 54).
    var barBottomPadding: CGFloat = 10                // measured: iOS 27.0 simulator
    /// Distance of the outermost glass item from the screen edge.
    var horizontalMargin: CGFloat = 16                // measured: iOS 27.0 simulator
    /// Minimum gap between the inline title / principal item and the glass items.
    var titleItemGap: CGFloat = 8

    // Items. An item's frame (its accessibility frame on iOS) is its glyph or text plus padding; a capsule
    // holds its items' frames with `itemSpacing` between them and `itemEndInset` at both ends, and is never
    // narrower than it is tall (a single icon is a circle).
    /// Height of a glass capsule in the navigation bar; a single icon item is a circle of this size.
    var itemHeight: CGFloat = 44                      // measured: iOS 27.0 simulator
    /// Height of an item's frame inside its capsule.
    var itemFrameHeight: CGFloat = 36                 // measured: iOS 27.0 simulator (XCUI frames)
    /// Padding on each side of an icon item's glyph.
    var iconItemPadding: CGFloat = 10                 // measured: iOS 27.0 simulator (heart 41pt, ellipsis 38pt)
    /// Same for an icon alone on its circle.
    var singleIconItemPadding: CGFloat = 4            // measured: iOS 27.0 simulator (plus 27.3pt, compose 28.7pt)
    /// Padding on each side of a button's text.
    var textItemPadding: CGFloat = 12                 // measured: iOS 27.0 simulator ("Edit" 53.3pt, "Cancel" 76.7pt)
    /// Padding on each side of text that is not a button (a NavigationLink or plain Text).
    var plainTextItemPadding: CGFloat = 6             // measured: iOS 27.0 simulator (NavigationLink "Cancel" 64.7pt)
    /// Space between item frames in a shared capsule, and from the outer frames to the capsule ends.
    var itemSpacing: CGFloat = 16                     // measured: iOS 27.0 simulator
    var itemEndInset: CGFloat = 4                     // measured: iOS 27.0 simulator
    /// Gap between separate capsules (a fixed `ToolbarSpacer`, or items that cannot share glass).
    var groupSpacing: CGFloat = 12                    // measured: iOS 27.0 simulator
    /// Item labels: 17pt regular text, glyphs at the large symbol scale.
    var itemFont = Font.system(size: 17)              // measured: iOS 27.0 simulator
    var itemImageScale = Image.Scale.large            // measured: iOS 27.0 simulator (gear 23pt, xmark 17.3pt)
    /// `.confirmationAction` and `.confirm` role labels.
    var prominentItemFont = Font.system(size: 17, weight: .semibold)

    // Back button: a glass circle with a chevron and no title.
    var backChevronSize = CGSize(width: 8.8, height: 16.7)   // measured: iOS 27.0 simulator (ink 11 x 19pt)
    var backChevronLineWidth: CGFloat = 2.3
    /// The chevron sits a little left of the circle's centre, like the glyph's optical centre.
    var backChevronOffsetX: CGFloat = -1.5            // measured: iOS 27.0 simulator

    // Titles.
    var inlineTitleFont = Font.system(size: 17, weight: .semibold)
    /// Inline title when a `navigationSubtitle` is shown under it.
    var inlineTitleWithSubtitleFont = Font.system(size: 15, weight: .semibold)   // (est.)
    var inlineSubtitleFont = Font.system(size: 12)
    var inlineSubtitleSpacing: CGFloat = 0            // measured: iOS 27.0 simulator
    /// Large title region under the item row, and the title's baseline above its bottom.
    var largeTitleHeight: CGFloat = 52                // measured: iOS 27.0 simulator (content at 165pt)
    var largeTitleBaselineInset: CGFloat = 16         // measured: iOS 27.0 simulator (baseline at 149pt)
    /// Subtitle under a large title: font, how far the title moves down for it, the distance
    /// between the two baselines, and the height it adds to the large title region.
    var largeSubtitleFont = Font.system(size: 11, weight: .semibold)   // measured: iOS 27.0 simulator (cap height 8pt, 61.7pt wide)
    var largeTitleShiftWithSubtitle: CGFloat = 3      // measured: iOS 27.0 simulator (baseline at 152pt)
    var largeSubtitleBaselineGap: CGFloat = 16.5      // measured: iOS 27.0 simulator (baseline at 168.5pt)
    var largeSubtitleHeight: CGFloat = 11.5           // (est.) no reference shows content under it

    // Bottom bar.
    var bottomBarHeight: CGFloat = 48                 // measured: iOS 27.0 simulator
    var bottomBarSideInset: CGFloat = 28              // measured: iOS 27.0 simulator
    /// Bottom-bar capsules: item spacing and end inset (the item frames are `itemFrameHeight` tall).
    var bottomItemSpacing: CGFloat = 14               // measured: iOS 27.0 simulator
    var bottomItemEndInset: CGFloat = 5.33            // measured: iOS 27.0 simulator
    /// A bottom item next to the search field shares its capsule; the field starts this far after the item's frame.
    var searchJoinGap: CGFloat = 9                    // measured: iOS 27.0 simulator
    /// Content ends this far above the floating bottom bar (its safe area inset).
    var bottomBarContentGap: CGFloat = 10             // measured: iOS 27.0 simulator
    /// Bottom edge of the floating bar above the screen bottom (home-indicator devices).
    var bottomBarBottomInset: CGFloat = 28            // measured: iOS 27.0 simulator (bar 776...824pt)
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

    /// What the `.automatic` scroll edge effect draws over scroll content under a bar.
    enum DefaultScrollEdge { case none, soft, hard }
    /// Nothing at rest, on iOS 26 and 27. measured: iOS 26.5 and 27.0 simulators; list rows under the tab bar
    /// (NavigationTabs-Tabs) and full-bleed content under both bars (GlassNavigation) are neither blurred nor dimmed.
    /// An explicit `.soft` or `.hard` style is still drawn.
    var defaultScrollEdge = DefaultScrollEdge.none

    static func forDesign(_ design: DesignLanguage) -> NavigationGlassMetrics { NavigationGlassMetrics() }

    /// The glass search field.
    struct Search {
        var bottomHeight: CGFloat = 48                // measured: iOS 27.0 simulator
        var drawerHeight: CGFloat = 44                // (est.)
        /// Magnifying glass: ink 41.7...58.3pt in a field starting at 27.7pt. measured: iOS 27.0 simulator
        var glyphCenterX: CGFloat = 21.2
        var glyphRadius: CGFloat = 5.6
        var glyphLineWidth: CGFloat = 2.0
        var textLeading: CGFloat = 41.3               // measured: iOS 27.0 simulator
        var textTrailing: CGFloat = 16
        /// iOS 27 shows no dictation microphone in the field. measured: iOS 27.0 simulator
        var showsMicrophone = false
        var micTrailing: CGFloat = 16
    }
    static let search = Search()

    /// Drawer search region added under the title.
    var drawerSearchRegion: CGFloat { drawerSearchTopGap + NavigationGlassMetrics.search.drawerHeight + drawerSearchBottomGap }
}
