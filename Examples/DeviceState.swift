// Formats and location that follow the device: render with --locale, --location and --time-zone to change them.
import SwiftUI
import CoreLocation

final class DeviceLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var text = "No location"
    let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse { m.requestLocation() } else { text = "Location: not determined" }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let c = locations.first?.coordinate { text = String(format: "%.4f, %.4f", c.latitude, c.longitude) }
    }
}
struct DeviceStateView: View {
    @StateObject var place = DeviceLocationModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(1234.5, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            Text(Date(timeIntervalSince1970: 1_780_000_000), format: .dateTime.weekday(.wide).day().month(.wide))
            Text(place.text)
        }.padding()
    }
}
#Preview("Device state") { DeviceStateView() }
