// Contracts shared by List, navigation, tab bars and the controls that change
// their appearance inside them.

public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic, visible, hidden
}

/// What a row asks its List to draw at the trailing edge.
enum ListRowAccessory {
    /// The gray chevron of a NavigationLink.
    case disclosureIndicator
}

/// Set by a view (e.g. NavigationLink) on its nodes; read by the List that lays out the row.
enum ListRowAccessoryTraitKey: TraitKey { typealias Value = ListRowAccessory }

enum IsInListRowKey: EnvironmentKey { static let defaultValue = false }
enum ScrollContentBackgroundKey: EnvironmentKey { static let defaultValue = Visibility.automatic }

extension EnvironmentValues {
    /// True while resolving the content of a List/Form row. Controls adapt to it: a
    /// NavigationLink or Button label is not tinted, a Picker shows its value trailing, etc.
    var isInListRow: Bool {
        get { self[IsInListRowKey.self] }
        set { self[IsInListRowKey.self] = newValue }
    }
    /// `.scrollContentBackground(.hidden)` removes the default List/Form background.
    var scrollContentBackground: Visibility {
        get { self[ScrollContentBackgroundKey.self] }
        set { self[ScrollContentBackgroundKey.self] = newValue }
    }
}

/// Screen-level layout constants that vary with device width.
enum ChromeMetrics {
    /// The system layout margin: 16pt on regular phones, 20pt on the wide ones.
    static func layoutMargin(forWidth width: CGFloat) -> CGFloat { width >= 414 ? 20 : 16 }
    static let hairline: CGFloat = 1.0 / 3
    static let navigationBarHeight: CGFloat = 44
    static let largeTitleHeight: CGFloat = 52
    static let tabBarHeight: CGFloat = 49
    static let toolbarHeight: CGFloat = 44
}

extension Node {
    /// First descendant (depth-first, including self) of a given node type.
    func firstDescendant<T: Node>(_ type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in children {
            if let match = child.firstDescendant(type) { return match }
        }
        return nil
    }
}
