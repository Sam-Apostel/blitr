import SwiftUI

// macOS and watchOS style members, drawn here with macOS metrics: checkbox toggles, radio groups,
// link and accessory-bar buttons, square-bordered fields, and the field date pickers.

struct PlatformStylesExample: View {
    @State private var notify = true
    @State private var sounds = false
    @State private var size = "Medium"
    @State private var date = Date(timeIntervalSince1970: 1_750_000_000)
    @State private var name = "Sam"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show notifications", isOn: $notify).toggleStyle(.checkbox)
            Toggle("Play sounds", isOn: $sounds).toggleStyle(.checkbox)
            Picker("Icon size:", selection: $size) {
                ForEach(["Small", "Medium", "Large"], id: \.self) { Text($0) }
            }
            .pickerStyle(.radioGroup)
            HStack(spacing: 12) {
                Button("Privacy Policy") {}.buttonStyle(.link)
                Button("All") {}.buttonStyle(.accessoryBar)
                Button("Recent", systemImage: "clock") {}.buttonStyle(.accessoryBarAction)
            }
            TextField("Name", text: $name).textFieldStyle(.squareBorder)
            DatePicker("Due", selection: $date).datePickerStyle(.field)
            DatePicker("Start", selection: $date, displayedComponents: .date).datePickerStyle(.stepperField)
            Spacer()
        }
        .padding()
    }
}

struct WatchListExample: View {
    var body: some View {
        List {
            Text("Carousel row")
            Text("Another row")
        }
        .listStyle(.carousel)
    }
}

#Preview("macOS styles") {
    PlatformStylesExample()
}

#Preview("watchOS list style") {
    WatchListExample()
}
