import SwiftUI

/// Tools that lean on frameworks the Linux renderer does not have. Nothing on the first screen refers
/// to this file, so the list and detail screens still render; rendering this one reports what is missing.
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Measure a trunk") { TrunkScannerView() }
                NavigationLink("Sunlight today") { SunlightView() }
            }
            .navigationTitle("Tools")
        }
    }
}

#Preview("Tools") {
    ToolsView()
}
