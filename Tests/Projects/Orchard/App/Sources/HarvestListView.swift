import SwiftUI
import OrchardKit
import OrchardUI

/// The first screen: every tree with what it gave this season.
struct HarvestListView: View {
    @EnvironmentObject private var store: OrchardStore
    @Environment(\.seasonDay) private var seasonDay

    var body: some View {
        NavigationStack {
            List {
                if store.state.trees.isEmpty {
                    Text("No trees yet")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(store.state.trees.prefix(store.visibleLimit)) { tree in
                            TreeRow(tree: tree)
                        }
                    } header: {
                        Text("Trees")
                    } footer: {
                        Text("Total \(kilogramsText(store.state.totalKilograms))")
                    }
                    Section {
                        Text(store.state.headline)
                        Text("Day \(seasonDay) of the season")
                            .accessibilityHint(Text(verbatim: orchardSurfaceName))
                    }
                }
            }
            .navigationTitle("orchard.title")
        }
    }
}

struct TreeRow: View {
    let tree: Tree

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tree.symbolName)
                .foregroundStyle(OrchardTheme.leaf)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tree.name)
                    .font(.headline)
                Text("\(tree.harvests.count) harvests")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            WeightBadge(kilograms: tree.totalKilograms)
        }
        .padding(.vertical, 2)
    }
}

#Preview("Harvest list") {
    HarvestListView()
        .environmentObject(OrchardStore(state: SampleOrchard.state))
        .environment(\.seasonDay, 211)
}

#Preview(
    "Empty orchard",
    traits: .portrait
) {
    HarvestListView()
        .environmentObject(OrchardStore(state: SampleOrchard.empty))
}
