import SwiftUI
import ARKit

/// Measures a trunk's girth with the camera. ARKit is not available to the Linux renderer; this file
/// exists so the fixture has one screen that cannot compile there.
struct TrunkScannerView: View {
    @State private var girth: Measurement<UnitLength>?

    var body: some View {
        VStack {
            if ARWorldTrackingConfiguration.isSupported {
                Text("Walk around the trunk")
            }
            if let girth {
                Text(girth.formatted())
            }
        }
        .onAppear {
            let session = ARSession()
            session.run(ARWorldTrackingConfiguration())
        }
    }
}
