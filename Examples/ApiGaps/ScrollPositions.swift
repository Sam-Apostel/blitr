import SwiftUI

// ScrollPosition: the scroll view is drawn where the position puts it (an edge, a point, a view id).

struct NumberedRows: View {
    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(1...40, id: \.self) { number in
                Text("Row \(number)")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(number % 10 == 0 ? Color.orange.opacity(0.4) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
    }
}

struct ScrollPositionExample: View {
    @State var position: ScrollPosition
    var anchor: UnitPoint? = nil
    var body: some View {
        ScrollView { NumberedRows() }
            .scrollPosition($position, anchor: anchor)
    }
}

struct ScrollPositionMutationExample: View {
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var horizontal = ScrollPosition(x: 0)
    @State private var selectedID: Int? = 7

    var body: some View {
        VStack(spacing: 12) {
            Text("scrollTo(id: 30, anchor: .top) in onAppear").font(.caption)
            ScrollView { NumberedRows() }
                .scrollPosition($position)
                .frame(height: 220)
                .border(.gray)
            Text("Horizontal, scrollTo(edge: .trailing)").font(.caption)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(1...20, id: \.self) { number in
                        Text("\(number)").frame(width: 50, height: 50).background(.green.opacity(0.2), in: Circle())
                    }
                }
            }
            .scrollPosition($horizontal)
            .border(.gray)
            Text("scrollPosition(id:) with id 7, anchor .center").font(.caption)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(1...20, id: \.self) { number in
                        Text("\(number)").frame(width: 50, height: 50)
                            .background(number == 7 ? Color.orange.opacity(0.5) : Color.green.opacity(0.2), in: Circle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $selectedID, anchor: .center)
            .border(.gray)
            Text(summary).font(.footnote.monospaced())
        }
        .padding()
        .onAppear {
            position.scrollTo(id: 30, anchor: .top)
            horizontal.scrollTo(edge: .trailing)
        }
    }

    private var summary: String {
        var probe = ScrollPosition(point: CGPoint(x: 4, y: 120))
        let point = probe.point ?? .zero
        probe.scrollTo(y: 80)
        probe.scrollTo(x: 10, y: 20)
        probe.scrollTo(x: 12)
        probe.scrollTo(point: CGPoint(x: 1, y: 2))
        let id = position.viewID(type: Int.self).map(String.init) ?? "none"
        return "id \(id), edge \(horizontal.edge == .trailing ? "trailing" : "other"), point y \(Int(point.y)), byUser \(position.isPositionedByUser)"
    }
}

#Preview("Bottom edge") {
    ScrollPositionExample(position: ScrollPosition(edge: .bottom))
}

#Preview("View id, centred") {
    ScrollPositionExample(position: ScrollPosition(id: 20), anchor: .center)
}

#Preview("Point") {
    ScrollPositionExample(position: ScrollPosition(y: 300))
}

#Preview("Mutating positions") {
    ScrollPositionMutationExample()
}
