import SwiftUI
import OrchardKit

@main
struct OrchardTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVBoardView(state: SampleOrchard.state)
        }
    }
}
