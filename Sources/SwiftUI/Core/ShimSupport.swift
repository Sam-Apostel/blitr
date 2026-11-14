// Hooks for the shim framework modules of this package (MapKit, WidgetKit, UIKit, ...), which extend
// SwiftUI types from outside the module. `package` access: app code compiled against the SDK cannot see
// them. See docs/ARCHITECTURE.md, "Shim modules".

extension ForEach {
    /// For `ForEach` conformances in other modules (MapKit's `MapContent`), which cannot assign the stored
    /// properties of a resilient struct themselves.
    package init(_data data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
}

extension Group {
    package init(_content content: Content) { self.content = content }
}
