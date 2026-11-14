import SwiftUI
import SunCalc

/// Hours of sun on the orchard today. SunCalc is a remote package, which cannot be fetched here.
struct SunlightView: View {
    var body: some View {
        Text("\(SunCalc.daylightHours(latitude: 51.2, day: Season.year)) hours of sun")
    }
}
