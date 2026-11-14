// MapKit's network services. Requests are built as on iOS, but there is no map service here, so
// they fail with `MKError.serverFailure` (apps then take their offline path, e.g. straight lines).

import CoreLocation
import Foundation
import SwiftUI
import UIKit

public struct MKError: Error, CustomNSError, Hashable, @unchecked Sendable {
    public enum Code: UInt, Sendable, Equatable {
        case unknown = 1, serverFailure, loadingThrottled, placemarkNotFound, directionsNotFound, decodingFailed
    }
    public let code: Code
    let message: String?
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        message = userInfo[NSLocalizedDescriptionKey] as? String
    }
    init(_ code: Code, message: String) { self.code = code; self.message = message }

    public static var errorDomain: String { MKErrorDomain }
    public var errorCode: Int { Int(code.rawValue) }
    public var errorUserInfo: [String: Any] { message.map { [NSLocalizedDescriptionKey: $0] } ?? [:] }
    public var localizedDescription: String { message ?? "The operation couldn’t be completed. (MKErrorDomain error \(code.rawValue).)" }
    public static func == (l: MKError, r: MKError) -> Bool { l.code == r.code }
    public func hash(into h: inout Hasher) { h.combine(code) }

    public static var unknown: Code { .unknown }
    public static var serverFailure: Code { .serverFailure }
    public static var loadingThrottled: Code { .loadingThrottled }
    public static var placemarkNotFound: Code { .placemarkNotFound }
    public static var directionsNotFound: Code { .directionsNotFound }
    public static var decodingFailed: Code { .decodingFailed }

    static func unavailable(_ service: String) -> MKError {
        MKError(.serverFailure, message: "\(service) is not available when rendering with swiftui-screenshot (no map services on Linux).")
    }
}

extension MKError.Code {
    /// `catch MKError.directionsNotFound { ... }`
    public static func ~= (code: MKError.Code, error: Error) -> Bool { (error as? MKError)?.code == code }
}

public let MKErrorDomain = "MKErrorDomain"

// MARK: - Directions

public struct MKDirectionsTransportType: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let automobile = MKDirectionsTransportType(rawValue: 1 << 0)
    public static let walking = MKDirectionsTransportType(rawValue: 1 << 1)
    public static let transit = MKDirectionsTransportType(rawValue: 1 << 2)
    public static let cycling = MKDirectionsTransportType(rawValue: 1 << 3)
    public static let any = MKDirectionsTransportType(rawValue: 0x0FFF_FFFF)
}

open class MKRoute: NSObject, @unchecked Sendable {
    public enum Preference: Int, Sendable { case any, avoid }
    open class Step: NSObject, @unchecked Sendable {
        public var polyline: MKPolyline { MKPolyline() }
        public var instructions: String { "" }
        public var notice: String? { nil }
        public var distance: CLLocationDistance { 0 }
        public var transportType: MKDirectionsTransportType { .automobile }
    }
    public var name: String { "" }
    public var advisoryNotices: [String] { [] }
    public var distance: CLLocationDistance { 0 }
    public var expectedTravelTime: TimeInterval { 0 }
    public var transportType: MKDirectionsTransportType { .automobile }
    public var polyline: MKPolyline { MKPolyline() }
    public var steps: [Step] { [] }
    public var hasTolls: Bool { false }
    public var hasHighways: Bool { false }
}

open class MKDirections: NSObject, @unchecked Sendable {
    open class Request: NSObject, @unchecked Sendable {
        public var source: MKMapItem?
        public var destination: MKMapItem?
        public var transportType: MKDirectionsTransportType = .any
        public var requestsAlternateRoutes = false
        public var departureDate: Date?
        public var arrivalDate: Date?
        public var tollPreference: MKRoute.Preference = .any
        public var highwayPreference: MKRoute.Preference = .any
        public override init() { super.init() }
        public init(contentsOf url: URL) { super.init() }
        open class func isDirectionsRequest(_ url: URL) -> Bool { false }
    }
    open class Response: NSObject, @unchecked Sendable {
        public var source: MKMapItem { MKMapItem() }
        public var destination: MKMapItem { MKMapItem() }
        public var routes: [MKRoute] { [] }
    }
    open class ETAResponse: NSObject, @unchecked Sendable {
        public var source: MKMapItem { MKMapItem() }
        public var destination: MKMapItem { MKMapItem() }
        public var expectedTravelTime: TimeInterval { 0 }
        public var distance: CLLocationDistance { 0 }
        public var expectedArrivalDate: Date { Date() }
        public var expectedDepartureDate: Date { Date() }
        public var transportType: MKDirectionsTransportType { .automobile }
    }
    public typealias DirectionsHandler = (Response?, Error?) -> Void
    public typealias ETAHandler = (ETAResponse?, Error?) -> Void

    public let request: Request
    public var isCalculating: Bool { false }
    public init(request: Request) { self.request = request; super.init() }

    open func calculate() async throws -> Response { throw MKError.unavailable("MKDirections") }
    open func calculate(completionHandler: @escaping DirectionsHandler) { completionHandler(nil, MKError.unavailable("MKDirections")) }
    open func calculateETA() async throws -> ETAResponse { throw MKError.unavailable("MKDirections") }
    open func calculateETA(completionHandler: @escaping ETAHandler) { completionHandler(nil, MKError.unavailable("MKDirections")) }
    open func cancel() {}
}

// MARK: - Local search

open class MKLocalSearch: NSObject, @unchecked Sendable {
    public struct ResultType: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let address = ResultType(rawValue: 1 << 0)
        public static let pointOfInterest = ResultType(rawValue: 1 << 1)
        public static let physicalFeature = ResultType(rawValue: 1 << 2)
    }
    open class Request: NSObject, @unchecked Sendable {
        public var naturalLanguageQuery: String?
        public var region = MKCoordinateRegion()
        public var resultTypes: ResultType = [.address, .pointOfInterest]
        public var pointOfInterestFilter: MKPointOfInterestFilter?
        public var addressFilter: MKAddressFilter?
        public var regionPriority: MKLocalSearchRegionPriority = .default
        public override init() { super.init() }
        public init(completion: MKLocalSearchCompletion) { naturalLanguageQuery = completion.title; super.init() }
        public init(naturalLanguageQuery: String) { self.naturalLanguageQuery = naturalLanguageQuery; super.init() }
        public init(naturalLanguageQuery: String, region: MKCoordinateRegion) {
            self.naturalLanguageQuery = naturalLanguageQuery
            self.region = region
            super.init()
        }
    }
    open class Response: NSObject, @unchecked Sendable {
        public var mapItems: [MKMapItem] { [] }
        public var boundingRegion: MKCoordinateRegion { MKCoordinateRegion() }
    }
    public typealias CompletionHandler = (Response?, Error?) -> Void

    public var isSearching: Bool { false }
    public init(request: Request) { super.init() }
    public init(request: MKLocalPointsOfInterestRequest) { super.init() }
    open func start() async throws -> Response { throw MKError.unavailable("MKLocalSearch") }
    open func start(completionHandler: @escaping CompletionHandler) { completionHandler(nil, MKError.unavailable("MKLocalSearch")) }
    open func cancel() {}
}

public enum MKLocalSearchRegionPriority: Int, Sendable { case `default`, required }

open class MKLocalPointsOfInterestRequest: NSObject, @unchecked Sendable {
    public static let maxRadius: CLLocationDistance = 2000
    public var pointOfInterestFilter: MKPointOfInterestFilter?
    public let coordinateRegion: MKCoordinateRegion
    public init(center coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) {
        coordinateRegion = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        super.init()
    }
    public init(coordinateRegion region: MKCoordinateRegion) { coordinateRegion = region; super.init() }
}

open class MKLocalSearchCompletion: NSObject, @unchecked Sendable {
    public let title: String
    public let subtitle: String
    public var titleHighlightRanges: [NSValue] { [] }
    public var subtitleHighlightRanges: [NSValue] { [] }
    init(title: String, subtitle: String) { self.title = title; self.subtitle = subtitle; super.init() }
}

public protocol MKLocalSearchCompleterDelegate: NSObjectProtocol {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter)
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error)
}
extension MKLocalSearchCompleterDelegate {
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {}
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

/// Inert: setting `queryFragment` produces no results and calls no delegate method.
open class MKLocalSearchCompleter: NSObject, @unchecked Sendable {
    public typealias ResultType = MKLocalSearchCompleterResultType
    public weak var delegate: MKLocalSearchCompleterDelegate?
    public var queryFragment = ""
    public var region = MKCoordinateRegion()
    public var regionPriority: MKLocalSearchRegionPriority = .default
    public var resultTypes: MKLocalSearchCompleterResultType = [.address, .pointOfInterest, .query]
    public var pointOfInterestFilter: MKPointOfInterestFilter?
    public var addressFilter: MKAddressFilter?
    public var results: [MKLocalSearchCompletion] { [] }
    public var isSearching: Bool { false }
    public override init() { super.init() }
    open func cancel() {}
}

public struct MKLocalSearchCompleterResultType: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let address = Self(rawValue: 1 << 0)
    public static let pointOfInterest = Self(rawValue: 1 << 1)
    public static let query = Self(rawValue: 1 << 2)
    public static let physicalFeature = Self(rawValue: 1 << 3)
}

// MARK: - Look Around

open class MKLookAroundScene: NSObject, @unchecked Sendable {}

/// Inert: `scene` is always `nil` (no imagery here).
open class MKLookAroundSceneRequest: NSObject, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let mapItem: MKMapItem?
    public var isLoading: Bool { false }
    public var isCancelled: Bool { false }
    public init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate; mapItem = nil; super.init() }
    public init(mapItem: MKMapItem) { coordinate = mapItem.mapCoordinate; self.mapItem = mapItem; super.init() }
    public var scene: MKLookAroundScene? { get async throws { nil } }
    open func getSceneWithCompletionHandler(_ completionHandler: @escaping (MKLookAroundScene?, Error?) -> Void) { completionHandler(nil, nil) }
    open func cancel() {}
}

open class MKLookAroundSnapshotter: NSObject, @unchecked Sendable {
    open class Options: NSObject, @unchecked Sendable {
        public var size = CGSize(width: 256, height: 256)
        public var pointOfInterestFilter: MKPointOfInterestFilter?
        public override init() { super.init() }
    }
    open class Snapshot: NSObject, @unchecked Sendable {
        public var image: UIImage { UIImage() }
    }
    public init(scene: MKLookAroundScene, options: Options) { super.init() }
    open var snapshot: Snapshot { get async throws { throw MKError.unavailable("Look Around") } }
    open func getSnapshotWithCompletionHandler(_ completionHandler: @escaping (Snapshot?, Error?) -> Void) {
        completionHandler(nil, MKError.unavailable("Look Around"))
    }
    open func cancel() {}
}

public enum MKLookAroundBadgePosition: Int, Sendable { case topLeading, topTrailing, bottomTrailing }
