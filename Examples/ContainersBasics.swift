import SwiftUI

struct Card: View {
    let i: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 140, height: 90)
            .overlay(Text("Card \(i)").foregroundStyle(.white).font(.headline))
    }
}

struct Demo: View {
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Featured").font(.title2.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(1..<7) { Card(i: $0) }
                    }
                    .padding(.horizontal)
                }
                Text("Grid").font(.title2.bold())
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(1..<10) { i in
                        RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.7))
                            .frame(height: 60)
                            .overlay(Text("\(i)"))
                    }
                }
                Text("Adaptive").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(1..<8) { i in
                        Circle().fill(Color.green).frame(height: 70).overlay(Text("\(i)"))
                    }
                }
                Text("Grid view").font(.title2.bold())
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").bold()
                        Text("Qty").bold().gridColumnAlignment(.trailing)
                        Text("Price").bold().gridColumnAlignment(.trailing)
                    }
                    Divider()
                    GridRow {
                        Text("Apples, red")
                        Text("3")
                        Text("$4.50")
                    }
                    GridRow {
                        Text("Bananas")
                        Text("12")
                        Text("$1.20")
                    }
                    GridRow {
                        Text("Total spanning two").gridCellColumns(2)
                        Text("$5.70")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .background(Color(white: 0.97))
    }
}

#Preview { Demo() }
