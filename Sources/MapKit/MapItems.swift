// Map items, placemarks, point-of-interest categories, launch options and the distance formatter.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

open class MKPlacemark: CLPlacemark, MKAnnotation, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public var title: String? { name ?? formattedAddress }
    public var subtitle: String? { name == nil ? nil : formattedAddress }
    public var countryCode: String? { isoCountryCode }

    public init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
    public init(coordinate: CLLocationCoordinate2D, addressDictionary: [String: Any]?) {
        self.coordinate = coordinate
        let fields = (addressDictionary ?? [:]).compactMapValues { $0 as? String }
        super.init(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), fields: fields)
    }
    public override init(placemark: CLPlacemark) {
        coordinate = placemark.location?.coordinate ?? kCLLocationCoordinate2DInvalid
        super.init(placemark: placemark)
    }
    public required init?(coder: NSCoder) { return nil }

    private var formattedAddress: String? {
        let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, locality, administrativeArea, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

public struct MKPointOfInterestCategory: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let airport = Self("MKPOICategoryAirport")
    public static let amusementPark = Self("MKPOICategoryAmusementPark")
    public static let animalService = Self("MKPOICategoryAnimalService")
    public static let aquarium = Self("MKPOICategoryAquarium")
    public static let atm = Self("MKPOICategoryATM")
    public static let automotiveRepair = Self("MKPOICategoryAutomotiveRepair")
    public static let bakery = Self("MKPOICategoryBakery")
    public static let bank = Self("MKPOICategoryBank")
    public static let baseball = Self("MKPOICategoryBaseball")
    public static let basketball = Self("MKPOICategoryBasketball")
    public static let beach = Self("MKPOICategoryBeach")
    public static let beauty = Self("MKPOICategoryBeauty")
    public static let bowling = Self("MKPOICategoryBowling")
    public static let brewery = Self("MKPOICategoryBrewery")
    public static let cafe = Self("MKPOICategoryCafe")
    public static let campground = Self("MKPOICategoryCampground")
    public static let carRental = Self("MKPOICategoryCarRental")
    public static let castle = Self("MKPOICategoryCastle")
    public static let conventionCenter = Self("MKPOICategoryConventionCenter")
    public static let distillery = Self("MKPOICategoryDistillery")
    public static let evCharger = Self("MKPOICategoryEVCharger")
    public static let fairground = Self("MKPOICategoryFairground")
    public static let fireStation = Self("MKPOICategoryFireStation")
    public static let fishing = Self("MKPOICategoryFishing")
    public static let fitnessCenter = Self("MKPOICategoryFitnessCenter")
    public static let foodMarket = Self("MKPOICategoryFoodMarket")
    public static let fortress = Self("MKPOICategoryFortress")
    public static let gasStation = Self("MKPOICategoryGasStation")
    public static let golf = Self("MKPOICategoryGolf")
    public static let goKart = Self("MKPOICategoryGoKart")
    public static let hiking = Self("MKPOICategoryHiking")
    public static let hospital = Self("MKPOICategoryHospital")
    public static let hotel = Self("MKPOICategoryHotel")
    public static let kayaking = Self("MKPOICategoryKayaking")
    public static let landmark = Self("MKPOICategoryLandmark")
    public static let laundry = Self("MKPOICategoryLaundry")
    public static let library = Self("MKPOICategoryLibrary")
    public static let mailbox = Self("MKPOICategoryMailbox")
    public static let marina = Self("MKPOICategoryMarina")
    public static let miniGolf = Self("MKPOICategoryMiniGolf")
    public static let movieTheater = Self("MKPOICategoryMovieTheater")
    public static let museum = Self("MKPOICategoryMuseum")
    public static let musicVenue = Self("MKPOICategoryMusicVenue")
    public static let nationalMonument = Self("MKPOICategoryNationalMonument")
    public static let nationalPark = Self("MKPOICategoryNationalPark")
    public static let nightlife = Self("MKPOICategoryNightlife")
    public static let park = Self("MKPOICategoryPark")
    public static let parking = Self("MKPOICategoryParking")
    public static let pharmacy = Self("MKPOICategoryPharmacy")
    public static let planetarium = Self("MKPOICategoryPlanetarium")
    public static let police = Self("MKPOICategoryPolice")
    public static let postOffice = Self("MKPOICategoryPostOffice")
    public static let publicTransport = Self("MKPOICategoryPublicTransport")
    public static let restaurant = Self("MKPOICategoryRestaurant")
    public static let restroom = Self("MKPOICategoryRestroom")
    public static let rockClimbing = Self("MKPOICategoryRockClimbing")
    public static let rvPark = Self("MKPOICategoryRVPark")
    public static let school = Self("MKPOICategorySchool")
    public static let skatePark = Self("MKPOICategorySkatePark")
    public static let skating = Self("MKPOICategorySkating")
    public static let skiing = Self("MKPOICategorySkiing")
    public static let soccer = Self("MKPOICategorySoccer")
    public static let spa = Self("MKPOICategorySpa")
    public static let stadium = Self("MKPOICategoryStadium")
    public static let store = Self("MKPOICategoryStore")
    public static let surfing = Self("MKPOICategorySurfing")
    public static let swimming = Self("MKPOICategorySwimming")
    public static let tennis = Self("MKPOICategoryTennis")
    public static let theater = Self("MKPOICategoryTheater")
    public static let university = Self("MKPOICategoryUniversity")
    public static let volleyball = Self("MKPOICategoryVolleyball")
    public static let winery = Self("MKPOICategoryWinery")
    public static let zoo = Self("MKPOICategoryZoo")
}

open class MKPointOfInterestFilter: NSObject, @unchecked Sendable {
    let included: [MKPointOfInterestCategory]?
    let excluded: [MKPointOfInterestCategory]?
    public init(including categories: [MKPointOfInterestCategory]) { included = categories; excluded = nil; super.init() }
    public init(excluding categories: [MKPointOfInterestCategory]) { included = nil; excluded = categories; super.init() }
    public static let includingAll = MKPointOfInterestFilter(excluding: [])
    public static let excludingAll = MKPointOfInterestFilter(including: [])
    public func includes(_ category: MKPointOfInterestCategory) -> Bool {
        if let included { return included.contains(category) }
        return !(excluded ?? []).contains(category)
    }
    public func excludes(_ category: MKPointOfInterestCategory) -> Bool { !includes(category) }
}

/// iOS 18: which kinds of address an `MKLocalSearchCompleter` may suggest.
public struct MKAddressFilter: Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let country = Options(rawValue: 1 << 0)
        public static let administrativeArea = Options(rawValue: 1 << 1)
        public static let subAdministrativeArea = Options(rawValue: 1 << 2)
        public static let locality = Options(rawValue: 1 << 3)
        public static let subLocality = Options(rawValue: 1 << 4)
        public static let postalCode = Options(rawValue: 1 << 5)
    }
    let included: Options?
    let excluded: Options?
    public init(including options: Options) { included = options; excluded = nil }
    public init(excluding options: Options) { included = nil; excluded = options }
    public static let includingAll = MKAddressFilter(excluding: [])
    public static let excludingAll = MKAddressFilter(including: [])
    public func includes(_ options: Options) -> Bool { included.map { $0.isSuperset(of: options) } ?? excluded!.isDisjoint(with: options) }
    public func excludes(_ options: Options) -> Bool { !includes(options) }
}

// MARK: - MKMapItem

public let MKLaunchOptionsDirectionsModeKey = "MKLaunchOptionsDirectionsMode"
public let MKLaunchOptionsMapTypeKey = "MKLaunchOptionsMapType"
public let MKLaunchOptionsMapCenterKey = "MKLaunchOptionsMapCenter"
public let MKLaunchOptionsMapSpanKey = "MKLaunchOptionsMapSpan"
public let MKLaunchOptionsShowsTrafficKey = "MKLaunchOptionsShowsTraffic"
public let MKLaunchOptionsCameraKey = "MKLaunchOptionsCamera"
public let MKLaunchOptionsDirectionsModeDefault = "MKLaunchOptionsDirectionsModeDefault"
public let MKLaunchOptionsDirectionsModeDriving = "MKLaunchOptionsDirectionsModeDriving"
public let MKLaunchOptionsDirectionsModeWalking = "MKLaunchOptionsDirectionsModeWalking"
public let MKLaunchOptionsDirectionsModeTransit = "MKLaunchOptionsDirectionsModeTransit"
public let MKLaunchOptionsDirectionsModeCycling = "MKLaunchOptionsDirectionsModeCycling"

open class MKMapItem: NSObject, @unchecked Sendable {
    public let placemark: MKPlacemark
    public let isCurrentLocation: Bool
    public var name: String?
    public var phoneNumber: String?
    public var url: URL?
    public var timeZone: TimeZone?
    public var pointOfInterestCategory: MKPointOfInterestCategory?
    public var alternateIdentifiers: Set<Identifier> { [] }
    public var identifier: Identifier? { nil }

    public struct Identifier: Hashable, Sendable {
        public let rawValue: String
        public init?(rawValue: String) { self.rawValue = rawValue }
    }

    public override init() {
        placemark = MKPlacemark(coordinate: kCLLocationCoordinate2DInvalid)
        isCurrentLocation = false
        super.init()
    }
    public init(placemark: MKPlacemark) {
        self.placemark = placemark
        isCurrentLocation = false
        name = placemark.name
        super.init()
    }
    init(currentLocation: Void) {
        placemark = MKPlacemark(coordinate: kCLLocationCoordinate2DInvalid)
        isCurrentLocation = true
        super.init()
        name = "My Location"
    }
    /// The current location: it has no coordinate here, because there is no device position.
    open class func forCurrentLocation() -> MKMapItem { MKMapItem(currentLocation: ()) }

    /// No-op: there is no Maps app to hand over to. Returns `false`.
    @discardableResult
    open func openInMaps(launchOptions: [String: Any]? = nil) -> Bool { false }
    @discardableResult
    open func openInMaps(launchOptions: [String: Any]? = nil, from scene: AnyObject?) async -> Bool { false }
    open func openInMaps(launchOptions: [String: Any]? = nil, from scene: AnyObject?, completionHandler: ((Bool) -> Void)? = nil) {
        completionHandler?(false)
    }
    @discardableResult
    open class func openMaps(with mapItems: [MKMapItem], launchOptions: [String: Any]? = nil) -> Bool { false }
    @discardableResult
    open class func openMaps(with mapItems: [MKMapItem], launchOptions: [String: Any]? = nil, from scene: AnyObject?) async -> Bool { false }

    /// The coordinate this item stands for (internal helper).
    var mapCoordinate: CLLocationCoordinate2D { placemark.coordinate }
}

// MARK: - MKDistanceFormatter

open class MKDistanceFormatter: Formatter, @unchecked Sendable {
    public enum Units: UInt, Sendable { case `default`, metric, imperial, imperialWithYards }
    public enum DistanceUnitStyle: UInt, Sendable { case `default`, abbreviated, full }

    open var locale: Locale = .current
    open var units: Units = .default
    open var unitStyle: DistanceUnitStyle = .default

    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    private var usesMetric: Bool {
        switch units {
        case .metric: return true
        case .imperial, .imperialWithYards: return false
        case .default:
            let region = locale.region?.identifier ?? "US"
            return !["US", "LR", "MM", "GB"].contains(region)
        }
    }

    /// Distances rounded the way Maps shows them ("250 m", "1.2 km", "500 ft", "3.4 mi").
    open func string(fromDistance distance: CLLocationDistance) -> String {
        let full = unitStyle == .full
        func number(_ v: Double, decimals: Int) -> String {
            let f = NumberFormatter()
            f.locale = locale
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = decimals
            return f.string(from: NSNumber(value: v)) ?? String(v)
        }
        func unit(_ short: String, _ one: String, _ many: String, _ value: Double) -> String {
            full ? (value == 1 ? one : many) : short
        }
        if usesMetric {
            if distance < 1000 {
                let step: Double = distance < 100 ? 5 : distance < 500 ? 10 : 50
                let m = (distance / step).rounded() * step
                if m >= 1000 { return "\(number(1, decimals: 0)) \(unit("km", "kilometer", "kilometers", 1))" }
                return "\(number(m, decimals: 0)) \(unit("m", "meter", "meters", m))"
            }
            let km = distance / 1000
            let decimals = km < 10 ? 1 : 0
            let rounded = decimals == 1 ? (km * 10).rounded() / 10 : km.rounded()
            return "\(number(rounded, decimals: decimals)) \(unit("km", "kilometer", "kilometers", rounded))"
        }
        let feet = distance / 0.3048
        let miles = distance / 1609.344
        if miles < 0.1 {
            if units == .imperialWithYards {
                let yd = (distance / 0.9144 / 10).rounded() * 10
                return "\(number(yd, decimals: 0)) \(unit("yd", "yard", "yards", yd))"
            }
            let ft = (feet / 10).rounded() * 10
            return "\(number(ft, decimals: 0)) \(unit("ft", "foot", "feet", ft))"
        }
        let decimals = miles < 10 ? 1 : 0
        let rounded = decimals == 1 ? (miles * 10).rounded() / 10 : miles.rounded()
        return "\(number(rounded, decimals: decimals)) \(unit("mi", "mile", "miles", rounded))"
    }

    open func distance(from distance: String) -> CLLocationDistance {
        let scanner = distance.trimmingCharacters(in: .whitespaces)
        let digits = scanner.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard let value = Double(digits.replacingOccurrences(of: ",", with: ".")) else { return 0 }
        let unit = scanner.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
        switch unit {
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": return value * 1000
        case "mi", "mile", "miles": return value * 1609.344
        case "ft", "foot", "feet": return value * 0.3048
        case "yd", "yard", "yards": return value * 0.9144
        default: return value
        }
    }

    open override func string(for obj: Any?) -> String? {
        if let d = obj as? Double { return string(fromDistance: d) }
        if let n = obj as? NSNumber { return string(fromDistance: n.doubleValue) }
        return nil
    }
}
