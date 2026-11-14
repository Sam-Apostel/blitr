// `import MapKit`: MapKit's types and SwiftUI's `Map`, which Apple ships as MapKit's SwiftUI overlay, so
// its names are only visible where MapKit is imported. There are no map tiles on Linux; see Map.swift.
// Like Apple's, the module re-exports CoreLocation and UIKit (MKMapView is a UIView), not SwiftUI.
@_exported import CoreLocation
@_exported import UIKit
@_exported import Foundation
