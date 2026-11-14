// TipView and popoverTip: Apple's tip card, drawn when the tip displays (see TipKit.swift for when).
import SwiftUI

// MARK: - Style

public struct TipViewStyleConfiguration {
    public let tip: any Tip
    public let actions: [Tips.Action]
    let action: @MainActor @Sendable (Tips.Action) -> Void
}

@MainActor @preconcurrency
public protocol TipViewStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = TipViewStyleConfiguration
}

/// The standard card: icon, title, message, close button and actions.
public struct _DefaultTipViewStyle: TipViewStyle {
    public init() {}
    public func makeBody(configuration: TipViewStyleConfiguration) -> some View { TipCard(configuration: configuration, mini: false) }
}
/// iOS 18: a compact card without the actions' divider.
public struct MiniTipViewStyle: TipViewStyle {
    public init() {}
    public func makeBody(configuration: TipViewStyleConfiguration) -> some View { TipCard(configuration: configuration, mini: true) }
}
extension TipViewStyle where Self == MiniTipViewStyle {
    public static var miniTip: MiniTipViewStyle { MiniTipViewStyle() }
}

struct TipStyleBox { let make: @MainActor (TipViewStyleConfiguration) -> AnyView }

struct TipLook {
    var background: AnyShapeStyle?
    var cornerRadius: CGFloat?
    var imageSize: CGSize?
    var imageStyle: AnyShapeStyle?
    var style: TipStyleBox?
}
enum TipLookKey: EnvironmentKey { static let defaultValue = TipLook() }
extension EnvironmentValues {
    var tipLook: TipLook {
        get { self[TipLookKey.self] }
        set { self[TipLookKey.self] = newValue }
    }
}

struct _TipStyleApplier<S: TipViewStyle>: View {
    let style: S
    let configuration: TipViewStyleConfiguration
    var body: some View { style.makeBody(configuration: configuration) }
}

extension View {
    public func tipViewStyle(_ style: some TipViewStyle) -> some View {
        environment(\.tipLook.style, TipStyleBox { AnyView(_TipStyleApplier(style: style, configuration: $0)) })
    }
    public func tipBackground(_ style: some ShapeStyle) -> some View { environment(\.tipLook.background, AnyShapeStyle(style)) }
    public func tipCornerRadius(_ cornerRadius: CGFloat, antialiased: Bool = true) -> some View {
        environment(\.tipLook.cornerRadius, cornerRadius)
    }
    public func tipImageSize(_ size: CGSize) -> some View { environment(\.tipLook.imageSize, size) }
    public func tipImageStyle(_ style: some ShapeStyle) -> some View { environment(\.tipLook.imageStyle, AnyShapeStyle(style)) }
    public func tipImageStyle(_ primary: some ShapeStyle, _ secondary: some ShapeStyle) -> some View {
        environment(\.tipLook.imageStyle, AnyShapeStyle(primary))
    }
    public func tipImageStyle(_ primary: some ShapeStyle, _ secondary: some ShapeStyle, _ tertiary: some ShapeStyle) -> some View {
        environment(\.tipLook.imageStyle, AnyShapeStyle(primary))
    }
}

// MARK: - Card

/// The tip card (iOS 17/18 metrics, estimated from the system's TipView).
struct TipCard: View {
    let configuration: TipViewStyleConfiguration
    let mini: Bool
    @Environment(\.tipLook) private var look

    var body: some View {
        let tip = configuration.tip
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let image = tip.image {
                    image.resizable().scaledToFit()
                        .frame(width: look.imageSize?.width ?? 35, height: look.imageSize?.height ?? 35)
                        .foregroundStyle(look.imageStyle ?? AnyShapeStyle(Color.accentColor))
                }
                VStack(alignment: .leading, spacing: 4) {
                    tip.title.font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let message = tip.message {
                        message.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            if !configuration.actions.isEmpty {
                if !mini { Divider().padding(.top, 12) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(configuration.actions.enumerated()), id: \.offset) { pair in
                        if pair.offset > 0 && !mini { Divider() }
                        let action = pair.element
                        Button { configuration.action(action) } label: { action.label() }
                            .foregroundStyle(Color.accentColor)
                            .padding(.vertical, mini ? 4 : 10)
                    }
                }
                .padding(.leading, tip.image == nil ? 0 : 47)
                .padding(.bottom, mini ? 0 : -6)
            }
        }
        .padding(16)
    }
}

/// The card with its background and shape; `arrowEdge` (inline tip views) draws an arrow on that edge.
struct TipChrome: View {
    let tip: any Tip
    let arrowEdge: Edge?
    let popover: Bool
    let action: @MainActor @Sendable (Tips.Action) -> Void
    @Environment(\.tipLook) private var look

    var body: some View {
        let configuration = TipViewStyleConfiguration(tip: tip, actions: tip.actions, action: action)
        let radius = look.cornerRadius ?? 13
        let fill = look.background ?? AnyShapeStyle(popover ? Color(SystemColor.tertiaryBackground) : Color(SystemColor.secondaryBackground))
        let card = Group {
            if let style = look.style { style.make(configuration) } else { TipCard(configuration: configuration, mini: false) }
        }
        .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: popover ? Color.black.opacity(0.12) : .clear, radius: popover ? 12 : 0, y: popover ? 4 : 0)
        if let arrowEdge, !popover {
            card.padding(EdgeInsets(arrowEdge, 10)).overlay(alignment: Alignment(arrowEdge)) {
                TipArrow(edge: arrowEdge).fill(fill).frame(width: arrowEdge == .top || arrowEdge == .bottom ? 22 : 10,
                                                          height: arrowEdge == .top || arrowEdge == .bottom ? 10 : 22)
            }
        } else {
            card
        }
    }
}

struct TipArrow: Shape {
    let edge: Edge
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        switch edge {
        case .top: p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .bottom: p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        case .leading: p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .trailing: p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

extension EdgeInsets {
    init(_ edge: Edge, _ length: CGFloat) {
        self.init(top: edge == .top ? length : 0, leading: edge == .leading ? length : 0,
                  bottom: edge == .bottom ? length : 0, trailing: edge == .trailing ? length : 0)
    }
}
extension Alignment {
    init(_ edge: Edge) {
        switch edge {
        case .top: self = .top
        case .bottom: self = .bottom
        case .leading: self = .leading
        case .trailing: self = .trailing
        }
    }
}

// MARK: - TipView

@MainActor @preconcurrency
public struct TipView<Content: Tip>: View {
    let tip: (any Tip)?
    let arrowEdge: Edge?
    let isPresented: Binding<Bool>?
    let action: @MainActor @Sendable (Tips.Action) -> Void

    public init(_ tip: Content, arrowEdge: Edge? = nil, action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.isPresented = nil
        self.action = action
    }

    public var body: some View {
        if let tip, tip.shouldDisplay, isPresented?.wrappedValue ?? true {
            TipChrome(tip: tip, arrowEdge: arrowEdge, popover: false, action: action)
        }
    }
}

extension TipView where Content == AnyTip {
    public init(_ tip: (any Tip)?, arrowEdge: Edge? = nil, action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.isPresented = nil
        self.action = action
    }
    public init(_ tip: (any Tip)?, isPresented: Binding<Bool>?, arrowEdge: Edge? = nil,
                action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.isPresented = isPresented
        self.action = action
    }
    public init(_ tip: (any Tip)?, isPresented: Binding<Bool>?, arrowEdge: Edge? = nil, anchorID: String,
                action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.init(tip, isPresented: isPresented, arrowEdge: arrowEdge, action: action)
    }
}

// MARK: - popoverTip

extension View {
    /// When the tip displays, its card is drawn as a popover next to this view (below it unless `arrowEdge`
    /// says otherwise), on top of the layout.
    @preconcurrency
    public func popoverTip(_ tip: (any Tip)?, arrowEdge: Edge? = nil,
                           action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) -> some View {
        modifier(_PopoverTipModifier(tip: tip, isPresented: nil, arrowEdge: arrowEdge, action: action))
    }
    @preconcurrency
    public func popoverTip(_ tip: (any Tip)?, isPresented: Binding<Bool>? = nil, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                           arrowEdge: Edge? = nil, action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) -> some View {
        modifier(_PopoverTipModifier(tip: tip, isPresented: isPresented, arrowEdge: arrowEdge, action: action))
    }
}

struct _PopoverTipModifier: ViewModifier {
    let tip: (any Tip)?
    let isPresented: Binding<Bool>?
    let arrowEdge: Edge?
    let action: @MainActor @Sendable (Tips.Action) -> Void
    @Environment(\.tipLook) private var look

    func body(content: Content) -> some View {
        if let tip, tip.shouldDisplay, isPresented?.wrappedValue ?? true {
            // The arrow is on the card's edge that faces the view: `.top` puts the card below the view.
            let side: Edge = switch arrowEdge ?? .top {
            case .top: .bottom
            case .bottom: .top
            case .leading: .trailing
            case .trailing: .leading
            }
            let fill = look.background ?? AnyShapeStyle(Color(SystemColor.tertiaryBackground))
            _AnchoredOverlay(content: content, overlay: TipChrome(tip: tip, arrowEdge: nil, popover: true, action: action),
                             edge: side, width: 360, gap: 10, margin: 12, arrow: fill)
        } else {
            content
        }
    }
}
