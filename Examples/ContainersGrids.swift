import SwiftUI

struct Demo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LazyHGrid").font(.headline)
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(50)), GridItem(.fixed(50))], spacing: 8) {
                    ForEach(0..<10) { i in
                        RoundedRectangle(cornerRadius: 8).fill(Color.teal)
                            .frame(width: 70)
                            .overlay(Text("\(i)").foregroundStyle(.white))
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 120)

            Text("Mixed columns").font(.headline)
            LazyVGrid(columns: [GridItem(.fixed(60)), GridItem(.flexible(minimum: 50)), GridItem(.flexible(), alignment: .trailing)], spacing: 6) {
                ForEach(0..<6) { i in
                    Text("Item \(i)").padding(4).background(Color.yellow.opacity(0.4))
                }
            }

            Text("Grid with baseline + frames").font(.headline)
            Grid(alignment: .leading) {
                GridRow {
                    Text("A").font(.largeTitle)
                    Text("small")
                    Color.red.frame(height: 20)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("B").font(.largeTitle)
                    Text("small")
                    Color.blue.frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)

            Text("LazyVStack").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(0..<3) { Text("Row \($0)").padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.gray.opacity(0.15)) }
                }
            }
            .contentMargins(16, for: .scrollContent)
            .background(Color.mint.opacity(0.2))
            .frame(height: 200)
        }
        .padding()
    }
}

#Preview { Demo() }
