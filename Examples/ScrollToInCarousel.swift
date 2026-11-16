import SwiftUI

// A carousel inside a scrolling page scrolls itself to its current card when it appears. The proxy belongs
// to the carousel's ScrollViewReader, so only the carousel moves: the page stays at its top.

struct CarouselCard: View {
    var index: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(index == 3 ? Color.orange : Color.gray.opacity(0.25))
            .frame(width: 220, height: 140)
            .overlay(Text("Card \(index)").font(.headline))
    }
}

struct ScrollToInCarouselView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top of the page").font(.largeTitle.bold()).padding(.horizontal, 20)
                ForEach(1...4, id: \.self) { i in
                    Text("Paragraph \(i)").padding(.horizontal, 20)
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(1...6, id: \.self) { i in CarouselCard(index: i).id(i) }
                        }
                        .padding(.horizontal, 20)
                    }
                    .onAppear { DispatchQueue.main.async { proxy.scrollTo(3, anchor: .center) } }
                }
                ForEach(5...40, id: \.self) { i in
                    Text("Paragraph \(i)").padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    ScrollToInCarouselView()
}
