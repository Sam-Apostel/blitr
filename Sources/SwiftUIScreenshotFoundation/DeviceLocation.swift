import Foundation

/// The device location a render runs at (`--location <lat>,<lon>`). CoreLocation reports it, with location
/// access granted; without the flag there is none and access is not determined, as on a fresh install.
public enum _DeviceLocation {
    public static func parse(_ raw: String) -> (latitude: Double, longitude: Double)? {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    /// The location given to the running render, if any.
    public static let current: (latitude: Double, longitude: Double)? = {
        let arguments = _RunnerArguments.all
        guard let index = arguments.firstIndex(of: "--location"), index + 1 < arguments.count else { return nil }
        return parse(arguments[index + 1])
    }()
}
