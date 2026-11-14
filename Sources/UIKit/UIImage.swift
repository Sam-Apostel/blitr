import Foundation
import SwiftUI
import ImageIO
import CoreImage
internal import CSkia

// UIImage: a named asset, an SF Symbol, or pixels (decoded data, a CGImage, a renderer's output).
// `Image(uiImage:)` draws all three.

open class UIImage: NSObject, @unchecked Sendable {
    public enum RenderingMode: Int, Sendable { case automatic, alwaysOriginal, alwaysTemplate }
    public enum Orientation: Int, Sendable {
        case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored

        var swiftUI: Image.Orientation {
            switch self {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .upMirrored: return .upMirrored
            case .downMirrored: return .downMirrored
            case .leftMirrored: return .leftMirrored
            case .rightMirrored: return .rightMirrored
            }
        }
        public init(_ cgOrientation: CGImagePropertyOrientation) {
            switch cgOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
            case .left: self = .left
            }
        }
    }
    public enum ResizingMode: Int, Sendable { case tile, stretch }
    public enum DynamicRange: Int, Sendable { case unspecified = -1, standard, constrainedHigh, high }

    open class Configuration: NSObject {
        public override init() { super.init() }
    }
    public enum SymbolWeight: Int, Sendable {
        case unspecified, ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }
    public enum SymbolScale: Int, Sendable { case `default` = -1, unspecified, small, medium, large }
    public class SymbolConfiguration: Configuration {
        public typealias Scale = SymbolScale
        var pointSize: CGFloat?
        var weight: UIFont.Weight?
        var scale = SymbolScale.default
        var colors: [UIColor] = []

        public init(pointSize: CGFloat, weight: SymbolWeight = .regular, scale: SymbolScale = .default) {
            super.init()
            self.pointSize = pointSize
            self.weight = [UIFont.Weight.regular, .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black][weight.rawValue]
            self.scale = scale
        }
        public init(weight: SymbolWeight) {
            super.init()
            self.weight = [UIFont.Weight.regular, .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black][weight.rawValue]
        }
        public init(scale: SymbolScale) { super.init(); self.scale = scale }
        public init(font: UIFont, scale: SymbolScale = .default) { super.init(); pointSize = font.pointSize; self.scale = scale }
        public init(textStyle: UIFont.TextStyle, scale: SymbolScale = .default) {
            super.init()
            pointSize = textStyle.swiftUI.metrics.size
            self.scale = scale
        }
        public init(hierarchicalColor: UIColor) { super.init(); colors = [hierarchicalColor] }
        public init(paletteColors: [UIColor]) { super.init(); colors = paletteColors }
        public override init() { super.init() }
        public class func preferringMulticolor() -> SymbolConfiguration { SymbolConfiguration() }
        public class func preferringMonochrome() -> SymbolConfiguration { SymbolConfiguration() }
        public func applying(_ other: Configuration?) -> SymbolConfiguration {
            guard let other = other as? SymbolConfiguration else { return self }
            let merged = SymbolConfiguration()
            merged.pointSize = other.pointSize ?? pointSize
            merged.weight = other.weight ?? weight
            merged.scale = other.scale == .default ? scale : other.scale
            merged.colors = other.colors.isEmpty ? colors : other.colors
            return merged
        }
    }

    /// Where the pixels come from: SwiftUI's named, system and file images, or pixels in memory.
    enum Source: Equatable {
        case named(String)
        case system(String)
        case file(String)
        case pixels(CGImage, scale: CGFloat, orientation: Image.Orientation)
    }
    let source: Source
    var template = false
    var original = false
    var symbolConfiguration: SymbolConfiguration?
    private let fixedScale: CGFloat?

    init(source: Source, scale: CGFloat? = nil) {
        self.source = source
        fixedScale = scale
        super.init()
    }

    public convenience override init() { self.init(source: .named("")) }
    /// Always succeeds: a missing asset renders as a visible placeholder (with a warning) instead of nothing.
    public convenience init?(named name: String) { self.init(source: .named(name)) }
    public convenience init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) { self.init(source: .named(name)) }
    public convenience init?(named name: String, in bundle: Bundle?, with configuration: Configuration?) { self.init(source: .named(name)) }
    public convenience init?(systemName name: String) { self.init(source: .system(name)) }
    public convenience init?(systemName name: String, withConfiguration configuration: Configuration?) {
        self.init(source: .system(name))
        symbolConfiguration = configuration as? SymbolConfiguration
    }
    public convenience init?(systemName name: String, compatibleWith traitCollection: UITraitCollection?) { self.init(source: .system(name)) }
    public convenience init?(systemName name: String, variableValue: Double, configuration: Configuration? = nil) {
        self.init(source: .system(name))
        symbolConfiguration = configuration as? SymbolConfiguration
    }

    /// Decodes PNG, JPEG, WebP, GIF, BMP and ICO data; other formats (HEIC, AVIF) give nil, as undecodable data does on iOS.
    public convenience init?(data: Data) { self.init(data: data, scale: 1) }
    public convenience init?(data: Data, scale: CGFloat) {
        guard let box = SkImageBox.decode(data) else {
            if _encodedFormatName(data) == "public.heic" {
                ShimDiagnostics.warn("UIImage(data:): HEIC data cannot be decoded here (PNG, JPEG, WebP and GIF can); the image is nil")
            }
            return nil
        }
        let image = CGImage(box: box)
        image.sourceType = _encodedFormatName(data)
        self.init(source: .pixels(image, scale: scale, orientation: .up), scale: scale)
    }
    public convenience init?(contentsOfFile path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        self.init(data: data, scale: name.hasSuffix("@3x") ? 3 : name.hasSuffix("@2x") ? 2 : 1)
    }
    public convenience init(cgImage: CGImage) { self.init(source: .pixels(cgImage, scale: 1, orientation: .up), scale: 1) }
    public convenience init(cgImage: CGImage, scale: CGFloat, orientation: Orientation) {
        self.init(source: .pixels(cgImage, scale: scale, orientation: orientation.swiftUI), scale: scale)
    }

    // MARK: Properties

    public var renderingMode: RenderingMode { template ? .alwaysTemplate : original ? .alwaysOriginal : .automatic }
    public var imageOrientation: Orientation {
        guard case .pixels(_, _, let o) = source else { return .up }
        switch o {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
    public var scale: CGFloat {
        if let fixedScale { return fixedScale }
        return _currentConfiguration().scale ?? _currentConfiguration().device.scale
    }
    /// The size in points, after the orientation is applied.
    public var size: CGSize {
        switch source {
        case .pixels(let image, let scale, let orientation):
            let s = max(scale, 0.01)
            let (w, h) = (CGFloat(image.width) / s, CGFloat(image.height) / s)
            switch orientation {
            case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: h, height: w)
            default: return CGSize(width: w, height: h)
            }
        case .named(let name):
            guard Thread.isMainThread else { return .zero }
            return MainActor.assumeIsolated { AssetCatalog.shared.bitmap(named: name, scheme: .light)?.pointSize ?? .zero }
        case .system:
            guard Thread.isMainThread else { return .zero }
            return MainActor.assumeIsolated { symbolSize() ?? .zero }
        case .file:
            return cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        }
    }
    public var isSymbolImage: Bool { if case .system = source { return true } else { return false } }
    public var configuration: Configuration? { symbolConfiguration }
    public var images: [UIImage]? { nil }
    public var duration: TimeInterval { 0 }
    public var capInsets: UIEdgeInsets { .zero }
    public var alignmentRectInsets: UIEdgeInsets { .zero }
    public var flipsForRightToLeftLayoutDirection: Bool { false }
    public var isHighDynamicRange: Bool { false }

    /// The pixels: the image's own, an asset's, or a symbol drawn in its tint (black without one).
    public var cgImage: CGImage? {
        switch source {
        case .pixels(let image, _, let orientation):
            _ = orientation
            return image
        case .named(let name):
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated {
                guard let bitmap = AssetCatalog.shared.bitmap(named: name, scheme: _currentConfiguration().colorScheme) else { return nil }
                sk_image_ref(bitmap.image)
                return CGImage(box: SkImageBox(adopting: bitmap.image))
            }
        case .file(let path):
            return FileManager.default.contents(atPath: path).flatMap(SkImageBox.decode).map { CGImage(box: $0) }
        case .system:
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated { renderedSymbol(color: RGBA.black) }
        }
    }

    private var symbolParameters: (name: String, size: CGFloat, weight: Font.Weight, scale: Image.Scale)? {
        guard case .system(let name) = source else { return nil }
        let c = symbolConfiguration
        let scale: Image.Scale = c?.scale == .small ? .small : c?.scale == .large ? .large : .medium
        return (name, c?.pointSize ?? 17, (c?.weight ?? .regular).swiftUI, scale)
    }
    @MainActor private func symbolSize() -> CGSize? {
        symbolParameters.flatMap { _symbolSize(named: $0.name, pointSize: $0.size, weight: $0.weight, scale: $0.scale) }
    }
    /// The symbol drawn into a bitmap at the screen scale.
    @MainActor private func renderedSymbol(color: RGBA) -> CGImage? {
        guard let p = symbolParameters else { return nil }
        return _renderSymbol(named: p.name, pointSize: p.size, weight: p.weight, scale: p.scale, color: (color.r, color.g, color.b, color.a), pixelScale: scale)
    }

    /// The image's pixels with the orientation applied, at its own scale.
    var uprightPixels: CGImage? {
        guard case .pixels(let image, _, let orientation) = source else { return cgImage }
        return orientation == .up ? image : image.oriented(PixelOrientation(orientation))
    }

    /// What `Image(uiImage:)` draws.
    var swiftUISource: Image.Source {
        switch source {
        case .named(let name): return .named(name)
        case .system(let name): return .system(name)
        case .file(let path): return .file(path)
        case .pixels(let image, let scale, let orientation):
            return .rendered(RenderedImage(cgImage: orientation == .up ? image : image.oriented(PixelOrientation(orientation)), scale: scale))
        }
    }
    /// From SwiftUI's sources (asset resources, ImageRenderer output).
    convenience init(source: Image.Source) {
        switch source {
        case .named(let name): self.init(source: Source.named(name))
        case .system(let name): self.init(source: Source.system(name))
        case .file(let path): self.init(source: Source.file(path))
        case .rendered(let rendered): self.init(source: .pixels(rendered.cgImage, scale: rendered.scale, orientation: .up), scale: rendered.scale)
        }
    }

    // MARK: Encoding

    public func pngData() -> Data? { uprightPixels?.box.encoded(.png) }
    public func jpegData(compressionQuality: CGFloat) -> Data? { uprightPixels?.box.encoded(.jpeg, quality: Double(compressionQuality)) }
    /// HEIC cannot be encoded here.
    public func heicData() -> Data? {
        ShimDiagnostics.warn("UIImage.heicData(): HEIC cannot be encoded here; returning nil")
        return nil
    }

    // MARK: Derived images

    private func derived(source: Source? = nil, scale: CGFloat? = nil) -> UIImage {
        let copy = UIImage(source: source ?? self.source, scale: scale ?? fixedScale)
        copy.template = template
        copy.original = original
        copy.symbolConfiguration = symbolConfiguration
        return copy
    }

    public func withRenderingMode(_ mode: RenderingMode) -> UIImage {
        let result = derived()
        result.template = mode == .alwaysTemplate
        result.original = mode == .alwaysOriginal
        return result
    }
    /// The image's shape filled with `color` (drawn as is, not as a template).
    public func withTintColor(_ color: UIColor) -> UIImage { withTintColor(color, renderingMode: .alwaysOriginal) }
    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode) -> UIImage {
        let rgba = _currentConfiguration().colorScheme == .dark ? color.dynamic.dark : color.dynamic.light
        var tinted: CGImage?
        if case .system = source, Thread.isMainThread {
            tinted = MainActor.assumeIsolated { renderedSymbol(color: rgba) }
        } else if let pixels = uprightPixels {
            tinted = pixels.box.tinted(r: rgba.r, g: rgba.g, b: rgba.b, a: rgba.a).map { CGImage(box: $0) }
        }
        guard let tinted else { return withRenderingMode(renderingMode) }
        let result = UIImage(source: .pixels(tinted, scale: scale, orientation: .up), scale: scale)
        result.template = renderingMode == .alwaysTemplate
        result.original = renderingMode != .alwaysTemplate
        return result
    }
    public func withConfiguration(_ configuration: Configuration) -> UIImage {
        let result = derived()
        if let symbol = configuration as? SymbolConfiguration { result.symbolConfiguration = (symbolConfiguration ?? SymbolConfiguration()).applying(symbol) }
        return result
    }
    public func applyingSymbolConfiguration(_ configuration: SymbolConfiguration) -> UIImage? { withConfiguration(configuration) }
    public func withAlignmentRectInsets(_ insets: UIEdgeInsets) -> UIImage { self }
    public func resizableImage(withCapInsets insets: UIEdgeInsets) -> UIImage { self }
    public func resizableImage(withCapInsets insets: UIEdgeInsets, resizingMode: ResizingMode) -> UIImage { self }
    public func imageFlippedForRightToLeftLayoutDirection() -> UIImage { self }
    public func withBaselineOffset(fromBottom baselineOffset: CGFloat) -> UIImage { self }
    public func withHorizontallyFlippedOrientation() -> UIImage {
        guard case .pixels(let image, let s, let o) = source else { return self }
        let flipped: [Image.Orientation: Image.Orientation] = [
            .up: .upMirrored, .upMirrored: .up, .down: .downMirrored, .downMirrored: .down,
            .left: .rightMirrored, .rightMirrored: .left, .right: .leftMirrored, .leftMirrored: .right,
        ]
        return derived(source: .pixels(image, scale: s, orientation: flipped[o] ?? o))
    }

    /// Resampled to fit `size` in pixels... UIKit takes points at the screen scale; the result has scale 1 times that.
    public func preparingThumbnail(of size: CGSize) -> UIImage? {
        guard let pixels = uprightPixels, size.width >= 1, size.height >= 1 else { return nil }
        let screen = _currentConfiguration().scale ?? _currentConfiguration().device.scale
        let (w, h) = (Int((size.width * screen).rounded()), Int((size.height * screen).rounded()))
        guard let box = pixels.box.scaled(width: max(w, 1), height: max(h, 1)) else { return nil }
        return UIImage(source: .pixels(CGImage(box: box), scale: screen, orientation: .up), scale: screen)
    }
    public func prepareThumbnail(of size: CGSize, completionHandler: @escaping (UIImage?) -> Void) {
        completionHandler(preparingThumbnail(of: size))
    }
    public func byPreparingThumbnail(ofSize size: CGSize) async -> UIImage? { preparingThumbnail(of: size) }
    public func preparingForDisplay() -> UIImage? { self }
    public func prepareForDisplay(completionHandler: @escaping (UIImage?) -> Void) { completionHandler(self) }
    public func byPreparingForDisplay() async -> UIImage? { self }

    // MARK: Drawing into the current context

    /// Draws the image upright in `rect` of the current graphics context (see `UIGraphicsImageRenderer`).
    public func draw(in rect: CGRect) { draw(in: rect, blendMode: .normal, alpha: 1) }
    public func draw(at point: CGPoint) { draw(in: CGRect(origin: point, size: size)) }
    public func draw(at point: CGPoint, blendMode: CGBlendMode, alpha: CGFloat) {
        draw(in: CGRect(origin: point, size: size), blendMode: blendMode, alpha: alpha)
    }
    public func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext(), rect.width != 0, rect.height != 0 else { return }
        var pixels = uprightPixels
        if case .system = source, Thread.isMainThread {
            pixels = MainActor.assumeIsolated { renderedSymbol(color: UIColor.tintColor.dynamic.light) }
        }
        guard let pixels else { return }
        context.saveGState()
        context.setBlendMode(blendMode)
        context.setAlpha(alpha)
        // UIKit draws images the right way up in its flipped contexts.
        let fit = CGAffineTransform(a: rect.width / CGFloat(pixels.width), b: 0, c: 0, d: rect.height / CGFloat(pixels.height),
                                    tx: rect.minX, ty: rect.minY)
        context.drawImage(pixels.box, transform: fit.concatenating(context.ctm))
        context.restoreGState()
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? UIImage else { return false }
        return other === self || (other.source == source && other.template == template && other.original == original)
    }
}

// MARK: - SwiftUI bridges

extension Image {
    public init(uiImage: UIImage) {
        self.init("")
        source = uiImage.swiftUISource
        if uiImage.template { renderingMode = .template }
    }
}

extension ImageRenderer {
    public var uiImage: UIImage? { cgImage.map { UIImage(cgImage: $0, scale: scale, orientation: .up) } }
}

// MARK: - Core Image

extension UIImage {
    /// Rendered at once over the image's extent (an infinite image gives an empty UIImage).
    public convenience init(ciImage: CIImage) { self.init(ciImage: ciImage, scale: 1, orientation: .up) }
    public convenience init(ciImage: CIImage, scale: CGFloat, orientation: Orientation) {
        if let cg = CIContext().createCGImage(ciImage, from: ciImage.extent) {
            self.init(cgImage: cg, scale: scale, orientation: orientation)
        } else {
            self.init(source: Source.named(""))
        }
    }
    public var ciImage: CIImage? { nil }
}
extension CIImage {
    public convenience init?(image: UIImage) {
        guard let cg = image.uprightPixels else { return nil }
        self.init(cgImage: cg)
    }
    public convenience init?(image: UIImage, options: [CIImageOption: Any]? = nil) { self.init(image: image) }
}
extension CIColor {
    public convenience init(color: UIColor) { self.init(cgColor: color.cgColor) }
}
