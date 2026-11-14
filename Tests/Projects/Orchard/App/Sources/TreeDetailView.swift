import SwiftUI
import OrchardKit
import OrchardUI

/// One tree: its crate of fruit and every picking.
struct TreeDetailView: View {
    let tree: Tree

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(.crate)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tree.name)
                            .font(.title2.bold())
                        Text("Planted in \(String(tree.plantedYear))")
                            .foregroundStyle(OrchardTheme.bark)
                    }
                    Spacer()
                    WeightBadge(kilograms: tree.totalKilograms)
                }
                .orchardCard()

                Text("Harvest")
                    .font(OrchardTheme.pixel(22))
                    .foregroundStyle(Color.accentColor)

                ForEach(tree.harvests) { harvest in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day \(harvest.day) of the season")
                            if !harvest.note.isEmpty {
                                Text(harvest.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(kilogramsText(harvest.kilograms))
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(Color(.sky), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
    }
}

#Preview("Tree detail") {
    TreeDetailView(tree: SampleOrchard.state.trees[0])
}
