import SwiftUI
import OrchardKit

/// Holds the orchard and sends actions through OrchardKit's reducer.
final class OrchardStore: ObservableObject {
    @Published private(set) var state: OrchardState
    /// How many trees the list shows before "Show all".
    @Clamped(1...50) var visibleLimit: Int = 12

    init(state: OrchardState) {
        self.state = state
    }

    func send(_ action: OrchardAction) {
        reduce(&state, action)
    }
}

#if ORCHARD_APP
/// Only the app target defines ORCHARD_APP; the list reads this, so it compiles only with the target's flags.
let orchardSurfaceName = "iPhone"
#endif
