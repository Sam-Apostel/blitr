import SwiftUI
import Observation

// MARK: - Model

enum FitnessRange: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
}

struct FitnessSummary: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
}

@Observable
final class FitnessModel {
    var range: FitnessRange = .week
    var summaries: [FitnessSummary] = []
    var moveProgress = 0.72
    var exerciseProgress = 0.55
    var standProgress = 0.83

    var bars: [Double] {
        switch range {
        case .day: return [0.2, 0.5, 0.8, 0.4, 0.6, 0.9, 0.3]
        case .week: return [0.5, 0.7, 0.4, 0.9, 0.6, 0.8, 0.3]
        case .month: return [0.6, 0.8, 0.7, 0.9, 0.5, 0.75, 0.85]
        }
    }

    func load() {
        summaries = [
            FitnessSummary(title: "Steps", value: "8,432", unit: "steps", symbol: "figure.walk", color: .green),
            FitnessSummary(title: "Calories", value: "486", unit: "kcal", symbol: "flame.fill", color: .orange),
            FitnessSummary(title: "Heart Rate", value: "68", unit: "bpm", symbol: "heart.fill", color: .red),
            FitnessSummary(title: "Sleep", value: "7h 12m", unit: "", symbol: "bed.double.fill", color: .indigo),
        ]
    }
}

// MARK: - Subviews

struct FitnessRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct FitnessActivityRings: View {
    let move: Double, exercise: Double, stand: Double

    var body: some View {
        ZStack {
            FitnessRing(progress: move, color: .red, lineWidth: 16)
            FitnessRing(progress: exercise, color: .green, lineWidth: 16).padding(20)
            FitnessRing(progress: stand, color: .cyan, lineWidth: 16).padding(40)
        }
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move \(Int(move * 100)) percent, exercise \(Int(exercise * 100)) percent, stand \(Int(stand * 100)) percent")
    }
}

struct FitnessSummaryCard: View {
    let item: FitnessSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(item.title, systemImage: item.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.value).font(.title.bold()).monospacedDigit()
                Text(item.unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FitnessBarChart: View {
    let values: [Double]
    let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top))
                        .frame(height: 120 * value)
                    Text(labels[index]).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150, alignment: .bottom)
        .animation(.easeInOut(duration: 0.4), value: values)
    }
}

// MARK: - Screen

struct FitnessDashboardScreen: View {
    @State private var model = FitnessModel()

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Range", selection: $model.range) {
                        ForEach(FitnessRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 20) {
                        FitnessActivityRings(move: model.moveProgress, exercise: model.exerciseProgress, stand: model.standProgress)
                        VStack(alignment: .leading, spacing: 10) {
                            legend("Move", "432/600 kcal", .red)
                            legend("Exercise", "22/40 min", .green)
                            legend("Stand", "10/12 hr", .cyan)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(model.summaries) { FitnessSummaryCard(item: $0) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active energy").font(.headline)
                        FitnessBarChart(values: model.bars)
                    }
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Gauge(value: 0.68) { Text("Weekly goal") } currentValueLabel: { Text("68%") }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(.green)
                        ProgressView("Hydration", value: 5, total: 8)
                            .tint(.blue)
                    }
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(16)
            }
            .navigationTitle("Summary")
            .task { model.load() }
        }
    }

    private func legend(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.subheadline).monospacedDigit()
        }
    }
}

#Preview {
    FitnessDashboardScreen()
}

#Preview("Dark") {
    FitnessDashboardScreen().preferredColorScheme(.dark)
}
