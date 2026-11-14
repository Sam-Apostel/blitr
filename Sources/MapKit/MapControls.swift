// Map controls: compass, scale, user-location button and pitch toggle. Inside `.mapControls`
// they are drawn where MapKit puts them (buttons top-trailing, scale top-leading); on their own
// (with `mapScope`) they draw where the app places them.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

enum MapControlSlot { case trailing, leading }

enum MapControlSlotKey: EnvironmentKey { static let defaultValue: MapControlSlot? = nil }
enum MapControlVisibilityKey: EnvironmentKey { static let defaultValue = Visibility.automatic }
enum MapControlHeadingKey: EnvironmentKey { static let defaultValue = 0.0 }
enum MapControlMetersPerPointKey: EnvironmentKey { static let defaultValue = 10.0 }

extension EnvironmentValues {
    var mapControlSlot: MapControlSlot? {
        get { self[MapControlSlotKey.self] }
        set { self[MapControlSlotKey.self] = newValue }
    }
    var mapControlVisibility: Visibility {
        get { self[MapControlVisibilityKey.self] }
        set { self[MapControlVisibilityKey.self] = newValue }
    }
    var mapControlHeading: Double {
        get { self[MapControlHeadingKey.self] }
        set { self[MapControlHeadingKey.self] = newValue }
    }
    var mapControlMetersPerPoint: Double {
        get { self[MapControlMetersPerPointKey.self] }
        set { self[MapControlMetersPerPointKey.self] = newValue }
    }
}

struct MapControlsOverlay: View {
    let controls: AnyView
    let projection: MapProjection
    let safeArea: EdgeInsets
    var body: some View {
        ZStack {
            VStack(spacing: 10) { controls }
                .environment(\.mapControlSlot, .trailing)
                .padding(.top, 8 + safeArea.top)
                .padding(.trailing, 8 + safeArea.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            HStack(spacing: 0) { controls }
                .environment(\.mapControlSlot, .leading)
                .padding(.top, 14 + safeArea.top)
                .padding(.leading, 12 + safeArea.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.mapControlHeading, projection.heading)
        .environment(\.mapControlMetersPerPoint, projection.metersPerPoint)
    }
}

/// One round (Liquid Glass) or rounded-square (iOS 17/18) control button.
struct MapControlButton<Label: View>: View {
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme
    let label: Label
    var body: some View {
        if design.isGlass {
            label.foregroundStyle(scheme == .dark ? Color.white : Color(white: 0.1))
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
        } else {
            label.foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(scheme == .dark ? Color(white: 0.24) : Color(white: 1, opacity: 0.96))
                    .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 1))
        }
    }
}

public struct MapUserLocationButton: View {
    @Environment(\.mapControlSlot) private var slot
    public init(scope: Namespace.ID? = nil) {}
    public var body: some View {
        if slot != .leading {
            MapControlButton(label: Image(systemName: "location").font(.system(size: 17, weight: .medium)))
        }
    }
}

public struct MapPitchToggle: View {
    @Environment(\.mapControlSlot) private var slot
    public init(scope: Namespace.ID? = nil) {}
    public var body: some View {
        if slot != .leading {
            MapControlButton(label: Text(verbatim: "3D").font(.system(size: 15, weight: .semibold)))
        }
    }
}

/// macOS controls; drawn like the iOS buttons where an app uses them.
public struct MapPitchSlider: View {
    public init(scope: Namespace.ID? = nil) {}
    public var body: some View { MapPitchToggle() }
}
public struct MapZoomStepper: View {
    @Environment(\.mapControlSlot) private var slot
    public init(scope: Namespace.ID? = nil) {}
    public var body: some View {
        if slot != .leading {
            MapControlButton(label: VStack(spacing: 6) { Text(verbatim: "+"); Text(verbatim: "−") }.font(.system(size: 15, weight: .semibold)))
        }
    }
}

/// Shown only while the map is rotated (or with `.mapControlVisibility(.visible)`).
public struct MapCompass: View {
    @Environment(\.mapControlSlot) private var slot
    @Environment(\.mapControlVisibility) private var visibility
    @Environment(\.mapControlHeading) private var heading
    public init(scope: Namespace.ID? = nil) {}
    public var body: some View {
        if slot != .leading, visibility == .visible || (visibility == .automatic && heading != 0) {
            ZStack {
                Circle().fill(Color(white: 0.22, opacity: 0.9))
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1).padding(3)
                CompassNeedle().fill(Color(red: 1, green: 0.23, blue: 0.19))
                    .frame(width: 8, height: 30)
                    .rotationEffect(.degrees(-heading))
                Text(verbatim: "N").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
    }
}

struct CompassNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.32))
        p.closeSubpath()
        return p
    }
}

/// Shown only while zooming (or with `.mapControlVisibility(.visible)`).
public struct MapScaleView: View {
    @Environment(\.mapControlSlot) private var slot
    @Environment(\.mapControlVisibility) private var visibility
    @Environment(\.mapControlMetersPerPoint) private var metersPerPoint
    @Environment(\.colorScheme) private var scheme
    public init(anchorEdge: HorizontalEdge = .leading, scope: Namespace.ID? = nil) {}
    public var body: some View {
        if slot != .trailing, visibility == .visible {
            let (meters, label) = Self.niceLength(maxPoints: 90, metersPerPoint: metersPerPoint)
            let width = meters / metersPerPoint
            let ink = scheme == .dark ? Color.white : Color(white: 0.15)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(verbatim: "0").font(.system(size: 10, weight: .semibold)).frame(width: width / 2, alignment: .leading)
                    Text(verbatim: label).font(.system(size: 10, weight: .semibold)).fixedSize()
                }
                HStack(spacing: 0) {
                    Rectangle().fill(ink).frame(width: width / 2, height: 3)
                    Rectangle().fill(scheme == .dark ? Color(white: 0.35) : Color.white).frame(width: width / 2, height: 3)
                }
                .overlay(Rectangle().stroke(ink, lineWidth: 0.5))
            }
            .foregroundStyle(ink)
        }
    }

    static func niceLength(maxPoints: Double, metersPerPoint: Double) -> (Double, String) {
        let metric = !(Locale.current.region?.identifier == "US")
        let unit = metric ? 1.0 : 0.3048
        let maxUnits = maxPoints * metersPerPoint / unit
        let magnitude = pow(10, floor(log10(max(maxUnits, 1e-9))))
        let nice = [5.0, 2, 1].map { $0 * magnitude }.first { $0 <= maxUnits } ?? magnitude
        let meters = nice * unit
        if metric {
            return meters >= 1000 ? (meters, "\(Self.format(meters / 1000)) km") : (meters, "\(Self.format(meters)) m")
        }
        let feet = nice
        return feet >= 5280 / 2 ? (meters, "\(Self.format(feet / 5280)) mi") : (meters, "\(Self.format(feet)) ft")
    }
    static func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
