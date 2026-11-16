import SwiftUI
import MapKit
import CoreLocation

// Checks of the MapKit / CoreLocation shims. Rendering this file runs them: a failed check stops
// the render with a message; a passing run shows the list of checks.
//
//   blitr render Tests/Maps/MapKitChecks.swift --open-fonts

private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

@MainActor
private func runChecks() -> [String] {
    var passed: [String] = []
    func check(_ name: String, _ ok: Bool) {
        precondition(ok, "MapKit check failed: \(name)")
        passed.append(name)
    }

    // Mercator map points (Apple's world is 2^28 points square).
    check("world size", MKMapSize.world.width == 268_435_456 && MKMapRect.world.height == 268_435_456)
    let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 0, longitude: 0))
    check("0,0 is the world's center", origin.x == 134_217_728 && close(origin.y, 134_217_728, 1e-6))
    let cities: [(String, Double, Double, Double, Double)] = [
        ("London", 51.5074, -0.1278, 134_122_433.413, 89_261_640.295),
        ("Tokyo", 35.6762, 139.6503, 238_348_539.003, 105_708_601.832),
        ("Sydney", -33.8688, 151.2093, 246_967_554.103, 161_086_037.162),
    ]
    for (name, lat, lon, x, y) in cities {
        let p = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        check("MKMapPoint(\(name))", close(p.x, x, 0.01) && close(p.y, y, 0.01))
        let back = p.coordinate
        check("round trip \(name)", close(back.latitude, lat, 1e-9) && close(back.longitude, lon, 1e-9))
    }
    check("metres per map point at the equator", close(MKMetersPerMapPointAtLatitude(0), 0.149291, 1e-6))

    // Geodesy: Vincenty's published test line (Flinders Peak to Buninyong, 54 972.271 m).
    let flinders = CLLocation(latitude: -(37 + 57 / 60.0 + 3.7203 / 3600), longitude: 144 + 25 / 60.0 + 29.5244 / 3600)
    let buninyong = CLLocation(latitude: -(37 + 39 / 60.0 + 10.1561 / 3600), longitude: 143 + 55 / 60.0 + 35.3839 / 3600)
    check("CLLocation.distance (Vincenty)", close(flinders.distance(from: buninyong), 54_972.271, 0.01))
    check("coordinate validity", CLLocationCoordinate2DIsValid(flinders.coordinate) && !CLLocationCoordinate2DIsValid(kCLLocationCoordinate2DInvalid))

    // Regions and rects.
    let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45, longitude: 10), latitudinalMeters: 10_000, longitudinalMeters: 10_000)
    check("region from metres", close(region.span.latitudeDelta, 0.0901, 0.0005) && close(region.span.longitudeDelta, 0.1270, 0.0005))
    let nw = MKMapPoint(CLLocationCoordinate2D(latitude: 45 + region.span.latitudeDelta / 2, longitude: 10 - region.span.longitudeDelta / 2))
    let se = MKMapPoint(CLLocationCoordinate2D(latitude: 45 - region.span.latitudeDelta / 2, longitude: 10 + region.span.longitudeDelta / 2))
    let back = MKCoordinateRegion(MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y))
    check("region -> rect -> region", close(back.center.latitude, 45, 1e-3) && close(back.span.longitudeDelta, region.span.longitudeDelta, 1e-9))
    let r = MKMapRect(x: 0, y: 0, width: 10, height: 10)
    check("rect union / intersection", r.union(MKMapRect(x: 20, y: 0, width: 5, height: 5)).width == 25
        && r.intersection(MKMapRect(x: 5, y: 5, width: 10, height: 10)).width == 5 && MKMapRect.null.isNull)

    let geodesic = MKGeodesicPolyline(coordinates: [CLLocationCoordinate2D(latitude: 51.47, longitude: -0.45),
                                                    CLLocationCoordinate2D(latitude: 40.64, longitude: -73.78)], count: 2)
    check("geodesic polyline is densified", geodesic.pointCount > 50)
    let formatter = MKDistanceFormatter()
    formatter.units = .metric
    formatter.unitStyle = .abbreviated
    check("distance formatter", formatter.string(fromDistance: 1234) == "1.2 km" && formatter.string(fromDistance: 240) == "240 m")
    return passed
}

// API shapes apps use, compiled here so a missing initializer fails this file.
@MainActor
private func apiShapes() async {
    let c = CLLocationCoordinate2D(latitude: 1, longitude: 2)
    let manager = CLLocationManager()
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.requestWhenInUseAuthorization()
    if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    _ = manager.authorizationStatus == .authorizedWhenInUse
    _ = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: 1, longitude: 2)).first?.timeZone
    let request = MKDirections.Request()
    request.source = MKMapItem.forCurrentLocation()
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: c))
    request.transportType = .walking
    do { _ = try await MKDirections(request: request).calculate().routes.first?.polyline }
    catch let error as MKError { _ = error.code == .directionsNotFound } catch {}
    _ = try? await MKDirections(request: request).calculateETA().expectedTravelTime
    let completer = MKLocalSearchCompleter()
    completer.resultTypes = [.pointOfInterest, .address]
    completer.addressFilter = MKAddressFilter(including: [.locality, .country])
    completer.region = MKCoordinateRegion(center: c, latitudinalMeters: 1000, longitudinalMeters: 1000)
    completer.queryFragment = "cafe"
    _ = completer.results.map(\.subtitle)
    _ = try? await MKLocalSearch(request: MKLocalSearch.Request()).start().mapItems
    _ = try? await MKLookAroundSceneRequest(coordinate: c).scene
    MKMapItem(placemark: MKPlacemark(coordinate: c)).openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    MKMapItem.openMaps(with: [MKMapItem(placemark: MKPlacemark(coordinate: c))],
                       launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    let watcher = HeadingWatcher()
    manager.delegate = watcher
    completer.delegate = watcher
    _ = describe(MKPlacemark(coordinate: c), .hotel, MKError(.loadingThrottled))
    do { for try await update in CLLocationUpdate.liveUpdates() { _ = update.location } } catch {}
}

private final class HeadingWatcher: NSObject, CLLocationManagerDelegate, MKLocalSearchCompleterDelegate {
    var heading: CLLocationDirection = 0
    var status: CLAuthorizationStatus = .notDetermined
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {}
}

private func describe(_ placemark: MKPlacemark, _ category: MKPointOfInterestCategory?, _ error: Error) -> String {
    let kind: String
    switch category {
    case .some(.hotel), .some(.campground): kind = "stay"
    case .some(.restaurant), .some(.cafe): kind = "food"
    default: kind = "other"
    }
    let problem: String
    if let mapKitError = error as? MKError {
        switch mapKitError.code {
        case .placemarkNotFound, .directionsNotFound: problem = "not found"
        case .loadingThrottled: problem = "throttled"
        default: problem = "offline"
        }
    } else { problem = "offline" }
    let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
    return [placemark.name, street, placemark.locality, placemark.isoCountryCode, kind, problem].compactMap { $0 }.joined(separator: ", ")
}

private struct Leg { let line: MKPolyline; let dashed: Bool }

private struct ChecksView: View {
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: Int?
    @State private var passed = runChecks()
    private let legs = [Leg(line: MKPolyline(coordinates: [CLLocationCoordinate2D(latitude: 46.25, longitude: 6.2),
                                                         CLLocationCoordinate2D(latitude: 46.4, longitude: 6.3)], count: 2), dashed: true)]
    private let camera = MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12), distance: 4000, heading: 37)

    /// MapProxy round trips and the camera the map settles on, checked once the map is laid out.
    private func checkProxy(_ proxy: MapProxy, _ context: MapCameraUpdateContext) {
        var names: [String] = []
        for point in [CGPoint(x: 20, y: 30), CGPoint(x: 200, y: 100)] {
            guard let coordinate = proxy.convert(point, from: .local), let again = proxy.convert(coordinate, to: .local) else {
                preconditionFailure("MapProxy returned nil after layout")
            }
            precondition(close(again.x, point.x, 1e-6) && close(again.y, point.y, 1e-6), "MapProxy round trip")
            names.append("MapProxy round trip (\(Int(point.x)), \(Int(point.y)))")
        }
        precondition(close(context.camera.distance, 4000, 1e-6) && context.camera.heading == 37, "camera round trip")
        let center = proxy.convert(camera.centerCoordinate, to: .local)!
        precondition(close(center.x, 195, 1e-6) && close(center.y, 60, 1e-6), "camera center at the view's center")
        names += ["camera distance and heading", "camera center"]
        passed += names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MapReader { proxy in
                Map(position: $position, bounds: MapCameraBounds(minimumDistance: 500), interactionModes: [.pan, .zoom], selection: $selection) {
                    MapPolyline(MKPolyline(coordinates: [CLLocationCoordinate2D(latitude: 46.2, longitude: 6.1),
                                                         CLLocationCoordinate2D(latitude: 46.5, longitude: 6.6)], count: 2))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [2, 8]))
                    Marker("Selected", systemImage: "star.fill", coordinate: CLLocationCoordinate2D(latitude: 46.2, longitude: 6.1)).tag(1)
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: 46.5, longitude: 6.6)) { Circle().frame(width: 12) }
                    ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                        MapPolyline(leg.line).stroke(.gray, style: StrokeStyle(lineWidth: 2, dash: leg.dashed ? [2, 6] : []))
                    }
                    if selection != nil { UserAnnotation() }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .continuous) { context in _ = context.region.span }
                .onMapCameraChange(frequency: .onEnd) { context in _ = context.region.center }
                .onTapGesture { point in _ = proxy.convert(point, from: .local) }
                .onAppear { _ = proxy.convert(CLLocationCoordinate2D(latitude: 46, longitude: 6), to: .global) }
            }
            .frame(height: 240)
            MapReader { proxy in
                Map(initialPosition: .camera(camera)) { Marker("London", coordinate: camera.centerCoordinate) }
                    .onMapCameraChange { context in checkProxy(proxy, context) }
            }
            .frame(width: 390, height: 120)
            List(passed, id: \.self) { Label($0, systemImage: "checkmark.circle.fill") }
        }
        .task { await apiShapes() }
        .onAppear { selection = 1 }
    }
}

#Preview("MapKit checks") { ChecksView() }
