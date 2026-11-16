import Foundation

/// iPhone Duo with its status bar as a column at the trailing edge (`DeviceProfile.statusColumnChrome`): the
/// navigation bar's buttons and the tab bar sit in that column, as vertical glass capsules.
/// measured: iOS 27.2 simulator, Examples/FoldChrome in the closed, partially open and open postures (the
/// same geometry in all three, the closed cover display's toolbar 50pt lower; see `RingStatusBar.toolbarTop`).
enum StatusColumnChrome {
    /// Every capsule is this wide and starts this far from the screen's trailing edge (centred in the 84pt
    /// column, 6pt nearer its leading side).
    static let width: CGFloat = 48
    static let fromScreenTrailing: CGFloat = 72

    // Toolbar groups: 38pt item cells, 14pt apart, 5pt from the capsule's ends; 12pt between capsules.
    static let itemCell: CGFloat = 38
    static let itemSpacing: CGFloat = 14
    static let itemEndInset: CGFloat = 5
    static let groupGap: CGFloat = 12

    // Tab rail: 44x58 item frames 50pt apart (they overlap), 2pt from the capsule's ends, the capsule 24pt
    // above the bottom of the screen. The selected tab's pill is its item frame. Titles are not drawn.
    static let tabCell = CGSize(width: 44, height: 58)
    static let tabStep: CGFloat = 50
    static let tabEndInset: CGFloat = 2
    static let railBottomInset: CGFloat = 24

    /// Height of a toolbar capsule holding `count` items.
    static func groupHeight(_ count: Int) -> CGFloat {
        CGFloat(count) * itemCell + CGFloat(max(0, count - 1)) * itemSpacing + itemEndInset * 2
    }
    /// Height of the tab rail holding `count` tabs.
    static func railHeight(_ count: Int) -> CGFloat {
        CGFloat(max(0, count - 1)) * tabStep + tabCell.height + tabEndInset * 2
    }
}
