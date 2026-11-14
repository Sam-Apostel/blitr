import SwiftUI

// A Form with mixed content plus per-row customisation: backgrounds, insets, hidden
// separators, prominent headers, badges and row spacing.

#Preview {
    Form {
        Section {
            Text("Custom background")
                .listRowBackground(Color.yellow.opacity(0.3))
            Text("Custom insets")
                .listRowInsets(EdgeInsets(top: 0, leading: 60, bottom: 0, trailing: 0))
            Text("No separator below")
                .listRowSeparator(.hidden)
            Text("Tinted separator")
                .listRowSeparatorTint(.red)
            Text("Last row")
        } header: {
            Text("Rows")
        }
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("18.1").foregroundStyle(.secondary)
            }
            Text("Inbox").badge(12)
            VStack(alignment: .leading, spacing: 4) {
                Text("Two-line row").font(.headline)
                Text("A subtitle in secondary color that wraps onto a second line when long")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Prominent")
        } footer: {
            Text("Footers are 13pt secondary text.")
        }
        .headerProminence(.increased)
        Section {
            Color.blue.frame(height: 80)
                .listRowInsets(EdgeInsets())
        }
    }
}
