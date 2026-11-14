// Location services. There is no device position here: managers stay `.notDetermined`, never
// deliver updates, and geocoding throws `CLError.network`.

import Foundation

public enum CLAuthorizationStatus: Int32, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorizedAlways = 3
    case authorizedWhenInUse = 4
    @available(*, deprecated, renamed: "authorizedAlways")
    public static var authorized: CLAuthorizationStatus { .authorizedAlways }
}

public enum CLAccuracyAuthorization: Int, Sendable { case fullAccuracy = 0, reducedAccuracy = 1 }

public enum CLActivityType: Int, Sendable {
    case other = 1, automotiveNavigation, fitness, otherNavigation, airborne
}

public enum CLDeviceOrientation: Int32, Sendable {
    case unknown = 0, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
}

// MARK: - Errors

/// CoreLocation's error, matchable like Apple's: `catch CLError.denied`, `error as? CLError`, `.code`.
public struct CLError: Error, CustomNSError, Hashable, @unchecked Sendable {
    public enum Code: Int, Sendable, Equatable {
        case locationUnknown = 0, denied, network, headingFailure, regionMonitoringDenied, regionMonitoringFailure,
             regionMonitoringSetupDelayed, regionMonitoringResponseDelayed, geocodeFoundNoResult, geocodeFoundPartialResult,
             geocodeCanceled, deferredFailed, deferredNotUpdatingLocation, deferredAccuracyTooLow, deferredDistanceFiltered,
             deferredCanceled, rangingUnavailable, rangingFailure, promptDeclined, historicalLocationError
    }
    public let code: Code
    let message: String?
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.message = userInfo[NSLocalizedDescriptionKey] as? String
    }
    init(_ code: Code, message: String) { self.code = code; self.message = message }

    public static var errorDomain: String { kCLErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { message.map { [NSLocalizedDescriptionKey: $0] } ?? [:] }
    public var localizedDescription: String { message ?? "The operation couldn’t be completed. (kCLErrorDomain error \(code.rawValue).)" }
    public static func == (l: CLError, r: CLError) -> Bool { l.code == r.code }
    public func hash(into h: inout Hasher) { h.combine(code) }

    public static var locationUnknown: Code { .locationUnknown }
    public static var denied: Code { .denied }
    public static var network: Code { .network }
    public static var headingFailure: Code { .headingFailure }
    public static var regionMonitoringDenied: Code { .regionMonitoringDenied }
    public static var regionMonitoringFailure: Code { .regionMonitoringFailure }
    public static var geocodeFoundNoResult: Code { .geocodeFoundNoResult }
    public static var geocodeFoundPartialResult: Code { .geocodeFoundPartialResult }
    public static var geocodeCanceled: Code { .geocodeCanceled }
    public static var promptDeclined: Code { .promptDeclined }
}

extension CLError.Code {
    /// `catch CLError.denied { ... }`
    public static func ~= (code: CLError.Code, error: Error) -> Bool { (error as? CLError)?.code == code }
}

public let kCLErrorDomain = "kCLErrorDomain"

// MARK: - CLLocationManager

public protocol CLLocationManagerDelegate: NSObjectProtocol {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading)
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion)
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error)
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion)
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager)
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit)
}

// Apple's delegate methods are all optional; here they have empty defaults.
extension CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {}
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {}
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {}
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {}
}

open class CLVisit: NSObject, @unchecked Sendable {
    public var arrivalDate: Date { .distantPast }
    public var departureDate: Date { .distantFuture }
    public var coordinate: CLLocationCoordinate2D { kCLLocationCoordinate2DInvalid }
    public var horizontalAccuracy: CLLocationAccuracy { -1 }
}

/// Inert: authorization stays `.notDetermined`, requests are ignored and no update is delivered.
open class CLLocationManager: NSObject, @unchecked Sendable {
    public weak var delegate: CLLocationManagerDelegate?
    public var authorizationStatus: CLAuthorizationStatus { .notDetermined }
    public var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
    public var isAuthorizedForWidgetUpdates: Bool { false }
    public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    public var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    public var headingFilter: CLLocationDegrees = 1
    public var headingOrientation: CLDeviceOrientation = .portrait
    public var activityType: CLActivityType = .other
    public var pausesLocationUpdatesAutomatically = true
    public var allowsBackgroundLocationUpdates = false
    public var showsBackgroundLocationIndicator = false
    public var location: CLLocation? { nil }
    public var heading: CLHeading? { nil }
    public var maximumRegionMonitoringDistance: CLLocationDistance { 200_000 }
    public var monitoredRegions: Set<CLRegion> { [] }
    public var rangedRegions: Set<CLRegion> { [] }

    public override init() { super.init() }

    open class func authorizationStatus() -> CLAuthorizationStatus { .notDetermined }
    open class func locationServicesEnabled() -> Bool { false }
    open class func headingAvailable() -> Bool { false }
    open class func significantLocationChangeMonitoringAvailable() -> Bool { false }
    open class func isMonitoringAvailable(for regionClass: AnyClass) -> Bool { false }
    open class func isRangingAvailable() -> Bool { false }
    open class func deferredLocationUpdatesAvailable() -> Bool { false }

    open func requestWhenInUseAuthorization() {}
    open func requestAlwaysAuthorization() {}
    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String, completion: ((Error?) -> Void)? = nil) {}
    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) async throws {}
    open func requestLocation() {}
    open func startUpdatingLocation() {}
    open func stopUpdatingLocation() {}
    open func startUpdatingHeading() {}
    open func stopUpdatingHeading() {}
    open func dismissHeadingCalibrationDisplay() {}
    open func startMonitoringSignificantLocationChanges() {}
    open func stopMonitoringSignificantLocationChanges() {}
    open func startMonitoringVisits() {}
    open func stopMonitoringVisits() {}
    open func startMonitoring(for region: CLRegion) {}
    open func stopMonitoring(for region: CLRegion) {}
    open func requestState(for region: CLRegion) {}
    open func startMonitoringLocationPushes(completion: ((Data?, Error?) -> Void)? = nil) {}
    open func stopMonitoringLocationPushes() {}
}

// MARK: - iOS 17 live updates and service sessions

/// `for try await update in CLLocationUpdate.liveUpdates()` ends at once: there is no position to report.
public struct CLLocationUpdate: Sendable {
    public var location: CLLocation? { nil }
    public var isStationary: Bool { false }
    public var authorizationDenied: Bool { false }
    public var authorizationDeniedGlobally: Bool { false }
    public var authorizationRestricted: Bool { false }
    public var authorizationRequestInProgress: Bool { false }
    public var insufficientlyInUse: Bool { false }
    public var locationUnavailable: Bool { true }
    public var accuracyLimited: Bool { false }
    public var serviceSessionRequired: Bool { false }
    public var stationary: Bool { false }

    public struct LiveConfiguration: Sendable {
        public static let `default` = LiveConfiguration()
        public static let automotiveNavigation = LiveConfiguration()
        public static let otherNavigation = LiveConfiguration()
        public static let fitness = LiveConfiguration()
        public static let airborne = LiveConfiguration()
    }

    public struct Updates: AsyncSequence, Sendable {
        public typealias Element = CLLocationUpdate
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> CLLocationUpdate? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    public static func liveUpdates(_ configuration: LiveConfiguration = .default) -> Updates { Updates() }
}

public final class CLServiceSession: @unchecked Sendable {
    public enum AuthorizationRequirement: Sendable { case none, whenInUse, always }
    public init(authorization: AuthorizationRequirement) {}
    public init(authorization: AuthorizationRequirement, fullAccuracyPurposeKey: String) {}
    public func invalidate() {}
}

// MARK: - Geocoding

open class CLPlacemark: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public internal(set) var location: CLLocation?
    public internal(set) var region: CLRegion?
    public internal(set) var timeZone: TimeZone?
    public internal(set) var name: String?
    public internal(set) var thoroughfare: String?
    public internal(set) var subThoroughfare: String?
    public internal(set) var locality: String?
    public internal(set) var subLocality: String?
    public internal(set) var administrativeArea: String?
    public internal(set) var subAdministrativeArea: String?
    public internal(set) var postalCode: String?
    public internal(set) var isoCountryCode: String?
    public internal(set) var country: String?
    public internal(set) var inlandWater: String?
    public internal(set) var ocean: String?
    public internal(set) var areasOfInterest: [String]?

    public init(placemark: CLPlacemark) {
        super.init()
        copyFields(from: placemark)
    }
    package init(location: CLLocation?, name: String? = nil, fields: [String: String] = [:]) {
        self.location = location
        self.name = name
        super.init()
        thoroughfare = fields["Street"]
        locality = fields["City"]
        administrativeArea = fields["State"]
        subAdministrativeArea = fields["SubAdministrativeArea"]
        postalCode = fields["ZIP"]
        country = fields["Country"]
        isoCountryCode = fields["CountryCode"]
        subLocality = fields["SubLocality"]
        subThoroughfare = fields["SubThoroughfare"]
    }
    private func copyFields(from p: CLPlacemark) {
        location = p.location; region = p.region; timeZone = p.timeZone; name = p.name
        thoroughfare = p.thoroughfare; subThoroughfare = p.subThoroughfare; locality = p.locality; subLocality = p.subLocality
        administrativeArea = p.administrativeArea; subAdministrativeArea = p.subAdministrativeArea; postalCode = p.postalCode
        isoCountryCode = p.isoCountryCode; country = p.country; inlandWater = p.inlandWater; ocean = p.ocean
        areasOfInterest = p.areasOfInterest
    }
    public static var supportsSecureCoding: Bool { true }
    public required init?(coder: NSCoder) { super.init() }
    public func encode(with coder: NSCoder) {}
    public func copy(with zone: NSZone? = nil) -> Any { self }
}

/// Inert: every request fails with `CLError.network`, as it does on a device with no connection.
open class CLGeocoder: NSObject, @unchecked Sendable {
    public typealias CLGeocodeCompletionHandler = ([CLPlacemark]?, Error?) -> Void
    public var isGeocoding: Bool { false }
    public override init() { super.init() }

    static var unavailable: CLError { CLError(.network, message: "Geocoding is not available when rendering with swiftui-screenshot (no network services).") }

    open func reverseGeocodeLocation(_ location: CLLocation, completionHandler: @escaping CLGeocodeCompletionHandler) {
        completionHandler(nil, Self.unavailable)
    }
    open func reverseGeocodeLocation(_ location: CLLocation, preferredLocale locale: Locale?, completionHandler: @escaping CLGeocodeCompletionHandler) {
        completionHandler(nil, Self.unavailable)
    }
    open func geocodeAddressString(_ addressString: String, completionHandler: @escaping CLGeocodeCompletionHandler) {
        completionHandler(nil, Self.unavailable)
    }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, completionHandler: @escaping CLGeocodeCompletionHandler) {
        completionHandler(nil, Self.unavailable)
    }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, preferredLocale locale: Locale?,
                                   completionHandler: @escaping CLGeocodeCompletionHandler) {
        completionHandler(nil, Self.unavailable)
    }
    open func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] { throw Self.unavailable }
    open func reverseGeocodeLocation(_ location: CLLocation, preferredLocale locale: Locale?) async throws -> [CLPlacemark] { throw Self.unavailable }
    open func geocodeAddressString(_ addressString: String) async throws -> [CLPlacemark] { throw Self.unavailable }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?) async throws -> [CLPlacemark] { throw Self.unavailable }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, preferredLocale locale: Locale?) async throws -> [CLPlacemark] {
        throw Self.unavailable
    }
    open func cancelGeocode() {}
}
