// UITraitCollection and the trait value types. The current traits describe the render in progress:
// color scheme, device, size classes, scale and Dynamic Type size.

import Foundation
import SwiftUI

public enum UIUserInterfaceLevel: Int, Hashable, Sendable { case unspecified = -1, base, elevated }
public enum UIAccessibilityContrast: Int, Hashable, Sendable { case unspecified = -1, normal, high }
public enum UILegibilityWeight: Int, Hashable, Sendable { case unspecified = -1, regular, bold }
public enum UITraitEnvironmentLayoutDirection: Int, Hashable, Sendable { case unspecified = -1, leftToRight, rightToLeft }
public enum UIDisplayGamut: Int, Hashable, Sendable { case unspecified = -1, SRGB, P3 }
public enum UIForceTouchCapability: Int, Hashable, Sendable { case unknown, unavailable, available }
public enum UIUserInterfaceActiveAppearance: Int, Hashable, Sendable { case unspecified = -1, inactive, active }
public enum UIUserInterfaceLayoutDirection: Int, Hashable, Sendable { case leftToRight, rightToLeft }
public enum UISemanticContentAttribute: Int, Hashable, Sendable { case unspecified, playback, spatial, forceLeftToRight, forceRightToLeft }

public struct UIContentSizeCategory: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let unspecified = UIContentSizeCategory(rawValue: "_UICTContentSizeCategoryUnspecified")
    public static let extraSmall = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXS")
    public static let small = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryS")
    public static let medium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryM")
    public static let large = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryL")
    public static let extraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXL")
    public static let extraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXL")
    public static let extraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXXL")
    public static let accessibilityMedium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityM")
    public static let accessibilityLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityL")
    public static let accessibilityExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXL")
    public static let accessibilityExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXL")
    public static let accessibilityExtraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXXL")
    public static let didChangeNotification = Notification.Name("UIContentSizeCategoryDidChangeNotification")
    public static let newValueUserInfoKey = "UIContentSizeCategoryNewValueKey"

    static let ordered: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]
    public var isAccessibilityCategory: Bool { (UIContentSizeCategory.ordered.firstIndex(of: self) ?? 0) >= 7 }
    public static func < (a: UIContentSizeCategory, b: UIContentSizeCategory) -> Bool {
        (ordered.firstIndex(of: a) ?? 3) < (ordered.firstIndex(of: b) ?? 3)
    }
    init(_ size: DynamicTypeSize) {
        self = UIContentSizeCategory.ordered[DynamicTypeSize.allCases.firstIndex(of: size) ?? 3]
    }
}

extension DynamicTypeSize {
    public init?(_ uiSizeCategory: UIContentSizeCategory) {
        guard let index = UIContentSizeCategory.ordered.firstIndex(of: uiSizeCategory) else { return nil }
        self = DynamicTypeSize.allCases[index]
    }
}
extension ColorScheme {
    public init?(_ uiUserInterfaceStyle: UIUserInterfaceStyle) {
        switch uiUserInterfaceStyle {
        case .light: self = .light
        case .dark: self = .dark
        case .unspecified: return nil
        }
    }
}
extension UIUserInterfaceStyle {
    public init(_ colorScheme: ColorScheme?) {
        switch colorScheme {
        case .light?: self = .light
        case .dark?: self = .dark
        case nil: self = .unspecified
        }
    }
}

open class UITraitCollection: NSObject, @unchecked Sendable {
    public var userInterfaceStyle: UIUserInterfaceStyle
    public var horizontalSizeClass: UIUserInterfaceSizeClass
    public var verticalSizeClass: UIUserInterfaceSizeClass
    public var displayScale: CGFloat
    public var userInterfaceIdiom: UIUserInterfaceIdiom
    public var preferredContentSizeCategory: UIContentSizeCategory
    public var layoutDirection = UITraitEnvironmentLayoutDirection.leftToRight
    public var userInterfaceLevel = UIUserInterfaceLevel.base
    public var accessibilityContrast = UIAccessibilityContrast.normal
    public var legibilityWeight = UILegibilityWeight.regular
    public var displayGamut = UIDisplayGamut.SRGB
    public var forceTouchCapability = UIForceTouchCapability.unavailable
    public var activeAppearance = UIUserInterfaceActiveAppearance.active

    public init(userInterfaceStyle: UIUserInterfaceStyle) {
        let config = _currentConfiguration()
        self.userInterfaceStyle = userInterfaceStyle
        horizontalSizeClass = _currentSizeClass(horizontal: true) == .regular ? .regular : .compact
        verticalSizeClass = _currentSizeClass(horizontal: false) == .regular ? .regular : .compact
        displayScale = config.scale ?? config.device.scale
        switch config.device.idiom {
        case .pad: userInterfaceIdiom = .pad
        case .tv: userInterfaceIdiom = .tv
        case .phone: userInterfaceIdiom = .phone
        case .watch: userInterfaceIdiom = .unspecified
        }
        preferredContentSizeCategory = UIContentSizeCategory(EnvironmentValues().dynamicTypeSize)
        super.init()
    }
    public convenience override init() { self.init(userInterfaceStyle: _currentConfiguration().colorScheme == .dark ? .dark : .light) }
    public convenience init(horizontalSizeClass: UIUserInterfaceSizeClass) { self.init(); self.horizontalSizeClass = horizontalSizeClass }
    public convenience init(verticalSizeClass: UIUserInterfaceSizeClass) { self.init(); self.verticalSizeClass = verticalSizeClass }
    public convenience init(userInterfaceIdiom: UIUserInterfaceIdiom) { self.init(); self.userInterfaceIdiom = userInterfaceIdiom }
    public convenience init(displayScale: CGFloat) { self.init(); self.displayScale = displayScale }
    public convenience init(preferredContentSizeCategory: UIContentSizeCategory) { self.init(); self.preferredContentSizeCategory = preferredContentSizeCategory }
    public convenience init(userInterfaceLevel: UIUserInterfaceLevel) { self.init(); self.userInterfaceLevel = userInterfaceLevel }
    public convenience init(accessibilityContrast: UIAccessibilityContrast) { self.init(); self.accessibilityContrast = accessibilityContrast }
    public convenience init(legibilityWeight: UILegibilityWeight) { self.init(); self.legibilityWeight = legibilityWeight }
    public convenience init(layoutDirection: UITraitEnvironmentLayoutDirection) { self.init(); self.layoutDirection = layoutDirection }
    /// The last collection's traits win where both specify one; here every collection is fully specified.
    public convenience init(traitsFrom traitCollections: [UITraitCollection]) {
        self.init(userInterfaceStyle: traitCollections.last(where: { $0.userInterfaceStyle != .unspecified })?.userInterfaceStyle ?? .unspecified)
        if let last = traitCollections.last {
            horizontalSizeClass = last.horizontalSizeClass
            verticalSizeClass = last.verticalSizeClass
            displayScale = last.displayScale
            userInterfaceIdiom = last.userInterfaceIdiom
            preferredContentSizeCategory = last.preferredContentSizeCategory
        }
    }

    /// The traits of the render in progress.
    public class var current: UITraitCollection {
        get { override ?? UITraitCollection() }
        set { override = newValue }
    }
    nonisolated(unsafe) private static var override: UITraitCollection?

    public func performAsCurrent(_ actions: () -> Void) {
        let previous = UITraitCollection.override
        UITraitCollection.override = self
        actions()
        UITraitCollection.override = previous
    }
    public func hasDifferentColorAppearance(comparedTo traitCollection: UITraitCollection?) -> Bool {
        guard let other = traitCollection else { return true }
        return other.userInterfaceStyle != userInterfaceStyle || other.accessibilityContrast != accessibilityContrast
            || other.userInterfaceLevel != userInterfaceLevel
    }
    public func containsTraits(in trait: UITraitCollection?) -> Bool { true }
    public func modifyingTraits(_ mutations: (UITraitCollection) -> Void) -> UITraitCollection {
        let copy = UITraitCollection(traitsFrom: [self])
        mutations(copy)
        return copy
    }
}

public protocol UITraitEnvironment: AnyObject {
    var traitCollection: UITraitCollection { get }
    func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
}
