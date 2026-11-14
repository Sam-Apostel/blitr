import SwiftUI
import OrchardKit
import OrchardUI

/// The season on the living-room screen: one card per tree.
struct TVBoardView: View {
    let state: OrchardState

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text("orchard.title")
                .font(OrchardTheme.pixel(72))
            #if os(tvOS)
            Text("Total \(kilogramsText(state.totalKilograms))")
                .font(.title2)
            #else
            Text(verbatim: "This branch is for other platforms and must not be compiled for the TV target.")
            #endif
            HStack(spacing: 32) {
                ForEach(state.trees) { tree in
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: tree.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(OrchardTheme.leaf)
                        Text(tree.name)
                            .font(.headline)
                        Text("\(tree.harvests.count) harvests")
                            .foregroundStyle(.secondary)
                        WeightBadge(kilograms: tree.totalKilograms)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .orchardCard()
                }
            }
            Spacer()
        }
        .padding(80)
    }
}

#Preview("Board") {
    TVBoardView(state: SampleOrchard.state)
}
