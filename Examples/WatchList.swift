// A plain watch list: a NavigationStack title over a few rows. Render with `--device apple-watch`,
// `apple-watch-series-10-42mm` or `apple-watch-ultra-2`.
//
//   swiftui-screenshot render Examples/WatchList.swift --device apple-watch --all --out-dir out/watch
import SwiftUI

struct WatchPlant: Identifiable {
    let id = UUID()
    let name: String
    let note: String
}

private let plants = [
    WatchPlant(name: "Fern", note: "Water today"),
    WatchPlant(name: "Basil", note: "In 2 days"),
    WatchPlant(name: "Cactus", note: "Next week"),
    WatchPlant(name: "Orchid", note: "Mist leaves"),
]

struct WatchPlantList: View {
    var body: some View {
        NavigationStack {
            List(plants) { plant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(plant.name)
                    Text(plant.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plants")
        }
    }
}

#Preview("List") {
    WatchPlantList()
}

#Preview("Rows") {
    NavigationStack {
        List {
            Label("Fern", systemImage: "drop.fill")
            Label("Basil", systemImage: "leaf.fill")
            Label("Cactus", systemImage: "sun.max.fill")
            Text("Plain row")
        }
        .navigationTitle("Garden")
    }
}
