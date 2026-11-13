import SwiftUI

struct IndicatorsDemo: View {
    @State private var on = true
    @State private var off = false
    @State private var volume = 0.4
    @State private var count = 3
    var body: some View {
        VStack(spacing: 16) {
            Toggle("Airplane Mode", isOn: $off)
            Toggle("Wi-Fi", isOn: $on)
            Toggle("Tinted", isOn: $on).tint(.orange)
            Toggle("Disabled", isOn: $on).disabled(true)
            Toggle(isOn: $on) { Text("Button style") }.toggleStyle(.button)
            Slider(value: $volume)
            Slider(value: $volume, in: 0...1) { Text("v") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            Stepper("Count: \(count)", value: $count, in: 0...10)
            Stepper("At min", value: .constant(0), in: 0...10)
            ProgressView(value: 0.6)
            ProgressView("Downloading", value: 0.3)
            ProgressView(value: 40, total: 100) { Text("Uploading") } currentValueLabel: { Text("40%") }
            HStack(spacing: 20) {
                ProgressView()
                ProgressView("Loading")
                ProgressView(value: 0.7).progressViewStyle(.circular)
            }
            Gauge(value: 0.7) { Text("Battery") } currentValueLabel: { Text("70%") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
            HStack(spacing: 20) {
                Gauge(value: 0.7) { Text("B") } currentValueLabel: { Text("70") }.gaugeStyle(.accessoryCircular)
                Gauge(value: 0.4) { Text("B") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryCircularCapacity)
            }
        }
        .padding(20)
    }
}

#Preview { IndicatorsDemo() }
