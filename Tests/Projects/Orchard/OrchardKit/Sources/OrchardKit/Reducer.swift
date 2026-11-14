import Foundation

public enum OrchardAction: Equatable, Sendable {
    case plant(Tree)
    case rename(treeID: String, to: String)
    case record(treeID: String, Harvest)
    case fell(treeID: String)
}

/// Applies one action. Unknown tree ids are ignored, as a replayed log may mention felled trees.
public func reduce(_ state: inout OrchardState, _ action: OrchardAction) {
    switch action {
    case .plant(let tree):
        guard !state.trees.contains(where: { $0.id == tree.id }) else { return }
        state.trees.append(tree)
    case .rename(let id, let name):
        guard let index = state.trees.firstIndex(where: { $0.id == id }) else { return }
        state.trees[index].name = name
    case .record(let id, let harvest):
        guard let index = state.trees.firstIndex(where: { $0.id == id }) else { return }
        state.trees[index].harvests.append(harvest)
        state.trees[index].harvests.sort { $0.day < $1.day }
    case .fell(let id):
        state.trees.removeAll { $0.id == id }
    }
}

extension OrchardState {
    public func applying(_ actions: [OrchardAction]) -> OrchardState {
        var copy = self
        for action in actions { reduce(&copy, action) }
        return copy
    }

    /// A one-line summary for a notification or a widget.
    public var headline: String {
        guard let best = bestTree, best.totalKilograms > 0 else { return String(localized: "Nothing picked yet") }
        return String(localized: "Best tree: \(best.name)")
    }
}
