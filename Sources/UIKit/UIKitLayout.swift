// UIKit layout for a representable's view tree: autoresizing masks, a small Auto Layout solver, UIStackView
// arrangement and the fitting sizes they use. The representable host (UIKitViewTree.swift) sets the root
// view's frame to the size SwiftUI gives it and calls `layoutSubviews` top-down; app overrides of
// `layoutSubviews` run there, after `super`, as on iOS.
//
// The solver handles what most hand-written layouts use: equalities (any priority; a required one wins
// over an optional one, and the first of two conflicting ones wins) between a view's subviews, its own
// layout guides and the view itself, with constants and multipliers; a size from the subview's fitting
// size (intrinsicContentSize, a label wrapped at its solved width) when only a position is pinned; and
// inequalities that bound an edge or a size. It is not a linear-programming solver: a subview whose frame
// these rules leave undetermined is recorded in `_UIKitLayout.unsolved`, and the host draws a placeholder.

import Foundation
import SwiftUI

@MainActor
enum _UIKitLayout {
    /// Views whose Auto Layout frame could not be determined, since the last reset.
    static var unsolved: [UIView] = []
}

extension UIView {
    /// `layoutMargins`, or `directionalLayoutMargins` when only that was changed (left to right).
    var _effectiveLayoutMargins: UIEdgeInsets {
        let standard = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        if layoutMargins != standard { return layoutMargins }
        let d = directionalLayoutMargins
        return UIEdgeInsets(top: d.top, left: d.leading, bottom: d.bottom, right: d.trailing)
    }

    /// Lays out this view's subviews, then each visible subview's own, top-down.
    func _layoutTree() {
        layoutSubviews()
        for sub in subviews where !sub.isHidden { sub._layoutTree() }
    }

    /// Moves and resizes subviews that use autoresizing masks after this view's size changed from `old`.
    func _autoresizeSubviews(from old: CGSize) {
        guard autoresizesSubviews else { return }
        for sub in subviews where sub.translatesAutoresizingMaskIntoConstraints && !sub.autoresizingMask.isEmpty {
            let mask = sub.autoresizingMask
            var f = sub.frame
            func adjust(_ delta: CGFloat, _ lead: inout CGFloat, _ size: inout CGFloat, total old: CGFloat,
                        _ flexLead: Bool, _ flexSize: Bool, _ flexTrail: Bool) {
                guard delta != 0, flexLead || flexSize || flexTrail else { return }
                let trail = old - lead - size
                let parts = [(flexLead, max(lead, 0)), (flexSize, max(size, 0)), (flexTrail, max(trail, 0))].filter(\.0)
                let sum = parts.reduce(0) { $0 + $1.1 }
                func share(_ part: CGFloat) -> CGFloat { sum > 0 ? delta * part / sum : delta / CGFloat(parts.count) }
                if flexLead { lead += share(max(lead, 0)) }
                if flexSize { size = max(0, size + share(max(size, 0))) }
            }
            adjust(frame.width - old.width, &f.origin.x, &f.size.width, total: old.width,
                   mask.contains(.flexibleLeftMargin), mask.contains(.flexibleWidth), mask.contains(.flexibleRightMargin))
            adjust(frame.height - old.height, &f.origin.y, &f.size.height, total: old.height,
                   mask.contains(.flexibleTopMargin), mask.contains(.flexibleHeight), mask.contains(.flexibleBottomMargin))
            sub.frame = f
        }
    }

    /// The size a view takes on its own, per dimension (nil where it has none): a constant width or height
    /// constraint, a stack view's arranged content, a label's text (wrapped at `width` when given), a
    /// button's title and image, or `intrinsicContentSize`.
    func _fittingSize(width: CGFloat? = nil) -> (width: CGFloat?, height: CGFloat?) {
        let fixedWidth = fixedDimension(.width), fixedHeight = fixedDimension(.height)
        var w: CGFloat?, h: CGFloat?
        switch self {
        case let stack as UIStackView:
            let s = stack._contentSize(width: fixedWidth ?? width)
            (w, h) = (s.width, s.height)
        case let label as UILabel:
            let s = label.sizeThatFits(CGSize(width: fixedWidth ?? width ?? 0, height: .greatestFiniteMagnitude))
            (w, h) = (s.width, s.height)
        case let button as UIButton:
            let s = button._contentSize
            (w, h) = (s.width, s.height)
        default:
            let intrinsic = intrinsicContentSize
            w = intrinsic.width >= 0 ? intrinsic.width : nil
            h = intrinsic.height >= 0 ? intrinsic.height : nil
        }
        return (fixedWidth ?? w, fixedHeight ?? h)
    }

    // MARK: Auto Layout

    /// Solves the constraints that place this view's Auto Layout subviews and its own layout guides.
    func _solveConstraints() {
        let arranged = Set(((self as? UIStackView)?.arrangedSubviews ?? []).map(ObjectIdentifier.init))
        let solving = subviews.filter { !$0.translatesAutoresizingMaskIntoConstraints && !arranged.contains(ObjectIdentifier($0)) }
        let guides = layoutGuides.filter { $0.kind == .own }
        guard !solving.isEmpty || !guides.isEmpty else { return }
        var solver = ConstraintSolver(container: self)
        for view in solving { solver.addUnknown(view, view: view) }
        for guide in guides { solver.addUnknown(guide, view: nil) }
        var seen = Set<ObjectIdentifier>()
        for constraint in constraints + subviews.flatMap(\.constraints) where seen.insert(ObjectIdentifier(constraint)).inserted {
            solver.add(constraint)
        }
        solver.solve()
        for (object, frame) in solver.frames {
            if let view = object as? UIView { view.frame = frame } else if let guide = object as? UILayoutGuide { guide.solvedFrame = frame }
        }
        _UIKitLayout.unsolved += solver.unsolvedViews
    }
}

/// One axis of an unknown item's frame: any two of its edges, centre and size give the rest.
private struct AxisValues {
    var lo: CGFloat?, hi: CGFloat?, mid: CGFloat?, size: CGFloat?
    var isComplete: Bool { lo != nil && size != nil }
    var hasPosition: Bool { lo != nil || hi != nil || mid != nil }

    mutating func derive() {
        for _ in 0..<2 {
            if let lo, let size { hi = hi ?? lo + size; mid = mid ?? lo + size / 2 }
            if let hi, let size { lo = lo ?? hi - size; mid = mid ?? hi - size / 2 }
            if let mid, let size { lo = lo ?? mid - size / 2; hi = hi ?? mid + size / 2 }
            if let lo, let hi { size = size ?? hi - lo; mid = mid ?? (lo + hi) / 2 }
            if let lo, let mid { size = size ?? 2 * (mid - lo) }
            if let hi, let mid { size = size ?? 2 * (hi - mid) }
        }
    }
    enum Slot { case lo, hi, mid, size }
    func value(_ slot: Slot) -> CGFloat? {
        switch slot { case .lo: lo; case .hi: hi; case .mid: mid; case .size: size }
    }
    /// Sets a slot that is still open; false when it was already known.
    mutating func set(_ slot: Slot, _ value: CGFloat) -> Bool {
        guard self.value(slot) == nil, value.isFinite else { return false }
        switch slot { case .lo: lo = value; case .hi: hi = value; case .mid: mid = value; case .size: size = max(0, value) }
        derive()
        return true
    }
}

@MainActor
private struct ConstraintSolver {
    final class Item {
        let object: AnyObject
        let view: UIView?
        var x = AxisValues(), y = AxisValues()
        let known: Bool
        let margins: UIEdgeInsets
        init(object: AnyObject, view: UIView?, frame: CGRect?, margins: UIEdgeInsets) {
            self.object = object
            self.view = view
            self.margins = margins
            known = frame != nil
            if let f = frame {
                x = AxisValues(lo: f.minX, hi: f.maxX, mid: f.midX, size: f.width)
                y = AxisValues(lo: f.minY, hi: f.maxY, mid: f.midY, size: f.height)
            }
        }
    }

    let container: UIView
    private var items: [ObjectIdentifier: Item] = [:]
    private var unknowns: [Item] = []
    private var equalities: [NSLayoutConstraint] = []
    private var inequalities: [NSLayoutConstraint] = []

    init(container: UIView) {
        self.container = container
        add(container, view: container, frame: container.bounds)
        for sub in container.subviews where sub.translatesAutoresizingMaskIntoConstraints { add(sub, view: sub, frame: sub.frame) }
        if let stack = container as? UIStackView { for sub in stack.arrangedSubviews { add(sub, view: sub, frame: sub.frame) } }
    }

    private mutating func add(_ object: AnyObject, view: UIView?, frame: CGRect?) {
        items[ObjectIdentifier(object)] = Item(object: object, view: view, frame: frame, margins: view?._effectiveLayoutMargins ?? .zero)
    }
    mutating func addUnknown(_ object: AnyObject, view: UIView?) {
        add(object, view: view, frame: nil)
        unknowns.append(items[ObjectIdentifier(object)]!)
    }

    /// The item a constraint names: one of ours, or one of the container's system guides (a known frame).
    private mutating func item(_ object: AnyObject) -> Item? {
        if let found = items[ObjectIdentifier(object)] { return found }
        if let guide = object as? UILayoutGuide, guide.owningView === container, guide.kind != .own {
            add(guide, view: nil, frame: guide.layoutFrame)
            return items[ObjectIdentifier(guide)]
        }
        return nil
    }

    mutating func add(_ constraint: NSLayoutConstraint) {
        // A second item that is gone (items are held weakly) leaves the constraint without meaning.
        guard let first = constraint.firstItem, let a = item(first),
              constraint.secondItem != nil || constraint.secondAttribute == .notAnAttribute else { return }
        if let second = constraint.secondItem { guard let b = item(second), !(a.known && b.known) else { return } } else if a.known { return }
        if constraint.relation == .equal { equalities.append(constraint) } else { inequalities.append(constraint) }
    }

    /// The axis, slot and offset from that slot an attribute reads on an item.
    private static func map(_ attribute: NSLayoutConstraint.Attribute, _ m: UIEdgeInsets) -> (vertical: Bool, slot: AxisValues.Slot, offset: CGFloat)? {
        switch attribute {
        case .left, .leading: (false, .lo, 0)
        case .right, .trailing: (false, .hi, 0)
        case .centerX: (false, .mid, 0)
        case .width: (false, .size, 0)
        case .top: (true, .lo, 0)
        case .bottom: (true, .hi, 0)
        case .centerY: (true, .mid, 0)
        case .height: (true, .size, 0)
        case .leftMargin, .leadingMargin: (false, .lo, m.left)
        case .rightMargin, .trailingMargin: (false, .hi, -m.right)
        case .centerXWithinMargins: (false, .mid, (m.left - m.right) / 2)
        case .topMargin: (true, .lo, m.top)
        case .bottomMargin: (true, .hi, -m.bottom)
        case .centerYWithinMargins: (true, .mid, (m.top - m.bottom) / 2)
        case .firstBaseline, .lastBaseline, .notAnAttribute: nil
        }
    }

    private func read(_ item: Item, _ attribute: NSLayoutConstraint.Attribute) -> CGFloat? {
        guard let (vertical, slot, offset) = Self.map(attribute, item.margins) else { return nil }
        return (vertical ? item.y : item.x).value(slot).map { $0 + offset }
    }
    private func write(_ item: Item, _ attribute: NSLayoutConstraint.Attribute, _ value: CGFloat) -> Bool {
        guard !item.known, let (vertical, slot, offset) = Self.map(attribute, item.margins) else { return false }
        return vertical ? item.y.set(slot, value - offset) : item.x.set(slot, value - offset)
    }

    /// Applies an equality in whichever direction has the unknown side; true when it set something.
    private func apply(_ c: NSLayoutConstraint) -> Bool {
        guard let a = items[ObjectIdentifier(c.firstItem!)] else { return false }
        guard let secondObject = c.secondItem else {
            return read(a, c.firstAttribute) == nil && write(a, c.firstAttribute, c.constant)
        }
        guard let b = items[ObjectIdentifier(secondObject)] else { return false }
        let av = read(a, c.firstAttribute), bv = read(b, c.secondAttribute)
        if av == nil, let bv { return write(a, c.firstAttribute, c.multiplier * bv + c.constant) }
        if bv == nil, let av, c.multiplier != 0 { return write(b, c.secondAttribute, (av - c.constant) / c.multiplier) }
        return false
    }

    private func propagate(_ constraints: [NSLayoutConstraint]) {
        var changed = true
        while changed {
            changed = false
            for c in constraints where apply(c) { changed = true }
        }
    }

    /// Moves the edge (or size) an inequality bounds back inside the bound, keeping the opposite edge.
    private func clamp(vertical: Bool) {
        for c in inequalities {
            guard let a = items[ObjectIdentifier(c.firstItem!)], !a.known,
                  let (axisVertical, slot, offset) = Self.map(c.firstAttribute, a.margins), axisVertical == vertical,
                  let current = read(a, c.firstAttribute) else { continue }
            let bound: CGFloat
            if let secondObject = c.secondItem {
                guard let b = items[ObjectIdentifier(secondObject)], let bv = read(b, c.secondAttribute) else { continue }
                bound = c.multiplier * bv + c.constant
            } else {
                bound = c.constant
            }
            guard c.relation == .lessThanOrEqual ? current > bound : current < bound else { continue }
            var axis = vertical ? a.y : a.x
            guard axis.isComplete, let lo = axis.lo, let hi = axis.hi else { continue }
            let target = bound - offset
            switch slot {
            case .lo: axis = AxisValues(lo: target, hi: hi, mid: nil, size: nil)
            case .hi: axis = AxisValues(lo: lo, hi: target, mid: nil, size: nil)
            case .size: axis = AxisValues(lo: lo, hi: nil, mid: nil, size: target)
            case .mid: axis = AxisValues(lo: nil, hi: nil, mid: target, size: hi - lo)
            }
            axis.derive()
            if vertical { a.y = axis } else { a.x = axis }
        }
    }

    func solve() {
        let required = equalities.filter { $0.priority >= .required }, optional = equalities.filter { $0.priority < .required }
        let all = required + optional.sorted { $0.priority > $1.priority }
        propagate(required)
        propagate(all)
        // Sizes from the views themselves where only a position is pinned: widths first, so a label's
        // height can follow the width it wraps at.
        for vertical in [false, true] {
            var changed = true
            while changed {
                changed = false
                for item in unknowns {
                    guard let view = item.view else { continue }
                    guard (vertical ? item.y : item.x).size == nil else { continue }
                    let fitting = view._fittingSize(width: item.x.isComplete ? item.x.size : nil)
                    guard let size = vertical ? fitting.height : fitting.width else { continue }
                    if vertical { _ = item.y.set(.size, size) } else { _ = item.x.set(.size, size) }
                    changed = true
                    propagate(all)
                }
            }
            clamp(vertical: vertical)
        }
    }

    var frames: [(AnyObject, CGRect)] {
        unknowns.compactMap { item in
            guard item.x.isComplete, item.y.isComplete, let x = item.x.lo, let w = item.x.size, let y = item.y.lo, let h = item.y.size else { return nil }
            return (item.object, CGRect(x: x, y: y, width: w, height: h))
        }
    }
    var unsolvedViews: [UIView] {
        unknowns.compactMap { $0.x.isComplete && $0.y.isComplete ? nil : $0.view }
    }
}

// MARK: - Stack views

extension UIStackView {
    private var visibleArranged: [UIView] { arrangedSubviews.filter { !$0.isHidden } }
    private var marginInsets: UIEdgeInsets { isLayoutMarginsRelativeArrangement ? _effectiveLayoutMargins : .zero }
    private func gaps(_ views: [UIView]) -> [CGFloat] {
        views.dropLast().map { view in
            let custom = customSpacing(after: view)
            return custom == UIStackView.spacingUseDefault ? spacing : custom
        }
    }

    /// The size of the arranged views laid out along the axis, with the spacing and margins.
    func _contentSize(width: CGFloat?) -> CGSize {
        let views = visibleArranged, m = marginInsets
        let spacingTotal = gaps(views).reduce(0, +)
        if axis == .horizontal {
            let sizes = views.map { $0._fittingSize() }
            return CGSize(width: sizes.reduce(0) { $0 + ($1.width ?? 0) } + spacingTotal + m.left + m.right,
                          height: (sizes.compactMap(\.height).max() ?? 0) + m.top + m.bottom)
        }
        let inner = width.map { $0 - m.left - m.right }
        let sizes = views.map { $0._fittingSize(width: alignment == .fill ? inner : nil) }
        return CGSize(width: (sizes.compactMap(\.width).max() ?? 0) + m.left + m.right,
                      height: sizes.reduce(0) { $0 + ($1.height ?? 0) } + spacingTotal + m.top + m.bottom)
    }

    /// Frames for the arranged views from the distribution and alignment.
    func _arrangeSubviews() {
        let views = visibleArranged
        guard !views.isEmpty else { return }
        let area = bounds.inset(by: marginInsets)
        let horizontal = axis == .horizontal
        let main = horizontal ? area.width : area.height, cross = horizontal ? area.height : area.width
        var gaps = gaps(views)
        let mainAxis: NSLayoutConstraint.Axis = horizontal ? .horizontal : .vertical
        let fits: [CGFloat?] = views.map { view in
            horizontal ? view._fittingSize().width : view._fittingSize(width: alignment == .fill ? cross : nil).height
        }
        var sizes = fits.map { $0 ?? 0 }
        let free = main - sizes.reduce(0, +) - gaps.reduce(0, +)

        switch distribution {
        case .fillEqually:
            let each = max(0, (main - gaps.reduce(0, +)) / CGFloat(views.count))
            sizes = Array(repeating: each, count: views.count)
        case .fillProportionally:
            let total = sizes.reduce(0, +)
            let available = max(0, main - gaps.reduce(0, +))
            sizes = total > 0 ? sizes.map { $0 * available / total } : Array(repeating: available / CGFloat(views.count), count: views.count)
        case .equalSpacing, .equalCentering:
            if views.count > 1, free > 0 { gaps = gaps.map { $0 + free / CGFloat(views.count - 1) } }
            else if free < 0 { shrink(&sizes, by: -free, views, mainAxis) }
        case .fill:
            if free > 0 {
                // Extra space goes to views with no size of their own, else to the one that hugs least.
                let flexible = fits.indices.filter { fits[$0] == nil }
                if !flexible.isEmpty {
                    for i in flexible { sizes[i] += free / CGFloat(flexible.count) }
                } else if let i = views.indices.min(by: { pick(views[$0].contentHuggingPriority(for: mainAxis), views[$1].contentHuggingPriority(for: mainAxis), $0, $1) }) {
                    sizes[i] += free
                }
            } else if free < 0 {
                shrink(&sizes, by: -free, views, mainAxis)
            }
        }

        if alignment == .firstBaseline || alignment == .lastBaseline {
            ShimDiagnostics.warn("UIStackView: baseline alignment is drawn centred")
        }
        var position = horizontal ? area.minX : area.minY
        for (i, view) in views.enumerated() {
            let length = sizes[i]
            var crossSize = cross
            if alignment != .fill {
                let fit = horizontal ? view._fittingSize(width: length).height : view._fittingSize().width
                crossSize = min(fit ?? cross, cross)
            }
            let crossStart = horizontal ? area.minY : area.minX
            let offset: CGFloat
            switch alignment {
            case .fill, .leading: offset = 0
            case .trailing: offset = cross - crossSize
            case .center, .firstBaseline, .lastBaseline: offset = (cross - crossSize) / 2
            }
            view.frame = horizontal
                ? CGRect(x: position, y: crossStart + offset, width: length, height: crossSize)
                : CGRect(x: crossStart + offset, y: position, width: crossSize, height: length)
            position += length + (i < gaps.count ? gaps[i] : 0)
        }
    }

    /// Orders by priority, the later view first on a tie (the one UIKit tends to stretch or squeeze).
    private func pick(_ a: UILayoutPriority, _ b: UILayoutPriority, _ i: Int, _ j: Int) -> Bool { a == b ? i > j : a < b }

    private func shrink(_ sizes: inout [CGFloat], by amount: CGFloat, _ views: [UIView], _ axis: NSLayoutConstraint.Axis) {
        var remaining = amount
        let order = views.indices.sorted { pick(views[$0].contentCompressionResistancePriority(for: axis), views[$1].contentCompressionResistancePriority(for: axis), $0, $1) }
        for i in order where remaining > 0 {
            let cut = min(sizes[i], remaining)
            sizes[i] -= cut
            remaining -= cut
        }
    }
}

// MARK: - Buttons

extension UIButton {
    /// Title and image with the content insets, the size a button takes on its own.
    var _contentSize: CGSize {
        let title = currentTitle.map { ($0 as NSString).size(withAttributes: [.font: titleLabel?.font ?? UIFont.systemFont(ofSize: 17)]) } ?? .zero
        let image = currentImage?.size ?? .zero
        let gap: CGFloat = title.width > 0 && image.width > 0 ? (configuration?.imagePadding ?? 0) : 0
        let insets: (h: CGFloat, v: CGFloat)
        if let configuration {
            insets = (configuration.contentInsets.leading + configuration.contentInsets.trailing, configuration.contentInsets.top + configuration.contentInsets.bottom)
        } else {
            insets = (contentEdgeInsets.left + contentEdgeInsets.right, contentEdgeInsets.top + contentEdgeInsets.bottom)
        }
        return CGSize(width: (title.width + image.width + gap + insets.h).rounded(.up), height: (max(title.height, image.height) + insets.v).rounded(.up))
    }
}
