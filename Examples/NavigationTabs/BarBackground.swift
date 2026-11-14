import SwiftUI

#Preview {
    NavigationStack {
        Rows()
            .navigationTitle("Visible Bar")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.blue, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct Rows: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6) { i in Text("Item \(i)").frame(maxWidth: .infinity, minHeight: 44) }
            Spacer()
        }
    }
}
