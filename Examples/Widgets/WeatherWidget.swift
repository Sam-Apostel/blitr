import WidgetKit
import SwiftUI

// A weather widget in three sizes, with a gradient container background.

struct WeatherEntry: TimelineEntry {
    let date: Date
    let city: String
    let temperature: Int
    let high: Int
    let low: Int
    let condition: String
    let symbol: String
    let hourly: [HourForecast]
}

struct HourForecast: Identifiable {
    let id = UUID()
    let hour: String
    let symbol: String
    let temperature: Int
}

extension WeatherEntry {
    static let sample = WeatherEntry(
        date: .now, city: "Cupertino", temperature: 21, high: 24, low: 13, condition: "Partly Cloudy",
        symbol: "cloud.sun.fill",
        hourly: [
            HourForecast(hour: "Now", symbol: "cloud.sun.fill", temperature: 21),
            HourForecast(hour: "15", symbol: "sun.max.fill", temperature: 23),
            HourForecast(hour: "16", symbol: "sun.max.fill", temperature: 24),
            HourForecast(hour: "17", symbol: "cloud.sun.fill", temperature: 22),
            HourForecast(hour: "18", symbol: "cloud.fill", temperature: 19),
            HourForecast(hour: "19", symbol: "moon.stars.fill", temperature: 17),
        ])

    static let rainy = WeatherEntry(
        date: .now.addingTimeInterval(3600), city: "Cupertino", temperature: 15, high: 17, low: 11, condition: "Rain",
        symbol: "cloud.rain.fill",
        hourly: [
            HourForecast(hour: "Now", symbol: "cloud.rain.fill", temperature: 15),
            HourForecast(hour: "16", symbol: "cloud.rain.fill", temperature: 15),
            HourForecast(hour: "17", symbol: "cloud.drizzle.fill", temperature: 14),
            HourForecast(hour: "18", symbol: "cloud.fill", temperature: 13),
            HourForecast(hour: "19", symbol: "cloud.fill", temperature: 12),
            HourForecast(hour: "20", symbol: "moon.fill", temperature: 12),
        ])
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(.sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        completion(Timeline(entries: [.sample, .rainy], policy: .atEnd))
    }
}

struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(entry.city).font(.subheadline.weight(.semibold))
                Image(systemName: "location.fill").font(.caption2)
            }
            Text("\(entry.temperature)°").font(.system(size: 44, weight: .light))
        }
    }

    private var summary: some View { summary(alignment: .leading) }

    private func summary(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Image(systemName: entry.symbol).symbolRenderingMode(.multicolor).font(.subheadline)
            Text(entry.condition).font(.caption.weight(.semibold))
            Text("H:\(entry.high)° L:\(entry.low)°").font(.caption.weight(.semibold))
        }
    }

    private var small: some View {
        VStack(alignment: .leading) {
            header
            Spacer(minLength: 0)
            summary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hours: some View {
        HStack {
            ForEach(entry.hourly) { hour in
                VStack(spacing: 6) {
                    Text(hour.hour).font(.caption2.weight(.semibold))
                    Image(systemName: hour.symbol).symbolRenderingMode(.multicolor).font(.callout)
                        .frame(height: 20)
                    Text("\(hour.temperature)°").font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                header
                Spacer()
                summary(alignment: .trailing)
            }
            Spacer(minLength: 0)
            hours
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                header
                Spacer()
                summary
            }
            hours
            Divider().overlay(.white.opacity(0.4))
            ForEach(["Today", "Tue", "Wed", "Thu"], id: \.self) { day in
                HStack {
                    Text(day).font(.subheadline.weight(.semibold)).frame(width: 52, alignment: .leading)
                    Image(systemName: day == "Wed" ? "cloud.rain.fill" : "sun.max.fill").symbolRenderingMode(.multicolor)
                        .frame(width: 28)
                    Text("\(entry.low)°").font(.subheadline).opacity(0.7)
                    Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                    Text("\(entry.high)°").font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct WeatherWidget: Widget {
    let kind = "WeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
                .foregroundStyle(.white)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.92), Color(red: 0.42, green: 0.70, blue: 0.98)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Weather")
        .description("Current conditions and the forecast.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WeatherWidgets: WidgetBundle {
    var body: some Widget {
        WeatherWidget()
    }
}

#Preview(as: .systemSmall) {
    WeatherWidget()
} timeline: {
    WeatherEntry.sample
    WeatherEntry.rainy
}

#Preview(as: .systemMedium) {
    WeatherWidget()
} timeline: {
    WeatherEntry.sample
}

#Preview(as: .systemLarge) {
    WeatherWidget()
} timeline: {
    WeatherEntry.sample
}
