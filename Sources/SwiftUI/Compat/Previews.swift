// Xcode's preview API before `#Preview`: PreviewProvider and the preview modifiers. The runner renders a
// provider's `previews` (see Preprocessor); the modifiers are preview metadata, and the layout, device and
// orientation they name are chosen with the tool's --layout, --device and --orientation flags instead.

public enum PreviewPlatform: Sendable { case iOS, macOS, tvOS, watchOS, visionOS }

@MainActor @preconcurrency
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder @MainActor @preconcurrency static var previews: Self.Previews { get }
    static var platform: PreviewPlatform? { get }
}
extension PreviewProvider {
    public static var platform: PreviewPlatform? { nil }
}

public enum PreviewLayout: Sendable {
    case device, sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
}

public struct PreviewDevice: RawRepresentable, ExpressibleByStringLiteral, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
}

public enum InterfaceOrientation: CaseIterable, Identifiable, Equatable, Sendable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
    public var id: Self { self }
}

/// A preview's context, such as WidgetKit's `WidgetPreviewContext(family:)`.
public protocol PreviewContext {}

extension View {
    public func previewLayout(_ value: PreviewLayout) -> some View { self }
    public func previewDevice(_ value: PreviewDevice?) -> some View { self }
    public func previewDisplayName(_ value: String?) -> some View { self }
    public func previewContext<C: PreviewContext>(_ value: C) -> some View { self }
    public func previewInterfaceOrientation(_ value: InterfaceOrientation) -> some View { self }
}
