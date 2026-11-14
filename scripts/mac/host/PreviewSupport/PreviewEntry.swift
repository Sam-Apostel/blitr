import SwiftUI

/// The host app's counterpart of the renderer's `SwiftUI._PreviewEntry`: what a rewritten
/// `#Preview { ... }` evaluates to. Same initializer, so the preprocessed sources compile unchanged.
public struct _PreviewEntry {
    public let name: String?
    public let orientation: String?
    public let layout: String?
    public let width: Double?
    public let height: Double?
    public let make: @MainActor () -> AnyView

    public init<V: View>(_ name: String? = nil, orientation: String? = nil, layout: String? = nil, width: Double? = nil,
                         height: Double? = nil, @ViewBuilder _ body: @escaping @MainActor () -> V) {
        self.name = name
        self.orientation = orientation
        self.layout = layout
        self.width = width
        self.height = height
        self.make = { AnyView(body()) }
    }
}
