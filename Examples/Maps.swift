import SwiftUI
import MapKit

// MapKit in SwiftUI: markers, annotations, overlays, cameras and styles. There are no map tiles
// on Linux; the map surface is a placeholder and everything the app adds is drawn on top of it.

private extension CLLocationCoordinate2D {
    static let lisbon = CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393)
    static let sintra = CLLocationCoordinate2D(latitude: 38.7979, longitude: -9.3906)
    static let cascais = CLLocationCoordinate2D(latitude: 38.6979, longitude: -9.4215)
    static let setubal = CLLocationCoordinate2D(latitude: 38.5244, longitude: -8.8882)
    static let evora = CLLocationCoordinate2D(latitude: 38.5714, longitude: -7.9135)
}

struct Stop: Identifiable {
    let id: Int
    let name: String
    let coordinate: CLLocationCoordinate2D
}

private let stops = [
    Stop(id: 1, name: "Lisbon", coordinate: .lisbon),
    Stop(id: 2, name: "Sintra", coordinate: .sintra),
    Stop(id: 3, name: "Cascais", coordinate: .cascais),
    Stop(id: 4, name: "Setúbal", coordinate: .setubal),
    Stop(id: 5, name: "Évora", coordinate: .evora),
]

private let cityStops = [
    Stop(id: 1, name: "Belém Tower", coordinate: CLLocationCoordinate2D(latitude: 38.6916, longitude: -9.2160)),
    Stop(id: 2, name: "Monastery", coordinate: CLLocationCoordinate2D(latitude: 38.6979, longitude: -9.2068)),
    Stop(id: 3, name: "LX Factory", coordinate: CLLocationCoordinate2D(latitude: 38.7036, longitude: -9.1784)),
    Stop(id: 4, name: "Praça do Comércio", coordinate: CLLocationCoordinate2D(latitude: 38.7075, longitude: -9.1364)),
    Stop(id: 5, name: "Castle", coordinate: CLLocationCoordinate2D(latitude: 38.7139, longitude: -9.1335)),
]

// MARK: - Markers

struct MarkersMap: View {
    var body: some View {
        Map {
            Marker("Lisbon", coordinate: .lisbon)
            Marker("Sintra", systemImage: "tree.fill", coordinate: .sintra).tint(.green)
            Marker("Cascais", systemImage: "beach.umbrella.fill", coordinate: .cascais).tint(.orange)
            Marker("Setúbal", monogram: Text("ST"), coordinate: .setubal).tint(.purple)
            Marker("Évora", systemImage: "building.columns.fill", coordinate: .evora).tint(.blue)
        }
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapCompass()
        }
    }
}

// MARK: - A trip: route with numbered stops

struct NumberedStop: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.indigo))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

struct HotelBadge: View {
    var body: some View {
        Image(systemName: "bed.double.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.teal))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 1.5))
    }
}

struct TripMap: View {
    @State private var camera: MapCameraPosition = .automatic
    var body: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: cityStops.map(\.coordinate))
                .stroke(Color.indigo.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            ForEach(cityStops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    NumberedStop(number: stop.id)
                }
            }
            Annotation("Hotel", coordinate: CLLocationCoordinate2D(latitude: 38.7166, longitude: -9.1489), anchor: .bottom) {
                HotelBadge()
            }
            .annotationTitles(.hidden)
            Marker("Ferry", systemImage: "ferry.fill", coordinate: CLLocationCoordinate2D(latitude: 38.6985, longitude: -9.1550))
                .tint(.cyan)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

struct TripScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            TripMap()
                .frame(height: 430)
            List {
                ForEach(cityStops) { stop in
                    HStack(spacing: 12) {
                        NumberedStop(number: stop.id)
                        Text(stop.name)
                    }
                }
            }
            .listStyle(.plain)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Overlays

struct OverlaysMap: View {
    private let park = [
        CLLocationCoordinate2D(latitude: 38.735, longitude: -9.175),
        CLLocationCoordinate2D(latitude: 38.742, longitude: -9.160),
        CLLocationCoordinate2D(latitude: 38.730, longitude: -9.150),
        CLLocationCoordinate2D(latitude: 38.722, longitude: -9.166),
    ]
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.728, longitude: -9.150),
                                                        latitudinalMeters: 4500, longitudinalMeters: 4500))) {
            MapPolygon(coordinates: park)
                .foregroundStyle(.green.opacity(0.35))
                .stroke(.green, lineWidth: 2)
            MapCircle(center: .lisbon, radius: 600)
                .foregroundStyle(.orange.opacity(0.25))
                .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            MapPolyline(coordinates: [CLLocationCoordinate2D(latitude: 38.715, longitude: -9.17), .lisbon,
                                      CLLocationCoordinate2D(latitude: 38.73, longitude: -9.125)])
                .stroke(.blue, lineWidth: 5)
            Marker("Centre", coordinate: .lisbon)
        }
        .mapControls { MapScaleView() }
        .mapControlVisibility(.visible)
    }
}

// MARK: - Cameras

struct RegionVersusAutomatic: View {
    var body: some View {
        VStack(spacing: 8) {
            Map(initialPosition: .region(MKCoordinateRegion(center: .lisbon, span: MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)))) {
                ForEach(stops) { Marker($0.name, coordinate: $0.coordinate) }
            }
            Map {
                ForEach(stops) { Marker($0.name, coordinate: $0.coordinate) }
            }
        }
    }
}

struct ImageryMap: View {
    var body: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: .sintra, distance: 9000, heading: 30))) {
            Marker("Pena Palace", systemImage: "crown.fill", coordinate: CLLocationCoordinate2D(latitude: 38.7876, longitude: -9.3906))
                .tint(.yellow)
            UserAnnotation()
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }
}

// MARK: - A map card in a list

struct MapCardRow: View {
    var body: some View {
        List {
            Section("Day 2") {
                VStack(alignment: .leading, spacing: 8) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: .sintra, latitudinalMeters: 3000, longitudinalMeters: 3000)),
                        interactionModes: []) {
                        Marker("Sintra", systemImage: "tree.fill", coordinate: .sintra).tint(.green)
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Sintra").font(.headline)
                    Text("Palaces in the hills, 40 min by train").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Text("Cascais")
                Text("Back to Lisbon")
            }
        }
    }
}

// MARK: - Legacy API

struct LegacyMap: View {
    @State private var region = MKCoordinateRegion(center: .lisbon, span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: Array(stops.prefix(3))) { stop in
            MapMarker(coordinate: stop.coordinate, tint: .red)
        }
    }
}

// MARK: - MapReader

struct ReaderMap: View {
    @State private var labelPoint: CGPoint?
    var body: some View {
        MapReader { proxy in
            Map {
                ForEach(stops) { Marker($0.name, coordinate: $0.coordinate) }
            }
            .onMapCameraChange { _ in labelPoint = proxy.convert(.evora, to: .local) }
            .overlay(alignment: .topLeading) {
                if let labelPoint {
                    Text("Évora is here")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .position(x: labelPoint.x, y: labelPoint.y + 28)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Markers") { MarkersMap() }
#Preview("Trip") { TripScreen() }
#Preview("Overlays") { OverlaysMap() }
#Preview("Region vs automatic") { RegionVersusAutomatic() }
#Preview("Imagery") { ImageryMap() }
#Preview("Dark") { TripMap().preferredColorScheme(.dark) }
#Preview("Map card") { MapCardRow() }
#Preview("Legacy") { LegacyMap() }
#Preview("Reader") { ReaderMap() }
#Preview("tvOS") {
    Map {
        MapPolyline(coordinates: stops.map(\.coordinate), contourStyle: .geodesic)
            .stroke(.indigo, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        ForEach(stops) { stop in
            Annotation(stop.name, coordinate: stop.coordinate) { NumberedStop(number: stop.id) }
        }
    }
    .mapStyle(.standard(elevation: .flat, emphasis: .muted))
    .ignoresSafeArea()
}
