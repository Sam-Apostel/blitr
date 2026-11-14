// UIView and gesture recognizers. Views are a tree of property stores: nothing lays them out or
// draws them on their own. A view wrapped in a UIViewRepresentable is drawn by the representable
// host (UIRepresentable.swift) from these properties.

import Foundation
import SwiftUI

open class UIView: UIResponder, _UILayoutAnchored, UITraitEnvironment, UICoordinateSpace {
    public enum ContentMode: Int, Sendable {
        case scaleToFill, scaleAspectFit, scaleAspectFill, redraw, center, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
    }
    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let flexibleLeftMargin = AutoresizingMask(rawValue: 1 << 0)
        public static let flexibleWidth = AutoresizingMask(rawValue: 1 << 1)
        public static let flexibleRightMargin = AutoresizingMask(rawValue: 1 << 2)
        public static let flexibleTopMargin = AutoresizingMask(rawValue: 1 << 3)
        public static let flexibleHeight = AutoresizingMask(rawValue: 1 << 4)
        public static let flexibleBottomMargin = AutoresizingMask(rawValue: 1 << 5)
    }
    public struct AnimationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let layoutSubviews = AnimationOptions(rawValue: 1 << 0)
        public static let allowUserInteraction = AnimationOptions(rawValue: 1 << 1)
        public static let beginFromCurrentState = AnimationOptions(rawValue: 1 << 2)
        public static let `repeat` = AnimationOptions(rawValue: 1 << 3)
        public static let autoreverse = AnimationOptions(rawValue: 1 << 4)
        public static let curveEaseInOut = AnimationOptions([])
        public static let curveEaseIn = AnimationOptions(rawValue: 1 << 16)
        public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16)
        public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
        public static let transitionFlipFromLeft = AnimationOptions(rawValue: 1 << 20)
        public static let transitionFlipFromRight = AnimationOptions(rawValue: 2 << 20)
        public static let transitionCurlUp = AnimationOptions(rawValue: 3 << 20)
        public static let transitionCurlDown = AnimationOptions(rawValue: 4 << 20)
        public static let transitionCrossDissolve = AnimationOptions(rawValue: 5 << 20)
        public static let transitionFlipFromTop = AnimationOptions(rawValue: 6 << 20)
        public static let transitionFlipFromBottom = AnimationOptions(rawValue: 7 << 20)
    }
    public enum AnimationCurve: Int, Sendable { case easeInOut, easeIn, easeOut, linear }
    public enum TintAdjustmentMode: Int, Sendable { case automatic, normal, dimmed }
    public static let noIntrinsicMetric: CGFloat = -1
    public static let layoutFittingCompressedSize = CGSize.zero
    public static let layoutFittingExpandedSize = CGSize(width: 10000, height: 10000)

    open var frame: CGRect = .zero
    open var bounds: CGRect {
        get { CGRect(origin: .zero, size: frame.size) }
        set { frame.size = newValue.size }
    }
    open var center: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set { frame.origin = CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2) }
    }
    open var transform = CGAffineTransform.identity
    open var backgroundColor: UIColor?
    open var tintColor: UIColor! = .tintColor
    open var tintAdjustmentMode = TintAdjustmentMode.automatic
    open var alpha: CGFloat = 1
    open var isHidden = false
    open var isOpaque = true
    open var clipsToBounds = false
    open var isUserInteractionEnabled = true
    open var isMultipleTouchEnabled = false
    open var isExclusiveTouch = false
    open var translatesAutoresizingMaskIntoConstraints = true
    open var autoresizingMask: AutoresizingMask = []
    open var autoresizesSubviews = true
    open var contentMode: ContentMode = .scaleToFill
    open var contentScaleFactor: CGFloat = 1
    open var tag = 0
    open var mask: UIView?
    open var layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    open var directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    open var preservesSuperviewLayoutMargins = false
    open var insetsLayoutMarginsFromSafeArea = true
    open var semanticContentAttribute = UISemanticContentAttribute.unspecified
    open var overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
    open var isAccessibilityElement = false
    open var accessibilityLabel: String?
    open var accessibilityHint: String?
    open var accessibilityValue: String?
    open var accessibilityIdentifier: String?
    open var accessibilityTraits: UIAccessibilityTraits = []
    open var accessibilityElementsHidden = false
    open var accessibilityViewIsModal = false
    open var showsLargeContentViewer = false
    open var largeContentTitle: String?
    open var largeContentImage: UIImage?
    open var interactions: [UIInteraction] = []
    open var gestureRecognizers: [UIGestureRecognizer]?
    public internal(set) var constraints: [NSLayoutConstraint] = []
    public private(set) var layoutGuides: [UILayoutGuide] = []
    /// Made on first use from `layerClass`.
    public private(set) lazy var layer: CALayer = (type(of: self).layerClass as? CALayer.Type)?.init() ?? CALayer()
    public private(set) var subviews: [UIView] = []
    public private(set) weak var superview: UIView?
    /// The controller whose `view` this is.
    weak var owningController: UIViewController?

    open class var layerClass: AnyClass { CALayer.self }

    public init(frame: CGRect) {
        self.frame = frame
        super.init()
    }
    public convenience override init() { self.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init() }

    // MARK: Hierarchy

    /// Never in a window: views are drawn through SwiftUI, not hosted by UIKit.
    open var window: UIWindow? { nil }
    open override var next: UIResponder? { owningController ?? superview }

    open func addSubview(_ view: UIView) { insertSubview(view, at: subviews.count) }
    open func insertSubview(_ view: UIView, at index: Int) {
        guard view !== self else { return }
        view.willMove(toSuperview: self)
        view.superview?.subviews.removeAll { $0 === view }
        view.superview = self
        subviews.insert(view, at: max(0, min(index, subviews.count)))
        view.didMoveToSuperview()
        didAddSubview(view)
    }
    open func insertSubview(_ view: UIView, aboveSubview sibling: UIView) {
        insertSubview(view, at: (subviews.firstIndex { $0 === sibling }).map { $0 + 1 } ?? subviews.count)
    }
    open func insertSubview(_ view: UIView, belowSubview sibling: UIView) {
        insertSubview(view, at: subviews.firstIndex { $0 === sibling } ?? 0)
    }
    open func bringSubviewToFront(_ view: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === view }) else { return }
        subviews.append(subviews.remove(at: index))
    }
    open func sendSubviewToBack(_ view: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === view }) else { return }
        subviews.insert(subviews.remove(at: index), at: 0)
    }
    open func exchangeSubview(at index1: Int, withSubviewAt index2: Int) {
        guard subviews.indices.contains(index1), subviews.indices.contains(index2) else { return }
        subviews.swapAt(index1, index2)
    }
    open func removeFromSuperview() {
        guard let parent = superview else { return }
        willMove(toSuperview: nil)
        parent.willRemoveSubview(self)
        parent.subviews.removeAll { $0 === self }
        superview = nil
        didMoveToSuperview()
    }
    open func isDescendant(of view: UIView) -> Bool {
        var current: UIView? = self
        while let c = current { if c === view { return true }; current = c.superview }
        return false
    }
    open func viewWithTag(_ tag: Int) -> UIView? {
        if self.tag == tag { return self }
        for child in subviews { if let found = child.viewWithTag(tag) { return found } }
        return nil
    }
    open func didAddSubview(_ subview: UIView) {}
    open func willRemoveSubview(_ subview: UIView) {}
    open func willMove(toSuperview newSuperview: UIView?) {}
    open func didMoveToSuperview() {}
    open func willMove(toWindow newWindow: UIWindow?) {}
    open func didMoveToWindow() {}

    // MARK: Layout

    open var safeAreaInsets: UIEdgeInsets { _currentSafeInsets() }
    public var safeAreaLayoutGuide: UILayoutGuide { UILayoutGuide(owner: self) }
    public var layoutMarginsGuide: UILayoutGuide { UILayoutGuide(owner: self) }
    public var readableContentGuide: UILayoutGuide { UILayoutGuide(owner: self) }
    public var keyboardLayoutGuide: UIKeyboardLayoutGuide { UIKeyboardLayoutGuide(owner: self) }
    public var firstBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .firstBaseline) }
    public var lastBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .lastBaseline) }
    open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    open var effectiveUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection { .leftToRight }
    open var traitCollection: UITraitCollection { .current }
    open var hasAmbiguousLayout: Bool { false }
    private var hugging: [Int: UILayoutPriority] = [:]
    private var resistance: [Int: UILayoutPriority] = [:]

    open func addLayoutGuide(_ layoutGuide: UILayoutGuide) { layoutGuide.owningView = self; layoutGuides.append(layoutGuide) }
    open func removeLayoutGuide(_ layoutGuide: UILayoutGuide) { layoutGuides.removeAll { $0 === layoutGuide } }
    open func addConstraint(_ constraint: NSLayoutConstraint) { constraint.isActive = true }
    open func addConstraints(_ constraints: [NSLayoutConstraint]) { NSLayoutConstraint.activate(constraints) }
    open func removeConstraint(_ constraint: NSLayoutConstraint) { constraint.isActive = false }
    open func removeConstraints(_ constraints: [NSLayoutConstraint]) { NSLayoutConstraint.deactivate(constraints) }
    open func layoutSubviews() {}
    open func setNeedsLayout() {}
    open func layoutIfNeeded() {}
    open func layoutMarginsDidChange() {}
    open func safeAreaInsetsDidChange() {}
    open func updateConstraints() {}
    open func updateConstraintsIfNeeded() {}
    open func setNeedsUpdateConstraints() {}
    open func invalidateIntrinsicContentSize() {}
    open func sizeThatFits(_ size: CGSize) -> CGSize {
        let intrinsic = intrinsicContentSize
        return CGSize(width: intrinsic.width >= 0 ? intrinsic.width : frame.width, height: intrinsic.height >= 0 ? intrinsic.height : frame.height)
    }
    open func sizeToFit() { frame.size = sizeThatFits(frame.size) }
    open func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize { sizeThatFits(targetSize) }
    open func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                      verticalFittingPriority: UILayoutPriority) -> CGSize { sizeThatFits(targetSize) }
    open func contentHuggingPriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { hugging[axis.rawValue] ?? .defaultLow }
    open func setContentHuggingPriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { hugging[axis.rawValue] = priority }
    open func contentCompressionResistancePriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { resistance[axis.rawValue] ?? .defaultHigh }
    open func setContentCompressionResistancePriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { resistance[axis.rawValue] = priority }

    /// A width or height pinned by an active constant constraint.
    func fixedDimension(_ attribute: NSLayoutConstraint.Attribute) -> CGFloat? {
        constraints.last { $0.firstAttribute == attribute && $0.secondItem == nil && $0.relation == .equal }?.constant
    }

    // MARK: Geometry

    private var originInRoot: CGPoint {
        var point = frame.origin
        var parent = superview
        while let p = parent { point.x += p.frame.minX; point.y += p.frame.minY; parent = p.superview }
        return point
    }
    open func convert(_ point: CGPoint, to view: UIView?) -> CGPoint {
        let (a, b) = (originInRoot, view?.originInRoot ?? .zero)
        return CGPoint(x: point.x + a.x - b.x, y: point.y + a.y - b.y)
    }
    open func convert(_ point: CGPoint, from view: UIView?) -> CGPoint {
        let (a, b) = (originInRoot, view?.originInRoot ?? .zero)
        return CGPoint(x: point.x + b.x - a.x, y: point.y + b.y - a.y)
    }
    open func convert(_ rect: CGRect, to view: UIView?) -> CGRect { CGRect(origin: convert(rect.origin, to: view), size: rect.size) }
    open func convert(_ rect: CGRect, from view: UIView?) -> CGRect { CGRect(origin: convert(rect.origin, from: view), size: rect.size) }
    open func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.contains(point) }
    open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, self.point(inside: point, with: event) else { return nil }
        for child in subviews.reversed() {
            if let hit = child.hitTest(CGPoint(x: point.x - child.frame.minX, y: point.y - child.frame.minY), with: event) { return hit }
        }
        return self
    }

    // MARK: Drawing

    /// Custom drawing: called by the representable host with a current graphics context.
    open func draw(_ rect: CGRect) {}
    open func setNeedsDisplay() {}
    open func setNeedsDisplay(_ rect: CGRect) {}
    open func tintColorDidChange() {}
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
    open func snapshotView(afterScreenUpdates afterUpdates: Bool) -> UIView? { nil }
    @discardableResult open func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool { false }
    open func addInteraction(_ interaction: UIInteraction) { interactions.append(interaction) }
    open func removeInteraction(_ interaction: UIInteraction) { interactions.removeAll { $0 === interaction } }
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        gestureRecognizer.view = self
        gestureRecognizers = (gestureRecognizers ?? []) + [gestureRecognizer]
    }
    open func removeGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        gestureRecognizers?.removeAll { $0 === gestureRecognizer }
        gestureRecognizer.view = nil
    }
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @discardableResult open func endEditing(_ force: Bool) -> Bool { true }
    open func accessibilityActivate() -> Bool { false }

    // MARK: Animation (changes apply at once)

    public class var areAnimationsEnabled: Bool { false }
    public class func setAnimationsEnabled(_ enabled: Bool) {}
    public class func performWithoutAnimation(_ actionsWithoutAnimation: () -> Void) { actionsWithoutAnimation() }
    public class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void) { animations() }
    public class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        animations()
        completion?(true)
    }
    public class func animate(withDuration duration: TimeInterval, delay: TimeInterval, options: AnimationOptions = [], animations: @escaping () -> Void,
                              completion: ((Bool) -> Void)? = nil) {
        animations()
        completion?(true)
    }
    public class func animate(withDuration duration: TimeInterval, delay: TimeInterval, usingSpringWithDamping dampingRatio: CGFloat,
                              initialSpringVelocity velocity: CGFloat, options: AnimationOptions = [], animations: @escaping () -> Void,
                              completion: ((Bool) -> Void)? = nil) {
        animations()
        completion?(true)
    }
    public class func animateKeyframes(withDuration duration: TimeInterval, delay: TimeInterval, options: AnimationOptions = [],
                                       animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        animations()
        completion?(true)
    }
    public class func addKeyframe(withRelativeStartTime frameStartTime: Double, relativeDuration frameDuration: Double, animations: @escaping () -> Void) {
        animations()
    }
    public class func transition(with view: UIView, duration: TimeInterval, options: AnimationOptions = [], animations: (() -> Void)?,
                                 completion: ((Bool) -> Void)? = nil) {
        animations?()
        completion?(true)
    }
    public class func transition(from fromView: UIView, to toView: UIView, duration: TimeInterval, options: AnimationOptions = [],
                                 completion: ((Bool) -> Void)? = nil) {
        if let parent = fromView.superview { parent.insertSubview(toView, aboveSubview: fromView); fromView.removeFromSuperview() }
        completion?(true)
    }
}

public protocol UIInteraction: AnyObject {}

open class UIWindow: UIView {
    public struct Level: RawRepresentable, Hashable, Comparable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let normal = Level(rawValue: 0)
        public static let statusBar = Level(rawValue: 1000)
        public static let alert = Level(rawValue: 2000)
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public static let didBecomeKeyNotification = Notification.Name("UIWindowDidBecomeKeyNotification")
    public static let didResignKeyNotification = Notification.Name("UIWindowDidResignKeyNotification")
    public static let didBecomeVisibleNotification = Notification.Name("UIWindowDidBecomeVisibleNotification")
    public static let didBecomeHiddenNotification = Notification.Name("UIWindowDidBecomeHiddenNotification")

    open var rootViewController: UIViewController?
    open var windowLevel = Level.normal
    open var isKeyWindow: Bool { true }
    open weak var windowScene: UIWindowScene?
    open var screen: UIScreen { .main }
    open var canBecomeKey: Bool { true }

    public convenience init(windowScene: UIWindowScene) {
        self.init(frame: CGRect(origin: .zero, size: _currentCanvasSize()))
        self.windowScene = windowScene
    }
    open func makeKeyAndVisible() {}
    open func makeKey() {}
    open func becomeKey() {}
    open func resignKey() {}
    open func sendEvent(_ event: UIEvent) {}
}

// MARK: - Gesture recognizers (never recognise: nothing touches a screenshot)

public protocol UIGestureRecognizerDelegate: NSObjectProtocol {}

open class UIGestureRecognizer: NSObject {
    public enum State: Int, Sendable {
        case possible, began, changed, ended, cancelled, failed
        public static var recognized: State { .ended }
    }
    open var state = State.possible
    open weak var delegate: UIGestureRecognizerDelegate?
    open var isEnabled = true
    open internal(set) weak var view: UIView?
    open var cancelsTouchesInView = true
    open var delaysTouchesBegan = false
    open var delaysTouchesEnded = true
    open var allowedTouchTypes: [NSNumber] = []
    open var allowedPressTypes: [NSNumber] = []
    open var requiresExclusiveTouchType = true
    open var name: String?
    open var numberOfTouches: Int { 0 }

    public init(target: Any?, action: Selector?) { super.init() }
    public convenience override init() { self.init(target: nil, action: nil) }
    open func addTarget(_ target: Any, action: Selector) {}
    open func removeTarget(_ target: Any?, action: Selector?) {}
    open func location(in view: UIView?) -> CGPoint { .zero }
    open func location(ofTouch touchIndex: Int, in view: UIView?) -> CGPoint { .zero }
    open func require(toFail otherGestureRecognizer: UIGestureRecognizer) {}
    open func reset() {}
    open func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    open func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {}
}
open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired = 1
    open var numberOfTouchesRequired = 1
    open var buttonMaskRequired: Int = 1
}
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    open var minimumPressDuration: TimeInterval = 0.5
    open var allowableMovement: CGFloat = 10
    open var numberOfTapsRequired = 0
    open var numberOfTouchesRequired = 1
}
open class UIPanGestureRecognizer: UIGestureRecognizer {
    open var minimumNumberOfTouches = 1
    open var maximumNumberOfTouches = Int.max
    open var allowedScrollTypesMask: Int = 0
    open func translation(in view: UIView?) -> CGPoint { .zero }
    open func setTranslation(_ translation: CGPoint, in view: UIView?) {}
    open func velocity(in view: UIView?) -> CGPoint { .zero }
}
open class UIScreenEdgePanGestureRecognizer: UIPanGestureRecognizer { open var edges: UIRectEdge = [] }
open class UIPinchGestureRecognizer: UIGestureRecognizer {
    open var scale: CGFloat = 1
    open var velocity: CGFloat { 0 }
}
open class UIRotationGestureRecognizer: UIGestureRecognizer {
    open var rotation: CGFloat = 0
    open var velocity: CGFloat { 0 }
}
open class UISwipeGestureRecognizer: UIGestureRecognizer {
    public struct Direction: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let right = Direction(rawValue: 1)
        public static let left = Direction(rawValue: 2)
        public static let up = Direction(rawValue: 4)
        public static let down = Direction(rawValue: 8)
    }
    open var direction: Direction = .right
    open var numberOfTouchesRequired = 1
}
open class UIHoverGestureRecognizer: UIGestureRecognizer {}
