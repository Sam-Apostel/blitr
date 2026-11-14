# MapKit and CoreLocation

Files that `import MapKit` or `import CoreLocation` compile unchanged. There is no map data on
Linux, so a `Map` draws a placeholder surface instead of map tiles, and on top of it, in the right
place, everything the app itself puts on the map. Every render that contains a map prints one
warning saying that tiles are not drawn.

## Layout of the code

The API is in two modules of its own, `Sources/CoreLocation` (Foundation only) and `Sources/MapKit`
(which imports SwiftUI and re-exports CoreLocation and UIKit, as Apple's does), so `Map`, `Marker` and
`Annotation` are only visible where MapKit is imported. Their code is linked into libSwiftUIScreenshotEngine, so there
is one copy of SwiftUI at run time and protocol conformances resolve (ARCHITECTURE.md, "Shim modules").

| File | Contents |
|---|---|
| `LocationCoordinates.swift` | `CLLocationCoordinate2D`, constants, `CLLocation`, heading and region types, geodesy |
| `LocationServices.swift` | `CLLocationManager` and its delegate, `CLLocationUpdate`, `CLError`, `CLGeocoder`, `CLPlacemark` |
| `MapGeometry.swift` | `MKMapPoint`/`MKMapSize`/`MKMapRect`, `MKCoordinateRegion`/`Span`, `MKMapCamera` |
| `MapShapes.swift` | `MKAnnotation`, `MKOverlay`, `MKPolyline`, `MKGeodesicPolyline`, `MKPolygon`, `MKCircle` |
| `MapItems.swift` | `MKMapItem`, `MKPlacemark`, point-of-interest categories and filters, launch options, `MKDistanceFormatter` |
| `MapServices.swift` | `MKDirections`, `MKRoute`, `MKLocalSearch`, `MKLocalSearchCompleter`, Look Around, `MKError` |
| `MKMapView.swift` | UIKit shells: `MKMapView`, annotation views, overlay renderers, map configurations |
| `MapContent.swift` | `MapContent`, `MapContentBuilder`, `Marker`, `Annotation`, `UserAnnotation`, `MapPolyline`/`Polygon`/`Circle`, content modifiers |
| `MapCamera.swift` | `MapCamera`, `MapCameraPosition`, `MapCameraBounds`, `MapStyle`, interaction modes, selection |
| `Map.swift` | `Map` (iOS 17 and legacy initializers), view modifiers, `MapReader`/`MapProxy`, `LookAroundPreview` |
| `MapProjection.swift` | Web Mercator projection of a resolved camera into the view's frame |
| `MapRendering.swift` | the surface, overlays, pins, labels and attribution |
| `MapControls.swift` | `MapCompass`, `MapScaleView`, `MapUserLocationButton`, `MapPitchToggle` |

## What is real

- **Geometry.** `MKMapPoint` uses Apple's spherical Mercator with a world of 2^28 map points;
  `MKMapRect`, `MKCoordinateRegion` and the conversion functions are exact. `CLLocation.distance(from:)`
  is Vincenty's formula on WGS 84. `MKGeodesicPolyline` stores the densified great circle.
- **Cameras.** `.region` and `.rect` fit the rect into the view (aspect fit). `.automatic` fits all
  markers, annotations and overlays, inset by the safe area plus a margin with room for marker
  balloons and titles; a single place is shown at street level. `.camera` uses a 30 degree vertical
  field of view to turn a distance into a zoom, and honours `heading` (the map rotates). `.item`
  centres on the item; `.userLocation(fallback:)` uses its fallback. `MapCameraBounds` clamps the
  distance and centre. The map never zooms out past one world width.
- **`MapReader`/`MapProxy`.** `convert` works in both directions and in any coordinate space, once
  the map is laid out (before that it returns `nil`, as on iOS). `onMapCameraChange` is called once
  with the camera the map settles on.

## What is drawn

- A land-coloured surface after Apple Maps' palette (light, dark, muted), a darker neutral for
  `.imagery`/`.hybrid`, and a faint graticule at a round spacing, so it reads as a map.
- Polylines, polygons (with holes) and circles with their stroke, stroke style and fill. Defaults:
  polylines 3 pt in the tint, shapes filled with the tint at 30 percent.
- `Marker`: Apple's balloon (gradient of the tint, red by default) with a white glyph (pin,
  SF Symbol, image or monogram), title below with a halo. A selected marker (its `tag` equals the
  selection) is drawn larger.
- `Annotation`: the app's own view, anchored at `anchor`, with its title below unless
  `.annotationTitles(.hidden)`. As in MapKit, a title that would cover another pin or a title already
  shown is left out.
- `UserAnnotation`: the blue dot. There is no device position, so it is drawn at the centre of the
  camera (the fallback's centre for `.userLocation(fallback:)`).
- Controls from `.mapControls`, where MapKit puts them: buttons top-trailing, scale top-leading.
  The compass appears only when the map is rotated and the scale only with
  `.mapControlVisibility(.visible)`, as on iOS. Buttons are rounded squares on iOS 18 and earlier and
  glass circles on iOS 26 and later (`--ios`). tvOS maps show no controls.
- The "Maps" and "Legal" attribution in the bottom-leading corner, inside the safe area. The Apple
  logo glyph is left out (it has no open-source stand-in).

## What is inert

- `CLLocationManager`: authorization stays `.notDetermined`, no update or delegate call is ever
  delivered. `CLLocationUpdate.liveUpdates()` ends at once.
- `CLGeocoder` throws `CLError.network`; `MKDirections.calculate()`/`calculateETA()` and
  `MKLocalSearch.start()` throw `MKError.serverFailure` with a message that says the service is not
  available, so apps take their offline path (for example drawing straight lines).
  `MKLocalSearchCompleter` produces no results and calls no delegate method.
- `MKLookAroundSceneRequest.scene` is `nil`; `LookAroundPreview` draws a grey placeholder.
- `MKMapItem.openInMaps`/`openMaps` return `false`.
- Points of interest, traffic, elevation and pitch have no visible effect (there is no map data).
- Selection accessories, detail sheets, `mapScope` and Look Around viewers return the view unchanged.
- `MKMapView` and the other UIKit classes keep their state but draw like any other wrapped `UIView`:
  the representable placeholder.

## Checking

```
swiftui-screenshot render Examples/Maps.swift --all --open-fonts
swiftui-screenshot render Examples/Maps.swift --preview tvOS --device apple-tv --open-fonts
swiftui-screenshot render Tests/Maps/MapKitChecks.swift --open-fonts
```

`Tests/Maps/MapKitChecks.swift` stops with a message when a check fails: map points of known
cities, coordinate round trips, Vincenty's published test line, region and rect conversions,
`MapProxy` round trips and the camera a map settles on.
