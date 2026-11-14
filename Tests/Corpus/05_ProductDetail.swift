import SwiftUI

// MARK: - Model

struct ProductColorOption: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

struct ProductDetailItem {
    let name = "Aero Trail Jacket"
    let price = 129.00
    let rating = 4.5
    let reviews = 328
    let description = "A lightweight, water-resistant shell designed for unpredictable weather. Taped seams, a packable hood and two zippered hand pockets keep you dry and moving. Made from recycled ripstop fabric with a soft brushed lining."
    let details = ["Water-resistant ripstop", "Packs into chest pocket", "Reflective trim", "Regular fit"]
    let colors = [
        ProductColorOption(id: "ocean", name: "Ocean", color: .blue),
        ProductColorOption(id: "forest", name: "Forest", color: .green),
        ProductColorOption(id: "ember", name: "Ember", color: .orange),
        ProductColorOption(id: "graphite", name: "Graphite", color: .gray),
    ]
    let sizes = ["XS", "S", "M", "L", "XL", "XXL"]
}

// MARK: - Subviews

struct ProductStars: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .foregroundStyle(.yellow)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating, specifier: "%.1f") out of 5")
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index)
        if value >= 1 { return "star.fill" }
        if value >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct ProductSwatch: View {
    let option: ProductColorOption
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(option.color.gradient)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .padding(4)
            .overlay {
                Circle().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .accessibilityLabel(option.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProductSizeChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Screen

struct ProductDetailScreen: View {
    let product = ProductDetailItem()
    @State private var selectedColor = "ocean"
    @State private var selectedSize = "M"
    @State private var descriptionOpen = true
    @State private var detailsOpen = false
    @State private var quantity = 1
    @State private var added = false

    private var activeColor: Color {
        product.colors.first { $0.id == selectedColor }?.color ?? .blue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .topTrailing) {
                        LinearGradient(colors: [activeColor.opacity(0.9), activeColor.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "figure.hiking")
                            .font(.system(size: 120))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Image(systemName: "heart")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(12)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .animation(.easeInOut, value: selectedColor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name).font(.title.bold())
                        HStack {
                            ProductStars(rating: product.rating)
                            Text("\(product.reviews) reviews").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Text(product.price, format: .currency(code: "USD")).font(.title2.weight(.semibold))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color: \(product.colors.first { $0.id == selectedColor }?.name ?? "")")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            ForEach(product.colors) { option in
                                ProductSwatch(option: option, isSelected: option.id == selectedColor)
                                    .onTapGesture { selectedColor = option.id }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Size").font(.subheadline.weight(.medium))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(product.sizes, id: \.self) { size in
                                ProductSizeChip(title: size, isSelected: size == selectedSize)
                                    .onTapGesture { selectedSize = size }
                            }
                        }
                    }

                    DisclosureGroup("Description", isExpanded: $descriptionOpen) {
                        Text(product.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    DisclosureGroup("Details", isExpanded: $detailsOpen) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(product.details, id: \.self) { Label($0, systemImage: "checkmark") .font(.callout) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "Aero Trail Jacket") { Image(systemName: "square.and.arrow.up") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Stepper("Quantity", value: $quantity, in: 1...9)
                        .labelsHidden()
                    Button {
                        withAnimation(.spring) { added = true }
                    } label: {
                        Label(added ? "Added" : "Add to Cart", systemImage: added ? "checkmark" : "bag.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

#Preview {
    ProductDetailScreen()
}

#Preview("Dark") {
    ProductDetailScreen().preferredColorScheme(.dark)
}
