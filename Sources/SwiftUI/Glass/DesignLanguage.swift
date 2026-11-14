// Which iOS release's look is being rendered.

/// The visual language of system components.
enum DesignLanguage: Equatable {
    /// iOS 18 and earlier: opaque bars and cards, materials.
    case flat
    /// iOS 26: Liquid Glass.
    case liquidGlass26
    /// iOS 27: Liquid Glass, refined (defined edges, hard scroll-edge effect, darker selection).
    case liquidGlass27

    init(osVersion: Int) {
        self = osVersion >= 27 ? .liquidGlass27 : osVersion >= 26 ? .liquidGlass26 : .flat
    }
    var isGlass: Bool { self != .flat }
}

enum PlatformVersionKey: EnvironmentKey { static let defaultValue = RenderedPlatform.defaultVersion }

extension EnvironmentValues {
    /// Major iOS version being rendered (18, 26, 27, ...).
    var platformVersion: Int {
        get { self[PlatformVersionKey.self] }
        set { self[PlatformVersionKey.self] = newValue }
    }
    var designLanguage: DesignLanguage { DesignLanguage(osVersion: platformVersion) }
}

/// The Apple platform whose look and conventions are rendered. Chosen before compilation,
/// because `#if os(...)` in user code is resolved by the compiler.
enum RenderPlatform: String, CaseIterable, Sendable {
    case iOS, tvOS, watchOS, macOS, visionOS

    init?(argument: String) {
        guard let match = RenderPlatform.allCases.first(where: { $0.rawValue.lowercased() == argument.lowercased() }) else { return nil }
        self = match
    }
}

enum RenderPlatformKey: EnvironmentKey { static let defaultValue = RenderPlatform.iOS }

extension EnvironmentValues {
    var renderPlatform: RenderPlatform {
        get { self[RenderPlatformKey.self] }
        set { self[RenderPlatformKey.self] = newValue }
    }
}

/// Runtime answer to `#available(iOS N, *)`, which the preprocessor rewrites to a call here:
/// on Linux the compiler would otherwise treat every availability check as true.
public enum RenderedPlatform {
    /// iOS versions with a distinct look that the renderer knows how to draw.
    static let supportedVersions = [18, 26, 27]
    static let defaultVersion = 27
    nonisolated(unsafe) static var current = defaultVersion
    nonisolated(unsafe) static var platform = RenderPlatform.iOS

    public static func isAtLeast(iOS major: Int, _ minor: Int = 0) -> Bool { current >= major }
}
