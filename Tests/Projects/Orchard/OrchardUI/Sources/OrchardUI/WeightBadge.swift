import SwiftUI

/// A weight in the pixel font on a leaf-green capsule.
public struct WeightBadge: View {
    let kilograms: Double

    public init(kilograms: Double) {
        self.kilograms = kilograms
    }

    public var body: some View {
        Text(verbatim: "\(Int(kilograms.rounded())) KG")
            .font(OrchardTheme.pixel(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OrchardTheme.leaf, in: Capsule())
    }
}

#Preview("Badges", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        WeightBadge(kilograms: 6.5)
        WeightBadge(kilograms: 58.5)
        Text("Bark").foregroundStyle(OrchardTheme.bark)
    }
    .padding()
}
