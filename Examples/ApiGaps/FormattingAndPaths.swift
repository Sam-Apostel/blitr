import SwiftUI

// AttributedString(localized:) (Markdown in the localized string is interpreted), MeasurementFormatter,
// and the iOS 17 path boolean operations.

struct FormattingAndPathsExample: View {
    private let distance = Measurement(value: 12.4, unit: UnitLength.kilometers)
    private let temperature = Measurement(value: 21.5, unit: UnitTemperature.celsius)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AttributedString(localized: "Welcome back, **Sam**! You have \(3) new messages."))
            Text(AttributedString(localized: "onboarding.title", defaultValue: "Start your *first* run", comment: "Title"))
            Text(AttributedString(localized: LocalizedStringResource("Read the [guide](https://example.com)")))

            Divider()
            Text(formatted(distance, style: .short, options: .providedUnit))
            Text(formatted(distance, style: .medium, options: []))
            Text(formatted(distance, style: .long, options: .providedUnit))
            Text(formatted(temperature, style: .medium, options: []))
            Text(formatted(temperature, style: .short, options: .temperatureWithoutUnit))
            Text(formatted(Measurement(value: 1500, unit: UnitLength.meters), style: .medium, options: [.providedUnit, .naturalScale]))
            Text(formatted(Measurement(value: 95, unit: UnitDuration.minutes), style: .long, options: [.providedUnit, .naturalScale]))

            Divider()
            HStack(spacing: 16) {
                let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 60, height: 60))
                let square = Path(CGRect(x: 30, y: 15, width: 45, height: 45))
                circle.union(square).fill(.blue).frame(width: 75, height: 60)
                circle.intersection(square).fill(.green).frame(width: 75, height: 60)
                circle.subtracting(square).fill(.orange).frame(width: 75, height: 60)
                circle.symmetricDifference(square).fill(.purple).frame(width: 75, height: 60)
            }
            HStack(spacing: 16) {
                let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 60, height: 60))
                let square = Path(CGRect(x: 30, y: 15, width: 45, height: 45))
                circle.lineSubtracting(square).stroke(.red, lineWidth: 3).frame(width: 75, height: 60)
                circle.lineIntersection(square).stroke(.red, lineWidth: 3).frame(width: 75, height: 60)
                Circle().subtracting(Rectangle().offset(x: 30)).fill(.teal).frame(width: 60, height: 60)
                Capsule().symmetricDifference(Circle(), eoFill: true).fill(.pink).frame(width: 75, height: 50)
            }
        }
        .padding()
    }

    private func formatted<U: Unit>(_ m: Measurement<U>, style: Formatter.UnitStyle, options: MeasurementFormatter.UnitOptions) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitStyle = style
        formatter.unitOptions = options
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: m)
    }
}

#Preview("Formatting and paths") {
    FormattingAndPathsExample()
}
