// Generated asset symbols (Xcode 15+): `ColorResource` and `ImageResource` values name an asset in a
// catalog, and `Color(.brand)` / `Image(.logo)` look them up. Project mode generates the static
// members (`ColorResource.brand`) from a module's catalogs, as Xcode's GeneratedAssetSymbols.swift
// does. Assets are found by name in every catalog given to the renderer; the bundle is not consulted.

public struct ColorResource: Hashable, Sendable {
    public let name: String
    public let bundle: Bundle
    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }
}

public struct ImageResource: Hashable, Sendable {
    public let name: String
    public let bundle: Bundle
    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }
}

extension Color {
    public init(_ resource: ColorResource) { self.init(resource.name, bundle: resource.bundle) }
}

extension Image {
    public init(_ resource: ImageResource) { self.init(resource.name, bundle: resource.bundle) }
}
