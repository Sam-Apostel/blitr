// What a transition does to a view at a point of its insertion or removal, for the tweener.

protocol TransitionModelProvider { var model: TransitionModel { get } }

indirect enum TransitionModel: Sendable {
    case identity
    case opacity
    case scale(Double, UnitPoint)
    case move(Edge)
    case offset(CGSize)
    case push(Edge)
    case slide
    case blurReplace(upUp: Bool)
    case asymmetric(TransitionModel, TransitionModel)
    case combined(TransitionModel, TransitionModel)
    case animated(TransitionModel, Animation?)
    /// A transition the capture cannot interpolate (custom `Transition` bodies, `.modifier`): fades.
    case custom(String)

    static func of<T: Transition>(_ transition: T) -> TransitionModel {
        (transition as? TransitionModelProvider)?.model ?? .custom("\(T.self)")
    }

    /// The animation attached with `AnyTransition.animation(_:)`, if any (for this direction).
    func animation(insertion: Bool) -> Animation?? {
        switch self {
        case .animated(_, let a): return .some(a)
        case .asymmetric(let i, let r): return (insertion ? i : r).animation(insertion: insertion)
        case .combined(let a, let b): return a.animation(insertion: insertion) ?? b.animation(insertion: insertion)
        default: return nil
        }
    }

    /// The model for one direction, with `.slide` and `.push` resolved to what they do in that direction.
    func resolved(insertion: Bool) -> TransitionModel {
        switch self {
        case .asymmetric(let i, let r): return (insertion ? i : r).resolved(insertion: insertion)
        case .combined(let a, let b): return .combined(a.resolved(insertion: insertion), b.resolved(insertion: insertion))
        case .animated(let m, _): return m.resolved(insertion: insertion)
        case .slide: return .move(insertion ? .leading : .trailing)
        case .push(let edge): return .combined(.move(insertion ? edge : edge.opposite), .opacity)
        default: return self
        }
    }

    var customName: String? {
        switch self {
        case .custom(let name): return name
        case .asymmetric(let a, let b), .combined(let a, let b): return a.customName ?? b.customName
        case .animated(let m, _): return m.customName
        default: return nil
        }
    }

    /// The effect at `visibility` (0: fully transitioned out, 1: identity) for a view of `size`.
    func effect(visibility v: Double, size: CGSize) -> TransitionEffect {
        var e = TransitionEffect()
        let hidden = 1 - v
        switch self {
        case .identity: break
        case .opacity, .custom: e.opacity = v
        case .scale(let s, let anchor):
            let k = s + (1 - s) * v
            e.scale = CGSize(width: k, height: k)
            e.anchor = anchor
        case .move(let edge):
            switch edge {
            case .top: e.offset.height = -size.height * hidden
            case .bottom: e.offset.height = size.height * hidden
            case .leading: e.offset.width = -size.width * hidden
            case .trailing: e.offset.width = size.width * hidden
            }
        case .offset(let o):
            e.offset = CGSize(width: o.width * hidden, height: o.height * hidden)
        case .blurReplace(let upUp):
            e.opacity = v
            e.blur = 10 * hidden
            let k = 1 - (upUp ? -0.1 : 0.2) * hidden
            e.scale = CGSize(width: k, height: k)
        case .combined(let a, let b):
            e = a.effect(visibility: v, size: size).combined(with: b.effect(visibility: v, size: size))
        case .asymmetric(let i, _): e = i.effect(visibility: v, size: size)
        case .animated(let m, _): e = m.effect(visibility: v, size: size)
        case .slide: e = TransitionModel.move(.leading).effect(visibility: v, size: size)
        case .push(let edge): e = TransitionModel.combined(.move(edge), .opacity).effect(visibility: v, size: size)
        }
        return e
    }
}

struct TransitionEffect {
    var opacity = 1.0
    var scale = CGSize(width: 1, height: 1)
    var anchor = UnitPoint.center
    var offset = CGSize.zero
    var blur: CGFloat = 0

    func combined(with o: TransitionEffect) -> TransitionEffect {
        var r = self
        r.opacity *= o.opacity
        r.scale = CGSize(width: scale.width * o.scale.width, height: scale.height * o.scale.height)
        if o.scale != CGSize(width: 1, height: 1) { r.anchor = o.anchor }
        r.offset = CGSize(width: offset.width + o.offset.width, height: offset.height + o.offset.height)
        r.blur = max(blur, o.blur)
        return r
    }

    var isIdentity: Bool { opacity >= 1 && scale == CGSize(width: 1, height: 1) && offset == .zero && blur <= 0 }

    /// Draws `draw` (in a view of `size`) through the effect.
    @MainActor func apply(_ p: Painter, size: CGSize, _ draw: () -> Void) {
        guard opacity > 0.001 else { return }
        p.save()
        p.translate(offset.width, offset.height)
        if scale != CGSize(width: 1, height: 1) {
            let a = anchor.point(in: CGRect(origin: .zero, size: size))
            p.translate(a.x, a.y)
            p.scale(max(scale.width, 0.0001), max(scale.height, 0.0001))
            p.translate(-a.x, -a.y)
        }
        var layers = 0
        if blur > 0.05 { p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: blur, scale: p.scale))); layers += 1 }
        if opacity < 0.999 { p.saveLayer(.init(opacity: opacity)); layers += 1 }
        draw()
        for _ in 0..<layers { p.restore() }
        p.restore()
    }
}

extension Edge {
    var opposite: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}
