@_exported import Foundation
@_exported import CoreGraphics

// CGVector, CGAffineTransform and `applying(_:)` live in the CoreGraphics module, which SwiftUI re-exports.

extension CGPoint {
    static func + (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x - r.x, y: l.y - r.y) }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
    func inset(by i: EdgeInsets) -> CGRect {
        CGRect(x: minX + i.leading, y: minY + i.top,
               width: max(0, width - i.leading - i.trailing), height: max(0, height - i.top - i.bottom))
    }
    func outset(by i: EdgeInsets) -> CGRect {
        CGRect(x: minX - i.leading, y: minY - i.top,
               width: width + i.leading + i.trailing, height: height + i.top + i.bottom)
    }
}

// MARK: - SwiftUI geometry

public enum Axis: Int8, CaseIterable, Hashable, Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
    var cross: Axis { self == .horizontal ? .vertical : .horizontal }
}

public enum Edge: Int8, CaseIterable, Hashable, Sendable {
    case top, leading, bottom, trailing
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ e: Edge) { self.rawValue = 1 << e.rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
    }
}

public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
    case leading, trailing
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let leading = Set(rawValue: 1)
        public static let trailing = Set(rawValue: 2)
        public static let all: Set = [.leading, .trailing]
    }
}

public enum VerticalEdge: Int8, CaseIterable, Hashable, Sendable {
    case top, bottom
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let bottom = Set(rawValue: 2)
        public static let all: Set = [.top, .bottom]
    }
}

public struct EdgeInsets: Hashable, Sendable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init() { top = 0; leading = 0; bottom = 0; trailing = 0 }
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    init(all v: CGFloat) { self.init(top: v, leading: v, bottom: v, trailing: v) }
    init(_ edges: Edge.Set, _ v: CGFloat) {
        self.init(top: edges.contains(.top) ? v : 0, leading: edges.contains(.leading) ? v : 0,
                  bottom: edges.contains(.bottom) ? v : 0, trailing: edges.contains(.trailing) ? v : 0)
    }
    static let zero = EdgeInsets()
    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }
    func only(_ edges: Edge.Set) -> EdgeInsets {
        EdgeInsets(top: edges.contains(.top) ? top : 0, leading: edges.contains(.leading) ? leading : 0,
                   bottom: edges.contains(.bottom) ? bottom : 0, trailing: edges.contains(.trailing) ? trailing : 0)
    }
}

public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double
    public var degrees: Double {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }
    public init() { radians = 0 }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { self.radians = degrees * .pi / 180 }
    public static func radians(_ r: Double) -> Angle { Angle(radians: r) }
    public static func degrees(_ d: Double) -> Angle { Angle(degrees: d) }
    public static let zero = Angle()
    public static func < (l: Angle, r: Angle) -> Bool { l.radians < r.radians }
    public static func + (l: Angle, r: Angle) -> Angle { Angle(radians: l.radians + r.radians) }
    public static func - (l: Angle, r: Angle) -> Angle { Angle(radians: l.radians - r.radians) }
    public static func * (l: Angle, r: Double) -> Angle { Angle(radians: l.radians * r) }
    public static func / (l: Angle, r: Double) -> Angle { Angle(radians: l.radians / r) }
    public static prefix func - (a: Angle) -> Angle { Angle(radians: -a.radians) }
    public static func += (l: inout Angle, r: Angle) { l = l + r }
    public static func -= (l: inout Angle, r: Angle) { l = l - r }
}

public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat, y: CGFloat
    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
    func point(in r: CGRect) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
}

public struct ProposedViewSize: Hashable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?
    public init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
    public init(_ size: CGSize) { width = size.width; height = size.height }
    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)
    public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }
    subscript(axis: Axis) -> CGFloat? {
        get { axis == .horizontal ? width : height }
        set { if axis == .horizontal { width = newValue } else { height = newValue } }
    }
    init(axis: Axis, main: CGFloat?, cross: CGFloat?) {
        self = axis == .horizontal ? .init(width: main, height: cross) : .init(width: cross, height: main)
    }
}

extension CGSize {
    subscript(axis: Axis) -> CGFloat {
        get { axis == .horizontal ? width : height }
        set { if axis == .horizontal { width = newValue } else { height = newValue } }
    }
    init(axis: Axis, main: CGFloat, cross: CGFloat) {
        self = axis == .horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
    }
}

extension CGPoint {
    subscript(axis: Axis) -> CGFloat {
        get { axis == .horizontal ? x : y }
        set { if axis == .horizontal { x = newValue } else { y = newValue } }
    }
    init(axis: Axis, main: CGFloat, cross: CGFloat) {
        self = axis == .horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
    }
}

public enum LayoutDirection: Hashable, CaseIterable, Sendable { case leftToRight, rightToLeft }
public enum ColorScheme: Hashable, CaseIterable, Sendable { case light, dark }
public enum ColorSchemeContrast: Hashable, CaseIterable, Sendable { case standard, increased }
public enum UserInterfaceSizeClass: Hashable, Sendable { case compact, regular }
public enum ControlSize: Hashable, CaseIterable, Sendable { case mini, small, regular, large, extraLarge }
public enum TextAlignment: Hashable, CaseIterable, Sendable { case leading, center, trailing }
public enum ContentMode: Hashable, CaseIterable, Sendable { case fit, fill }
