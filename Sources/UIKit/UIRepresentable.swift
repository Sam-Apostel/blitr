// UIViewRepresentable and UIViewControllerRepresentable. Their body makes the UIKit object (makeCoordinator,
// make..., update...) and shows what can be drawn from it: an image view's image, a label's text, an
// activity indicator, a blur or glass view, a hosting controller's SwiftUI root view, and the background
// colour, corner radius and alpha of any view. Anything else is a placeholder of the proposed size, with
// one warning naming the wrapped class.

import Foundation
import SwiftUI

public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public var transaction = Transaction()
    public var environment = EnvironmentValues()
}

public protocol UIViewRepresentable: View {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    typealias Context = UIViewRepresentableContext<Self>
    @MainActor func makeUIView(context: Context) -> UIViewType
    @MainActor func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
    @MainActor static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
    @MainActor func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIViewType, context: Context) -> CGSize?
}
extension UIViewRepresentable {
    @MainActor public var body: _UIKitRepresentableBody {
        let context = Context(coordinator: makeCoordinator())
        let view = makeUIView(context: context)
        updateUIView(view, context: context)
        return _UIKitRepresentableBody(view: view, representable: String(describing: Self.self))
    }
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIViewType, context: Context) -> CGSize? { nil }
}
extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void {}
}

public struct UIViewControllerRepresentableContext<Representable: UIViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public var transaction = Transaction()
    public var environment = EnvironmentValues()
}

public protocol UIViewControllerRepresentable: View {
    associatedtype UIViewControllerType: UIViewController
    associatedtype Coordinator = Void
    typealias Context = UIViewControllerRepresentableContext<Self>
    @MainActor func makeUIViewController(context: Context) -> UIViewControllerType
    @MainActor func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
    @MainActor static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator)
    @MainActor func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewControllerType, context: Context) -> CGSize?
}
extension UIViewControllerRepresentable {
    @MainActor public var body: _UIKitRepresentableBody {
        let context = Context(coordinator: makeCoordinator())
        let controller = makeUIViewController(context: context)
        updateUIViewController(controller, context: context)
        return _UIKitRepresentableBody(controller: controller, representable: String(describing: Self.self))
    }
    public static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewControllerType, context: Context) -> CGSize? { nil }
}
extension UIViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void {}
}

/// What a representable shows (see the top of this file).
public struct _UIKitRepresentableBody: View {
    let content: AnyView

    @MainActor init(view: UIView, representable: String) {
        content = _UIKitRepresentableBody.draw(view, representable: representable) ?? AnyView(
            _RepresentablePlaceholder(typeName: representable, wrapping: String(describing: type(of: view))))
    }
    @MainActor init(controller: UIViewController, representable: String) {
        if let hosting = controller as? _AnyHostingController {
            content = hosting.anyRootView
        } else if let view = controller.viewIfLoaded, let drawn = _UIKitRepresentableBody.draw(view, representable: representable) {
            content = drawn
        } else {
            content = AnyView(_RepresentablePlaceholder(typeName: representable, wrapping: String(describing: type(of: controller))))
        }
    }

    public var body: some View { content }

    private static func color(_ c: UIColor?) -> Color? { c.map { Color(uiColor: $0) } }

    /// The SwiftUI equivalent of a UIKit view, or nil when it cannot be drawn.
    @MainActor static func draw(_ view: UIView, representable: String) -> AnyView? {
        if view.isHidden || view.alpha <= 0.01 { return AnyView(Color.clear) }
        var inner: AnyView?
        switch view {
        case let drawable as _SwiftUIDrawableView:
            inner = drawable._swiftUIRepresentation
        case let imageView as UIImageView:
            if let image = imageView.isHighlighted ? (imageView.highlightedImage ?? imageView.image) : imageView.image {
                let base = Image(uiImage: image)
                switch imageView.contentMode {
                case .scaleAspectFit: inner = AnyView(base.resizable().aspectRatio(contentMode: .fit))
                case .scaleAspectFill: inner = AnyView(base.resizable().aspectRatio(contentMode: .fill).clipped())
                case .scaleToFill, .redraw: inner = AnyView(base.resizable())
                default: inner = AnyView(base)
                }
                if let tint = imageView.tintColor, image.renderingMode == .alwaysTemplate || image.isSymbolImage {
                    inner = AnyView(inner!.foregroundStyle(Color(uiColor: tint)))
                }
            } else {
                inner = AnyView(Color.clear)
            }
        case let label as UILabel:
            let text = label.attributedText?.string ?? label.text ?? ""
            let alignment: TextAlignment = label.textAlignment == .center ? .center : label.textAlignment == .right ? .trailing : .leading
            inner = AnyView(Text(text)
                .font(Font(label.font ?? .systemFont(ofSize: 17)))
                .foregroundStyle(color(label.textColor) ?? .primary)
                .multilineTextAlignment(alignment)
                .lineLimit(label.numberOfLines == 0 ? nil : label.numberOfLines)
                .minimumScaleFactor(label.adjustsFontSizeToFitWidth ? max(label.minimumScaleFactor, 0.01) : 1)
                .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading))
        case let spinner as UIActivityIndicatorView:
            if !spinner.isAnimating && spinner.hidesWhenStopped {
                inner = AnyView(Color.clear)
            } else {
                inner = AnyView(ProgressView().controlSize(spinner.style == .large ? .large : .regular).tint(color(spinner.color)))
            }
        case let effectView as UIVisualEffectView:
            let material: Material
            if let blur = effectView.effect as? UIBlurEffect {
                switch blur.style {
                case .systemUltraThinMaterial, .systemUltraThinMaterialLight, .systemUltraThinMaterialDark: material = .ultraThinMaterial
                case .systemThinMaterial, .systemThinMaterialLight, .systemThinMaterialDark, .light, .extraLight: material = .thinMaterial
                case .systemThickMaterial, .systemThickMaterialLight, .systemThickMaterialDark, .prominent: material = .thickMaterial
                case .systemChromeMaterial, .systemChromeMaterialLight, .systemChromeMaterialDark: material = .bar
                default: material = .regularMaterial
                }
            } else {
                material = .ultraThinMaterial
            }
            inner = AnyView(Rectangle().fill(material))
            if !effectView.contentView.subviews.isEmpty {
                ShimDiagnostics.warn("\(representable): the subviews of a UIVisualEffectView are not drawn, only its material")
            }
        default:
            // A plain view with nothing but a background (or nothing at all) can be drawn as that.
            guard type(of: view) == UIView.self, view.subviews.isEmpty else { return nil }
            inner = AnyView(Color.clear)
        }
        var result = inner!
        if let background = color(view.backgroundColor) { result = AnyView(result.background(background)) }
        if view.layer.cornerRadius > 0 {
            let shape = RoundedRectangle(cornerRadius: view.layer.cornerRadius, style: view.layer.cornerCurve == .continuous ? .continuous : .circular)
            result = AnyView(result.clipShape(shape))
            if view.layer.borderWidth > 0, let border = view.layer.borderColor {
                result = AnyView(result.overlay(shape.strokeBorder(Color(cgColor: border), lineWidth: view.layer.borderWidth)))
            }
        } else if view.layer.borderWidth > 0, let border = view.layer.borderColor {
            result = AnyView(result.overlay(Rectangle().strokeBorder(Color(cgColor: border), lineWidth: view.layer.borderWidth)))
        }
        if view.alpha < 1 { result = AnyView(result.opacity(Double(view.alpha))) }
        if let width = view.fixedDimension(.width) { result = AnyView(result.frame(width: width)) }
        if let height = view.fixedDimension(.height) { result = AnyView(result.frame(height: height)) }
        return result
    }
}

/// Lets the representable host read a hosting controller's root view without knowing its type.
protocol _AnyHostingController: AnyObject {
    var anyRootView: AnyView { get }
}
extension UIHostingController: _AnyHostingController {}

/// A UIKit view (in another framework's module, such as PassKit's buttons) that knows how to look:
/// a representable wrapping it draws this instead of a placeholder.
public protocol _SwiftUIDrawableView: UIView {
    @MainActor var _swiftUIRepresentation: AnyView { get }
}
