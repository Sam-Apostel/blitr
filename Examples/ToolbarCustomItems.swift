import SwiftUI

// Toolbar items that are views of their own, not a plain button: a back chevron and a picker chip
// in one HStack, a stack with a divider, a custom capsule that hides the shared glass. From iOS 26
// the navigation bar puts each item on its glass unless the item hides it.

struct DayChip: View {
    var title: String
    var body: some View {
        Menu {
            Button("Monday 20") {}
            Button("Tuesday 21") {}
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 17, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

struct ToolbarCustomItemsView: View {
    var hidesSharedBackground = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
                        .frame(height: 320)
                    ForEach(1...8, id: \.self) { i in
                        Text("Stop \(i)").font(.title3.weight(.semibold)).padding(.horizontal, 20)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 0) {
                        Button {} label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(.primary.opacity(0.2)).frame(width: 1, height: 20)
                        DayChip(title: "Tue 21")
                    }
                    .fixedSize()
                }
                .sharedBackgroundVisibility(hidesSharedBackground ? .hidden : .automatic)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit") {}
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
    }
}

#Preview("Custom item") {
    ToolbarCustomItemsView()
}

#Preview("Custom item, background hidden") {
    ToolbarCustomItemsView(hidesSharedBackground: true)
}
