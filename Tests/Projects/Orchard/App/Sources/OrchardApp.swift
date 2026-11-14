import SwiftUI
import OrchardKit

@main
struct OrchardApp: App {
    @StateObject private var store = OrchardStore(state: SampleOrchard.state)

    var body: some Scene {
        WindowGroup {
            HarvestListView()
                .environmentObject(store)
        }
    }
}
