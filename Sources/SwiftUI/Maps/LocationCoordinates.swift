// CoreLocation for Linux: the value types and geodesy are real; the services (location updates,
// geocoding) are inert, because a screenshot has no device position and no network services.

import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationDirection = Double
public typealias CLLocationDirectionAccuracy = Double
public typealias CLLocationSpeed = Double
public typealias CLLocationSpeedAccuracy = Double
public typealias CLLocationCourseAccuracy = Double
public typealias CLHeadingComponentValue = Double

/// A latitude and longitude in degrees (WGS 84).
///
/// Like Apple's, this has no `Equatable`, `Hashable` or `Codable` conformance: apps that need one
/// add it themselves, and a second conformance here would break them.
public struct CLLocationCoordinate2D: @unchecked Sendable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init() { latitude = 0; longitude = 0 }
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public let kCLLocationCoordinate2DInvalid = CLLocationCoordinate2D(latitude: -180, longitude: -180)

public func CLLocationCoordinate2DIsValid(_ coord: CLLocationCoordinate2D) -> Bool {
    coord.latitude.isFinite && coord.longitude.isFinite
        && (-90...90).contains(coord.latitude) && (-180...180).contains(coord.longitude)
}

public func CLLocationCoordinate2DMake(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

public let kCLLocationAccuracyBestForNavigation: CLLocationAccuracy = -2
public let kCLLocationAccuracyBest: CLLocationAccuracy = -1
public let kCLLocationAccuracyNearestTenMeters: CLLocationAccuracy = 10
public let kCLLocationAccuracyHundredMeters: CLLocationAccuracy = 100
public let kCLLocationAccuracyKilometer: CLLocationAccuracy = 1000
public let kCLLocationAccuracyThreeKilometers: CLLocationAccuracy = 3000
public let kCLLocationAccuracyReduced: CLLocationAccuracy = 3000
public let kCLDistanceFilterNone: CLLocationDistance = -1
public let kCLHeadingFilterNone: CLLocationDegrees = -1
public let CLLocationDistanceMax: CLLocationDistance = .greatestFiniteMagnitude
public let CLTimeIntervalMax: TimeInterval = .greatestFiniteMagnitude

// MARK: - Geodesy

/// WGS 84 ellipsoid distances (Vincenty's inverse formula), with a great-circle fallback for the
/// nearly antipodal pairs where Vincenty does not converge.
enum Geodesy {
    static let a = 6_378_137.0
    static let f = 1 / 298.257223563
    static let b = a * (1 - f)
    static let meanRadius = 6_371_008.8

    static func distance(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D) -> CLLocationDistance {
        let rad = Double.pi / 180
        let L = (q.longitude - p.longitude) * rad
        let U1 = atan((1 - f) * tan(p.latitude * rad))
        let U2 = atan((1 - f) * tan(q.latitude * rad))
        let sinU1 = sin(U1), cosU1 = cos(U1), sinU2 = sin(U2), cosU2 = cos(U2)
        var lambda = L
        for _ in 0..<200 {
            let sinL = sin(lambda), cosL = cos(lambda)
            let sinSigma = sqrt(pow(cosU2 * sinL, 2) + pow(cosU1 * sinU2 - sinU1 * cosU2 * cosL, 2))
            if sinSigma == 0 { return 0 }
            let cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosL
            let sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinL / sinSigma
            let cos2Alpha = 1 - sinAlpha * sinAlpha
            let cos2SigmaM = cos2Alpha != 0 ? cosSigma - 2 * sinU1 * sinU2 / cos2Alpha : 0
            let C = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
            let previous = lambda
            lambda = L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - previous) < 1e-12 {
                let u2 = cos2Alpha * (a * a - b * b) / (b * b)
                let A = 1 + u2 / 16384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
                let B = u2 / 1024 * (256 + u2 * (-128 + u2 * (74 - 47 * u2)))
                let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                    - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
                return b * A * (sigma - deltaSigma)
            }
        }
        return haversine(p, q)
    }

    static func haversine(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D) -> CLLocationDistance {
        let rad = Double.pi / 180
        let dLat = (q.latitude - p.latitude) * rad, dLon = (q.longitude - p.longitude) * rad
        let h = pow(sin(dLat / 2), 2) + cos(p.latitude * rad) * cos(q.latitude * rad) * pow(sin(dLon / 2), 2)
        return 2 * meanRadius * asin(min(1, sqrt(h)))
    }

    /// The point `distance` metres from `start` along the initial `bearing` (degrees), on a sphere.
    static func destination(from start: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let rad = Double.pi / 180
        let delta = distance / meanRadius, theta = bearing * rad
        let phi1 = start.latitude * rad, lambda1 = start.longitude * rad
        let phi2 = asin(sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta))
        let lambda2 = lambda1 + atan2(sin(theta) * sin(delta) * cos(phi1), cos(delta) - sin(phi1) * sin(phi2))
        var lon = lambda2 / rad
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: phi2 / rad, longitude: lon)
    }

    /// Points along the great circle from `p` to `q` (both included), `steps` segments.
    static func greatCircle(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D, steps: Int) -> [CLLocationCoordinate2D] {
        let rad = Double.pi / 180
        let phi1 = p.latitude * rad, l1 = p.longitude * rad, phi2 = q.latitude * rad, l2 = q.longitude * rad
        let d = 2 * asin(min(1, sqrt(pow(sin((phi2 - phi1) / 2), 2) + cos(phi1) * cos(phi2) * pow(sin((l2 - l1) / 2), 2))))
        guard d > 1e-9, steps > 1 else { return [p, q] }
        var out: [CLLocationCoordinate2D] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let A = sin((1 - t) * d) / sin(d), B = sin(t * d) / sin(d)
            let x = A * cos(phi1) * cos(l1) + B * cos(phi2) * cos(l2)
            let y = A * cos(phi1) * sin(l1) + B * cos(phi2) * sin(l2)
            let z = A * sin(phi1) + B * sin(phi2)
            out.append(CLLocationCoordinate2D(latitude: atan2(z, sqrt(x * x + y * y)) / rad, longitude: atan2(y, x) / rad))
        }
        return out
    }
}

// MARK: - CLLocation

public struct CLFloor: Sendable {
    public let level: Int
}

open class CLLocation: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let altitude: CLLocationDistance
    public let ellipsoidalAltitude: CLLocationDistance
    public let horizontalAccuracy: CLLocationAccuracy
    public let verticalAccuracy: CLLocationAccuracy
    public let course: CLLocationDirection
    public let courseAccuracy: CLLocationDirectionAccuracy
    public let speed: CLLocationSpeed
    public let speedAccuracy: CLLocationSpeedAccuracy
    public let timestamp: Date
    public var floor: CLFloor? { nil }
    public var sourceInformation: CLLocationSourceInformation? { nil }

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        altitude = 0; ellipsoidalAltitude = 0; horizontalAccuracy = 0; verticalAccuracy = -1
        course = -1; courseAccuracy = -1; speed = -1; speedAccuracy = -1; timestamp = Date()
        super.init()
    }
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                verticalAccuracy vAccuracy: CLLocationAccuracy, timestamp: Date) {
        self.coordinate = coordinate; self.altitude = altitude; ellipsoidalAltitude = altitude
        horizontalAccuracy = hAccuracy; verticalAccuracy = vAccuracy
        course = -1; courseAccuracy = -1; speed = -1; speedAccuracy = -1; self.timestamp = timestamp
        super.init()
    }
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, speed: CLLocationSpeed, timestamp: Date) {
        self.coordinate = coordinate; self.altitude = altitude; ellipsoidalAltitude = altitude
        horizontalAccuracy = hAccuracy; verticalAccuracy = vAccuracy
        self.course = course; courseAccuracy = -1; self.speed = speed; speedAccuracy = -1; self.timestamp = timestamp
        super.init()
    }
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, courseAccuracy: CLLocationDirectionAccuracy,
                speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date) {
        self.coordinate = coordinate; self.altitude = altitude; ellipsoidalAltitude = altitude
        horizontalAccuracy = hAccuracy; verticalAccuracy = vAccuracy
        self.course = course; self.courseAccuracy = courseAccuracy; self.speed = speed; self.speedAccuracy = speedAccuracy
        self.timestamp = timestamp
        super.init()
    }

    public static var supportsSecureCoding: Bool { true }
    public required init?(coder: NSCoder) { return nil }
    public func encode(with coder: NSCoder) {}
    public func copy(with zone: NSZone? = nil) -> Any { self }

    /// Distance along the WGS 84 ellipsoid, in metres.
    public func distance(from location: CLLocation) -> CLLocationDistance {
        Geodesy.distance(coordinate, location.coordinate)
    }

    open override var description: String {
        String(format: "<%+.8f,%+.8f> +/- %.2fm (speed %.2f mps / course %.2f)", coordinate.latitude, coordinate.longitude,
               horizontalAccuracy, speed, course)
    }
}

open class CLLocationSourceInformation: NSObject, @unchecked Sendable {
    public let isSimulatedBySoftware: Bool
    public let isProducedByAccessory: Bool
    public init(softwareSimulationState isSoftware: Bool, andExternalAccessoryState isAccessory: Bool) {
        isSimulatedBySoftware = isSoftware
        isProducedByAccessory = isAccessory
        super.init()
    }
}

// MARK: - Heading and regions

open class CLHeading: NSObject, @unchecked Sendable {
    public let magneticHeading: CLLocationDirection
    public let trueHeading: CLLocationDirection
    public let headingAccuracy: CLLocationDirection
    public let x: CLHeadingComponentValue
    public let y: CLHeadingComponentValue
    public let z: CLHeadingComponentValue
    public let timestamp: Date
    init(magneticHeading: CLLocationDirection, trueHeading: CLLocationDirection) {
        self.magneticHeading = magneticHeading; self.trueHeading = trueHeading
        headingAccuracy = -1; x = 0; y = 0; z = 0; timestamp = Date()
        super.init()
    }
}

public enum CLRegionState: Int, Sendable { case unknown, inside, outside }
public enum CLProximity: Int, Sendable { case unknown, immediate, near, far }

open class CLRegion: NSObject, @unchecked Sendable {
    public let identifier: String
    public var notifyOnEntry = true
    public var notifyOnExit = true
    init(identifier: String) { self.identifier = identifier; super.init() }
}

open class CLCircularRegion: CLRegion, @unchecked Sendable {
    public let center: CLLocationCoordinate2D
    public let radius: CLLocationDistance
    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        self.center = center
        self.radius = radius
        super.init(identifier: identifier)
    }
    public func contains(_ coordinate: CLLocationCoordinate2D) -> Bool { Geodesy.distance(center, coordinate) <= radius }
}

open class CLBeaconRegion: CLRegion, @unchecked Sendable {
    public let uuid: UUID
    public let major: NSNumber?
    public let minor: NSNumber?
    public var notifyEntryStateOnDisplay = false
    public init(uuid: UUID, identifier: String) { self.uuid = uuid; major = nil; minor = nil; super.init(identifier: identifier) }
    public init(uuid: UUID, major: UInt16, identifier: String) {
        self.uuid = uuid; self.major = NSNumber(value: major); minor = nil; super.init(identifier: identifier)
    }
    public init(uuid: UUID, major: UInt16, minor: UInt16, identifier: String) {
        self.uuid = uuid; self.major = NSNumber(value: major); self.minor = NSNumber(value: minor); super.init(identifier: identifier)
    }
}
