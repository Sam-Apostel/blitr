// Kept in its own file: `Visibility` is shared by many modifiers (scrollContentBackground, toolbar, listRowSeparator...).

public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic, visible, hidden
}
