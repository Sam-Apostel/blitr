import SwiftUI

struct InputsDemo: View {
    @State private var flavor = 1
    @State private var seg = "Week"
    @State private var name = ""
    @State private var email = "sam@example.com"
    @State private var password = "hunter2"
    @State private var notes = "Some multi-line notes\nin a text editor."
    @State private var expanded = true
    @State private var color = Color.orange
    @State private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Flavor", selection: $flavor) {
                Text("Chocolate").tag(0)
                Text("Vanilla").tag(1)
            }
            Picker("Range", selection: $seg) {
                ForEach(["Day", "Week", "Month", "Year"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            Picker("Flavor", selection: $flavor) {
                Text("Chocolate").tag(0)
                Text("Vanilla").tag(1)
            }
            .pickerStyle(.navigationLink)
            Picker("Inline", selection: $flavor) {
                Text("Chocolate").tag(0)
                Text("Vanilla").tag(1)
            }
            .pickerStyle(.inline)
            TextField("Name", text: $name)
            TextField("Email", text: $email).textFieldStyle(.roundedBorder)
            TextField("Placeholder", text: $name).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            TextEditor(text: $notes).frame(height: 70)
            DatePicker("Date", selection: $date)
            DatePicker("Only date", selection: $date, displayedComponents: .date)
            ColorPicker("Accent", selection: $color)
            DisclosureGroup("Details", isExpanded: $expanded) {
                Text("Hidden content")
            }
            DisclosureGroup("Collapsed") { Text("Not shown") }
            GroupBox("Storage") {
                Text("42 GB of 128 GB used")
            }
            ControlGroup {
                Button("Cut") {}
                Button("Copy") {}
                Button("Paste") {}
            }
        }
        .padding(20)
    }
}

#Preview { InputsDemo() }
