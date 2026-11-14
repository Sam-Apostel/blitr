// UIKit's geometry and layout value types.

import Foundation
import SwiftUI

public struct UIEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init() { top = 0; left = 0; bottom = 0; right = 0 }
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static let zero = UIEdgeInsets()
}

public struct NSDirectionalEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init() { top = 0; leading = 0; bottom = 0; trailing = 0 }
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public static let zero = NSDirectionalEdgeInsets()
}

extension EdgeInsets {
    public init(_ insets: NSDirectionalEdgeInsets) {
        self.init(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }
}
extension NSDirectionalEdgeInsets {
    public init(_ insets: EdgeInsets) { self.init(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing) }
}
extension UIEdgeInsets {
    public init(_ insets: EdgeInsets, layoutDirection: LayoutDirection) {
        let rtl = layoutDirection == .rightToLeft
        self.init(top: insets.top, left: rtl ? insets.trailing : insets.leading, bottom: insets.bottom, right: rtl ? insets.leading : insets.trailing)
    }
}

extension CGRect {
    /// The rectangle made smaller by the insets (negative insets grow it).
    public func inset(by insets: UIEdgeInsets) -> CGRect {
        CGRect(x: minX + insets.left, y: minY + insets.top, width: width - insets.left - insets.right, height: height - insets.top - insets.bottom)
    }
}

public struct UIOffset: Equatable, Hashable, Sendable {
    public var horizontal: CGFloat, vertical: CGFloat
    public init() { horizontal = 0; vertical = 0 }
    public init(horizontal: CGFloat, vertical: CGFloat) { self.horizontal = horizontal; self.vertical = vertical }
    public static let zero = UIOffset()
}

public struct UIRectEdge: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = UIRectEdge(rawValue: 1)
    public static let left = UIRectEdge(rawValue: 2)
    public static let bottom = UIRectEdge(rawValue: 4)
    public static let right = UIRectEdge(rawValue: 8)
    public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}
public struct NSDirectionalRectEdge: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = NSDirectionalRectEdge(rawValue: 1)
    public static let leading = NSDirectionalRectEdge(rawValue: 2)
    public static let bottom = NSDirectionalRectEdge(rawValue: 4)
    public static let trailing = NSDirectionalRectEdge(rawValue: 8)
    public static let all: NSDirectionalRectEdge = [.top, .leading, .bottom, .trailing]
}
public struct UIRectCorner: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let topLeft = UIRectCorner(rawValue: 1)
    public static let topRight = UIRectCorner(rawValue: 2)
    public static let bottomLeft = UIRectCorner(rawValue: 4)
    public static let bottomRight = UIRectCorner(rawValue: 8)
    public static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
public struct UIAxis: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let horizontal = UIAxis(rawValue: 1)
    public static let vertical = UIAxis(rawValue: 2)
    public static let both: UIAxis = [.horizontal, .vertical]
}

public struct UILayoutPriority: RawRepresentable, Hashable, Comparable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, Sendable {
    public let rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public init(_ rawValue: Float) { self.rawValue = rawValue }
    public init(floatLiteral value: Float) { rawValue = value }
    public init(integerLiteral value: Int) { rawValue = Float(value) }
    public static let required = UILayoutPriority(1000)
    public static let defaultHigh = UILayoutPriority(750)
    public static let dragThatCanResizeScene = UILayoutPriority(510)
    public static let sceneSizeStayPut = UILayoutPriority(500)
    public static let dragThatCannotResizeScene = UILayoutPriority(490)
    public static let defaultLow = UILayoutPriority(250)
    public static let fittingSizeLevel = UILayoutPriority(50)
    public static func < (a: UILayoutPriority, b: UILayoutPriority) -> Bool { a.rawValue < b.rawValue }
    public static func + (a: UILayoutPriority, b: Float) -> UILayoutPriority { UILayoutPriority(a.rawValue + b) }
    public static func - (a: UILayoutPriority, b: Float) -> UILayoutPriority { UILayoutPriority(a.rawValue - b) }
}

public enum NSTextAlignment: Int, Sendable { case left, center, right, justified, natural }
public enum NSLineBreakMode: Int, Sendable { case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle }
public enum NSWritingDirection: Int, Sendable { case natural = -1, leftToRight, rightToLeft }

extension NSValue {
    public convenience init(cgRect: CGRect) { self.init(rect: NSRect(x: cgRect.minX, y: cgRect.minY, width: cgRect.width, height: cgRect.height)) }
    public convenience init(cgPoint: CGPoint) { self.init(point: NSPoint(x: cgPoint.x, y: cgPoint.y)) }
    public convenience init(cgSize: CGSize) { self.init(size: NSSize(width: cgSize.width, height: cgSize.height)) }
    public var cgRectValue: CGRect { rectValue }
    public var cgPointValue: CGPoint { pointValue }
    public var cgSizeValue: CGSize { sizeValue }
}

public func NSStringFromCGRect(_ rect: CGRect) -> String { "{{\(rect.minX), \(rect.minY)}, {\(rect.width), \(rect.height)}}" }
public func NSStringFromCGPoint(_ point: CGPoint) -> String { "{\(point.x), \(point.y)}" }
public func NSStringFromCGSize(_ size: CGSize) -> String { "{\(size.width), \(size.height)}" }
