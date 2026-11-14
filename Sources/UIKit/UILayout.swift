// Auto Layout as record keeping: constraints can be created, activated and inspected, and nothing
// solves them. The representable host reads the simple ones (a constant width or height) when it
// draws a UIKit view; everything else is laid out by SwiftUI around the view.

import Foundation
import SwiftUI

@MainActor
open class NSLayoutConstraint: NSObject {
    public enum Attribute: Int, Sendable {
        case notAnAttribute = 0, left, right, top, bottom, leading, trailing, width, height, centerX, centerY, lastBaseline, firstBaseline
        case leftMargin, rightMargin, topMargin, bottomMargin, leadingMargin, trailingMargin, centerXWithinMargins, centerYWithinMargins
    }
    public enum Relation: Int, Sendable { case lessThanOrEqual = -1, equal = 0, greaterThanOrEqual = 1 }
    public enum Axis: Int, Sendable { case horizontal, vertical }
    public struct FormatOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let alignAllLeft = FormatOptions(rawValue: 1 << 1)
        public static let alignAllRight = FormatOptions(rawValue: 1 << 2)
        public static let alignAllTop = FormatOptions(rawValue: 1 << 3)
        public static let alignAllBottom = FormatOptions(rawValue: 1 << 4)
        public static let alignAllLeading = FormatOptions(rawValue: 1 << 5)
        public static let alignAllTrailing = FormatOptions(rawValue: 1 << 6)
        public static let alignAllCenterX = FormatOptions(rawValue: 1 << 9)
        public static let alignAllCenterY = FormatOptions(rawValue: 1 << 10)
    }

    public private(set) weak var firstItem: AnyObject?
    public private(set) weak var secondItem: AnyObject?
    public let firstAttribute: Attribute
    public let secondAttribute: Attribute
    public let relation: Relation
    public let multiplier: CGFloat
    public var constant: CGFloat
    public var priority = UILayoutPriority.required
    public var identifier: String?
    public var shouldBeArchived = false
    public var isActive = false {
        didSet {
            guard isActive != oldValue, let view = firstItem as? UIView else { return }
            if isActive { view.constraints.append(self) } else { view.constraints.removeAll { $0 === self } }
        }
    }

    public init(item view1: Any, attribute attr1: Attribute, relatedBy relation: Relation, toItem view2: Any?, attribute attr2: Attribute,
                multiplier: CGFloat, constant c: CGFloat) {
        firstItem = view1 as AnyObject
        secondItem = view2.map { $0 as AnyObject }
        firstAttribute = attr1
        secondAttribute = attr2
        self.relation = relation
        self.multiplier = multiplier
        constant = c
        super.init()
    }

    public class func activate(_ constraints: [NSLayoutConstraint]) { constraints.forEach { $0.isActive = true } }
    public class func deactivate(_ constraints: [NSLayoutConstraint]) { constraints.forEach { $0.isActive = false } }
    /// The visual format language is not parsed: no constraints result.
    public class func constraints(withVisualFormat format: String, options: FormatOptions = [], metrics: [String: Any]?, views: [String: Any]) -> [NSLayoutConstraint] { [] }
}

@MainActor
open class NSLayoutAnchor<AnchorType: AnyObject>: NSObject {
    weak var item: AnyObject?
    let attribute: NSLayoutConstraint.Attribute
    init(item: AnyObject?, attribute: NSLayoutConstraint.Attribute) {
        self.item = item
        self.attribute = attribute
        super.init()
    }
    func make(_ relation: NSLayoutConstraint.Relation, _ other: NSLayoutAnchor<AnchorType>?, multiplier: CGFloat = 1, constant: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(item: item as Any, attribute: attribute, relatedBy: relation, toItem: other?.item, attribute: other?.attribute ?? .notAnAttribute,
                           multiplier: multiplier, constant: constant)
    }
    public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.equal, anchor) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.greaterThanOrEqual, anchor) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.lessThanOrEqual, anchor) }
    public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.equal, anchor, constant: c) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, anchor, constant: c)
    }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, anchor, constant: c)
    }
}

open class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {
    public func anchorWithOffset(to otherAnchor: NSLayoutXAxisAnchor) -> NSLayoutDimension { NSLayoutDimension(item: item, attribute: .width) }
    public func constraint(equalToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.equal, anchor, constant: 8 * multiplier)
    }
    public func constraint(greaterThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, anchor, constant: 8 * multiplier)
    }
    public func constraint(lessThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, anchor, constant: 8 * multiplier)
    }
}
open class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {
    public func anchorWithOffset(to otherAnchor: NSLayoutYAxisAnchor) -> NSLayoutDimension { NSLayoutDimension(item: item, attribute: .height) }
    public func constraint(equalToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.equal, anchor, constant: 8 * multiplier)
    }
    public func constraint(greaterThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, anchor, constant: 8 * multiplier)
    }
    public func constraint(lessThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, anchor, constant: 8 * multiplier)
    }
}
open class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { make(.equal, nil, constant: c) }
    public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, nil, constant: c) }
    public func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, nil, constant: c) }
    public func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.equal, anchor, multiplier: m) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, anchor, multiplier: m) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, anchor, multiplier: m) }
    public func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint {
        make(.equal, anchor, multiplier: m, constant: c)
    }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, anchor, multiplier: m, constant: c)
    }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, anchor, multiplier: m, constant: c)
    }
}

/// The anchors a view and a layout guide share.
@MainActor public protocol _UILayoutAnchored: AnyObject {}
extension _UILayoutAnchored {
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .left) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .right) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }
}

@MainActor
open class UILayoutGuide: NSObject, _UILayoutAnchored {
    public var identifier = ""
    public internal(set) weak var owningView: UIView?
    public var layoutFrame: CGRect { owningView?.bounds ?? .zero }
    public override init() { super.init() }
    init(owner: UIView) { owningView = owner; super.init() }
}
open class UITrackingLayoutGuide: UILayoutGuide {}
open class UIKeyboardLayoutGuide: UITrackingLayoutGuide {
    public var followsUndockedKeyboard = false
    public var usesBottomSafeArea = true
}
