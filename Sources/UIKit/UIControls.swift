// UIKit's stock views and controls as property stores (see UIView.swift). The ones with an obvious
// SwiftUI counterpart are drawn by the representable host when a UIViewRepresentable wraps them.

import Foundation
import SwiftUI

open class UILabel: UIView {
    open var text: String?
    open var attributedText: NSAttributedString?
    open var font: UIFont! = .systemFont(ofSize: 17)
    open var textColor: UIColor! = .label
    open var highlightedTextColor: UIColor?
    open var shadowColor: UIColor?
    open var shadowOffset = CGSize(width: 0, height: -1)
    open var textAlignment: NSTextAlignment = .natural
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    open var numberOfLines = 1
    open var adjustsFontSizeToFitWidth = false
    open var adjustsFontForContentSizeCategory = false
    open var minimumScaleFactor: CGFloat = 0
    open var allowsDefaultTighteningForTruncation = false
    open var preferredMaxLayoutWidth: CGFloat = 0
    open var isHighlighted = false
    open var isEnabled = true
    open var showsExpansionTextWhenTruncated = false
    open override var intrinsicContentSize: CGSize {
        let string = attributedText ?? NSAttributedString(string: text ?? "", attributes: [.font: font as Any])
        let size = string.boundingRect(with: CGSize(width: preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : .greatestFiniteMagnitude,
                                                    height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).size
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }
    /// The text's size wrapped at `size.width` (one line when `numberOfLines` is 1), at most `numberOfLines` lines.
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let string = attributedText ?? NSAttributedString(string: text ?? "", attributes: [.font: font as Any])
        guard string.length > 0 else { return .zero }
        let wraps = numberOfLines != 1 && size.width > 0 && size.width < 1e6
        var fitted = string.boundingRect(with: CGSize(width: wraps ? size.width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin], context: nil).size
        if numberOfLines > 0, let font { fitted.height = min(fitted.height, font.lineHeight * CGFloat(numberOfLines)) }
        return CGSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
    }
}

open class UIImageView: UIView {
    open var image: UIImage?
    open var highlightedImage: UIImage?
    open var isHighlighted = false
    open var preferredSymbolConfiguration: UIImage.SymbolConfiguration?
    open var animationImages: [UIImage]?
    open var animationDuration: TimeInterval = 0
    open var animationRepeatCount = 0
    open var adjustsImageSizeForAccessibilityContentSizeCategory = false
    open var isAnimating: Bool { false }
    public init(image: UIImage?) {
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
    }
    public convenience init(image: UIImage?, highlightedImage: UIImage?) { self.init(image: image); self.highlightedImage = highlightedImage }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open func startAnimating() {}
    open func stopAnimating() {}
    open override var intrinsicContentSize: CGSize { image?.size ?? super.intrinsicContentSize }
}

// MARK: - Controls

public typealias UIActionHandler = (UIAction) -> Void

open class UIMenuElement: NSObject {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let disabled = Attributes(rawValue: 1)
        public static let destructive = Attributes(rawValue: 2)
        public static let hidden = Attributes(rawValue: 4)
        public static let keepsMenuPresented = Attributes(rawValue: 8)
    }
    public enum State: Int, Sendable { case off, on, mixed }
    open var title: String
    open var subtitle: String?
    open var image: UIImage?
    init(title: String, image: UIImage?) { self.title = title; self.image = image; super.init() }
}
open class UIAction: UIMenuElement {
    public struct Identifier: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    open var identifier: Identifier
    open var discoverabilityTitle: String?
    open var attributes: Attributes
    open var state: State
    open var sender: Any? { nil }
    let handler: UIActionHandler
    public init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, selectedImage: UIImage? = nil, identifier: Identifier? = nil,
                discoverabilityTitle: String? = nil, attributes: Attributes = [], state: State = .off, handler: @escaping UIActionHandler) {
        self.identifier = identifier ?? Identifier(UUID().uuidString)
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        self.handler = handler
        super.init(title: title, image: image)
        self.subtitle = subtitle
    }
}
open class UIMenu: UIMenuElement {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let displayInline = Options(rawValue: 1)
        public static let destructive = Options(rawValue: 2)
        public static let singleSelection = Options(rawValue: 32)
        public static let displayAsPalette = Options(rawValue: 128)
    }
    public struct Identifier: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    open var children: [UIMenuElement]
    open var options: Options
    public init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, identifier: Identifier? = nil, options: Options = [],
                children: [UIMenuElement] = []) {
        self.children = children
        self.options = options
        super.init(title: title, image: image)
        self.subtitle = subtitle
    }
    open func replacingChildren(_ newChildren: [UIMenuElement]) -> UIMenu { UIMenu(title: title, image: image, options: options, children: newChildren) }
}
open class UIDeferredMenuElement: UIMenuElement {
    public init(_ elementProvider: @escaping (@escaping ([UIMenuElement]) -> Void) -> Void) { super.init(title: "", image: nil) }
    public class func uncached(_ elementProvider: @escaping (@escaping ([UIMenuElement]) -> Void) -> Void) -> UIDeferredMenuElement {
        UIDeferredMenuElement(elementProvider)
    }
}

open class UIControl: UIView {
    public struct State: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State([])
        public static let highlighted = State(rawValue: 1)
        public static let disabled = State(rawValue: 2)
        public static let selected = State(rawValue: 4)
        public static let focused = State(rawValue: 8)
    }
    public struct Event: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let touchDown = Event(rawValue: 1 << 0)
        public static let touchDownRepeat = Event(rawValue: 1 << 1)
        public static let touchDragInside = Event(rawValue: 1 << 2)
        public static let touchDragOutside = Event(rawValue: 1 << 3)
        public static let touchDragEnter = Event(rawValue: 1 << 4)
        public static let touchDragExit = Event(rawValue: 1 << 5)
        public static let touchUpInside = Event(rawValue: 1 << 6)
        public static let touchUpOutside = Event(rawValue: 1 << 7)
        public static let touchCancel = Event(rawValue: 1 << 8)
        public static let valueChanged = Event(rawValue: 1 << 12)
        public static let primaryActionTriggered = Event(rawValue: 1 << 13)
        public static let menuActionTriggered = Event(rawValue: 1 << 14)
        public static let editingDidBegin = Event(rawValue: 1 << 16)
        public static let editingChanged = Event(rawValue: 1 << 17)
        public static let editingDidEnd = Event(rawValue: 1 << 18)
        public static let editingDidEndOnExit = Event(rawValue: 1 << 19)
        public static let allTouchEvents = Event(rawValue: 0x0FFF)
        public static let allEditingEvents = Event(rawValue: 0xF0000)
        public static let allEvents = Event(rawValue: 0xFFFF_FFFF)
    }
    public enum ContentHorizontalAlignment: Int, Sendable { case center, left, right, fill, leading, trailing }
    public enum ContentVerticalAlignment: Int, Sendable { case center, top, bottom, fill }

    open var isEnabled = true
    open var isSelected = false
    open var isHighlighted = false
    open var contentHorizontalAlignment = ContentHorizontalAlignment.center
    open var contentVerticalAlignment = ContentVerticalAlignment.center
    open var isContextMenuInteractionEnabled = false
    open var showsMenuAsPrimaryAction = false
    open var toolTip: String?
    open var state: State {
        var s: State = []
        if !isEnabled { s.insert(.disabled) }
        if isSelected { s.insert(.selected) }
        if isHighlighted { s.insert(.highlighted) }
        return s
    }
    open var isTracking: Bool { false }
    open var isTouchInside: Bool { false }
    open var allTargets: Set<AnyHashable> { [] }
    private var actions: [(UIAction, Event)] = []

    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(frame: CGRect, primaryAction: UIAction?) {
        self.init(frame: frame)
        if let primaryAction { addAction(primaryAction, for: .primaryActionTriggered) }
    }
    open func addTarget(_ target: Any?, action: Selector, for controlEvents: Event) {}
    open func removeTarget(_ target: Any?, action: Selector?, for controlEvents: Event) {}
    open func addAction(_ action: UIAction, for controlEvents: Event) { actions.append((action, controlEvents)) }
    open func removeAction(_ action: UIAction, for controlEvents: Event) { actions.removeAll { $0.0 === action } }
    /// Runs the `UIAction`s registered for the events (target/action pairs cannot be called without the Objective-C runtime).
    open func sendActions(for controlEvents: Event) {
        for (action, events) in actions where !events.intersection(controlEvents).isEmpty { action.handler(action) }
    }
    open func sendAction(_ action: UIAction) { action.handler(action) }
}

public struct UIBackgroundConfiguration {
    public var backgroundColor: UIColor?
    public var cornerRadius: CGFloat = 0
    public var strokeColor: UIColor?
    public var strokeWidth: CGFloat = 0
    public var image: UIImage?
    public var visualEffect: UIVisualEffect?
    public var customView: UIView?
    public var backgroundInsets = NSDirectionalEdgeInsets.zero
    public static func clear() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listPlainCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listGroupedCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
}

open class UIButton: UIControl {
    public enum ButtonType: Int, Sendable { case custom, system, detailDisclosure, infoLight, infoDark, contactAdd, close }
    public enum Role: Int, Sendable { case normal, primary, cancel, destructive }
    public struct Configuration {
        public enum Size: Int, Sendable { case medium, small, mini, large }
        public enum CornerStyle: Int, Sendable { case fixed = -1, dynamic, small, medium, large, capsule }
        public enum TitleAlignment: Int, Sendable { case automatic, leading, center, trailing }
        enum Style { case plain, tinted, gray, filled, bordered, borderedTinted, borderedProminent, glass, prominentGlass }
        var style: Style
        public var title: String?
        public var attributedTitle: AttributedString?
        public var subtitle: String?
        public var image: UIImage?
        public var imagePadding: CGFloat = 0
        public var imagePlacement = NSDirectionalRectEdge.leading
        public var titlePadding: CGFloat = 1
        public var titleAlignment = TitleAlignment.automatic
        public var baseForegroundColor: UIColor?
        public var baseBackgroundColor: UIColor?
        public var background = UIBackgroundConfiguration()
        public var cornerStyle = CornerStyle.dynamic
        public var buttonSize = Size.medium
        public var contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
        public var showsActivityIndicator = false
        public var preferredSymbolConfigurationForImage: UIImage.SymbolConfiguration?
        public var titleTextAttributesTransformer: Any?
        public var titleLineBreakMode = NSLineBreakMode.byWordWrapping
        public static func plain() -> Configuration { Configuration(style: .plain) }
        public static func tinted() -> Configuration { Configuration(style: .tinted) }
        public static func gray() -> Configuration { Configuration(style: .gray) }
        public static func filled() -> Configuration { Configuration(style: .filled) }
        public static func borderless() -> Configuration { Configuration(style: .plain) }
        public static func bordered() -> Configuration { Configuration(style: .bordered) }
        public static func borderedTinted() -> Configuration { Configuration(style: .borderedTinted) }
        public static func borderedProminent() -> Configuration { Configuration(style: .borderedProminent) }
        public static func glass() -> Configuration { Configuration(style: .glass) }
        public static func prominentGlass() -> Configuration { Configuration(style: .prominentGlass) }
        public func updated(for button: UIButton) -> Configuration { self }
        public mutating func setDefaultContentInsets() { contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12) }
    }
    public typealias ConfigurationUpdateHandler = (UIButton) -> Void

    open var buttonType = ButtonType.custom
    open var configuration: Configuration?
    open var configurationUpdateHandler: ConfigurationUpdateHandler?
    open var automaticallyUpdatesConfiguration = true
    open var role = Role.normal
    open var menu: UIMenu?
    open var changesSelectionAsPrimaryAction = false
    open var isPointerInteractionEnabled = false
    open var contentEdgeInsets = UIEdgeInsets.zero
    open var titleEdgeInsets = UIEdgeInsets.zero
    open var imageEdgeInsets = UIEdgeInsets.zero
    open var adjustsImageWhenHighlighted = true
    public let titleLabel: UILabel? = UILabel()
    public let imageView: UIImageView? = UIImageView()
    private var titles: [UInt: String] = [:]
    private var attributedTitles: [UInt: NSAttributedString] = [:]
    private var images: [UInt: UIImage] = [:]
    private var backgroundImages: [UInt: UIImage] = [:]
    private var titleColors: [UInt: UIColor] = [:]

    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(type buttonType: ButtonType) { self.init(frame: .zero); self.buttonType = buttonType }
    public convenience init(type buttonType: ButtonType = .system, primaryAction: UIAction?) {
        self.init(frame: .zero, primaryAction: primaryAction)
        self.buttonType = buttonType
        if let primaryAction { setTitle(primaryAction.title, for: .normal); setImage(primaryAction.image, for: .normal) }
    }
    public convenience init(configuration: Configuration, primaryAction: UIAction? = nil) {
        self.init(frame: .zero, primaryAction: primaryAction)
        self.configuration = configuration
    }
    public class func systemButton(with image: UIImage, target: Any?, action: Selector?) -> UIButton {
        let button = UIButton(frame: .zero)
        button.buttonType = .system
        button.setImage(image, for: .normal)
        return button
    }

    open func setTitle(_ title: String?, for state: State) { titles[state.rawValue] = title }
    open func setAttributedTitle(_ title: NSAttributedString?, for state: State) { attributedTitles[state.rawValue] = title }
    open func setImage(_ image: UIImage?, for state: State) { images[state.rawValue] = image }
    open func setBackgroundImage(_ image: UIImage?, for state: State) { backgroundImages[state.rawValue] = image }
    open func setTitleColor(_ color: UIColor?, for state: State) { titleColors[state.rawValue] = color }
    open func setTitleShadowColor(_ color: UIColor?, for state: State) {}
    open func setPreferredSymbolConfiguration(_ configuration: UIImage.SymbolConfiguration?, forImageIn state: State) {}
    open func title(for state: State) -> String? { titles[state.rawValue] ?? titles[0] }
    open func attributedTitle(for state: State) -> NSAttributedString? { attributedTitles[state.rawValue] ?? attributedTitles[0] }
    open func image(for state: State) -> UIImage? { images[state.rawValue] ?? images[0] }
    open func backgroundImage(for state: State) -> UIImage? { backgroundImages[state.rawValue] ?? backgroundImages[0] }
    open func titleColor(for state: State) -> UIColor? { titleColors[state.rawValue] ?? titleColors[0] }
    open var currentTitle: String? { configuration?.title ?? title(for: state) }
    open var currentImage: UIImage? { configuration?.image ?? image(for: state) }
    open var currentTitleColor: UIColor { configuration?.baseForegroundColor ?? titleColor(for: state) ?? (buttonType == .custom ? .white : tintColor) }
    /// The title and image with the content insets (UIKitLayout.swift).
    open override var intrinsicContentSize: CGSize { _contentSize }
    open func setNeedsUpdateConfiguration() { configurationUpdateHandler?(self) }
    open func updateConfiguration() {}
}

public enum UITextAutocorrectionType: Int, Sendable { case `default`, no, yes }
public enum UITextSpellCheckingType: Int, Sendable { case `default`, no, yes }
public enum UITextSmartQuotesType: Int, Sendable { case `default`, no, yes }
public enum UITextSmartDashesType: Int, Sendable { case `default`, no, yes }
public enum UITextSmartInsertDeleteType: Int, Sendable { case `default`, no, yes }
public enum UITextInlinePredictionType: Int, Sendable { case `default`, no, yes }
public enum UIKeyboardAppearance: Int, Sendable { case `default`, dark, light }
public enum UIReturnKeyType: Int, Sendable { case `default`, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue` }

public protocol UITextInputTraits: AnyObject {}
public protocol UIKeyInput: UITextInputTraits {
    var hasText: Bool { get }
    func insertText(_ text: String)
    func deleteBackward()
}
public protocol UITextInput: UIKeyInput {}
public protocol UITextInputDelegate: AnyObject {}

/// A position in a text view's text, as a UTF-16 offset.
open class UITextPosition: NSObject {
    let offset: Int
    init(offset: Int) { self.offset = offset; super.init() }
    open override func isEqual(_ object: Any?) -> Bool { (object as? UITextPosition)?.offset == offset }
}
open class UITextRange: NSObject {
    let range: NSRange
    init(range: NSRange) { self.range = range; super.init() }
    open var start: UITextPosition { UITextPosition(offset: range.location) }
    open var end: UITextPosition { UITextPosition(offset: range.location + range.length) }
    open var isEmpty: Bool { range.length == 0 }
    open override func isEqual(_ object: Any?) -> Bool { (object as? UITextRange).map { NSEqualRanges($0.range, range) } ?? false }
}
public enum UITextStorageDirection: Int, Sendable { case forward, backward }
public enum UITextLayoutDirection: Int, Sendable { case right = 2, left, up, down }
public enum UITextGranularity: Int, Sendable { case character, word, sentence, paragraph, line, document }

/// The text-position half of UITextInput, shared by UITextField and UITextView.
protocol _UITextEditing: AnyObject {
    var _string: String { get set }
    var selectedRange: NSRange { get set }
}
extension _UITextEditing {
    var _length: Int { (_string as NSString).length }
    func _clamp(_ offset: Int) -> Int { max(0, min(_length, offset)) }
    func _replace(_ range: NSRange, with text: String) {
        let ns = _string as NSString
        let safe = NSRange(location: _clamp(range.location), length: max(0, min(range.length, ns.length - _clamp(range.location))))
        _string = ns.replacingCharacters(in: safe, with: text)
        selectedRange = NSRange(location: safe.location + (text as NSString).length, length: 0)
    }
}

public protocol UITextFieldDelegate: NSObjectProtocol {}

open class UITextField: UIControl, UITextInput, _UITextEditing {
    public enum BorderStyle: Int, Sendable { case none, line, bezel, roundedRect }
    public enum ViewMode: Int, Sendable { case never, whileEditing, unlessEditing, always }
    public static let textDidChangeNotification = Notification.Name("UITextFieldTextDidChangeNotification")
    public static let textDidBeginEditingNotification = Notification.Name("UITextFieldTextDidBeginEditingNotification")
    public static let textDidEndEditingNotification = Notification.Name("UITextFieldTextDidEndEditingNotification")

    open var text: String? = ""
    open var attributedText: NSAttributedString?
    open var placeholder: String?
    open var attributedPlaceholder: NSAttributedString?
    open var font: UIFont? = .systemFont(ofSize: 17)
    open var textColor: UIColor? = .label
    open var textAlignment: NSTextAlignment = .natural
    open var borderStyle = BorderStyle.none
    open weak var delegate: UITextFieldDelegate?
    open var clearButtonMode = ViewMode.never
    open var leftView: UIView?
    open var rightView: UIView?
    open var leftViewMode = ViewMode.never
    open var rightViewMode = ViewMode.never
    open var background: UIImage?
    open var clearsOnBeginEditing = false
    open var adjustsFontSizeToFitWidth = false
    open var adjustsFontForContentSizeCategory = false
    open var minimumFontSize: CGFloat = 0
    open var isEditing: Bool { false }
    open var defaultTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var typingAttributes: [NSAttributedString.Key: Any]?
    open var isSecureTextEntry = false
    open var keyboardType = UIKeyboardType.default
    open var keyboardAppearance = UIKeyboardAppearance.default
    open var returnKeyType = UIReturnKeyType.default
    open var enablesReturnKeyAutomatically = false
    open var autocapitalizationType = UITextAutocapitalizationType.sentences
    open var autocorrectionType = UITextAutocorrectionType.default
    open var spellCheckingType = UITextSpellCheckingType.default
    open var smartQuotesType = UITextSmartQuotesType.default
    open var smartDashesType = UITextSmartDashesType.default
    open var smartInsertDeleteType = UITextSmartInsertDeleteType.default
    open var textContentType: UITextContentType!
    open var passwordRules: UITextInputPasswordRules?
    private var accessory: UIView?
    private var customInput: UIView?
    open override var inputAccessoryView: UIView? { get { accessory } set { accessory = newValue } }
    open override var inputView: UIView? { get { customInput } set { customInput = newValue } }

    var _string: String { get { text ?? "" } set { text = newValue } }
    public var selectedRange = NSRange(location: 0, length: 0)
    open var hasText: Bool { !(text ?? "").isEmpty }
    open func insertText(_ text: String) { _replace(selectedRange, with: text) }
    open func deleteBackward() {
        if selectedRange.length > 0 { _replace(selectedRange, with: "") } else if selectedRange.location > 0 { _replace(NSRange(location: selectedRange.location - 1, length: 1), with: "") }
    }
    open var selectedTextRange: UITextRange? {
        get { UITextRange(range: selectedRange) }
        set { if let newValue { selectedRange = newValue.range } }
    }
    open var markedTextRange: UITextRange? { nil }
    open var beginningOfDocument: UITextPosition { UITextPosition(offset: 0) }
    open var endOfDocument: UITextPosition { UITextPosition(offset: _length) }
    open func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = position.offset + offset
        return target < 0 || target > _length ? nil : UITextPosition(offset: target)
    }
    open func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { toPosition.offset - from.offset }
    open func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        UITextRange(range: NSRange(location: min(fromPosition.offset, toPosition.offset), length: abs(toPosition.offset - fromPosition.offset)))
    }
    open func text(in range: UITextRange) -> String? {
        let ns = _string as NSString
        guard range.range.location + range.range.length <= ns.length else { return nil }
        return ns.substring(with: range.range)
    }
    open func replace(_ range: UITextRange, withText text: String) { _replace(range.range, with: text) }
    open func selectAll(_ sender: Any?) { selectedRange = NSRange(location: 0, length: _length) }
    open override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: borderStyle == .roundedRect ? 34 : ((font?.lineHeight ?? 20) + 1).rounded(.up)) }
}
open class UITextInputPasswordRules: NSObject {
    public let passwordRulesDescriptor: String
    public init(descriptor passwordRulesDescriptor: String) { self.passwordRulesDescriptor = passwordRulesDescriptor; super.init() }
}

open class UISwitch: UIControl {
    public enum Style: Int, Sendable { case automatic, checkbox, sliding }
    open var isOn = false
    open var onTintColor: UIColor?
    open var thumbTintColor: UIColor?
    open var preferredStyle = Style.automatic
    open var title: String?
    open func setOn(_ on: Bool, animated: Bool) { isOn = on }
    open override var intrinsicContentSize: CGSize { CGSize(width: 51, height: 31) }
}
open class UISlider: UIControl {
    open var value: Float = 0
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
    open var isContinuous = true
    open var minimumTrackTintColor: UIColor?
    open var maximumTrackTintColor: UIColor?
    open var thumbTintColor: UIColor?
    open var minimumValueImage: UIImage?
    open var maximumValueImage: UIImage?
    open func setValue(_ value: Float, animated: Bool) { self.value = max(minimumValue, min(maximumValue, value)) }
    open func setThumbImage(_ image: UIImage?, for state: State) {}
    open func setMinimumTrackImage(_ image: UIImage?, for state: State) {}
    open func setMaximumTrackImage(_ image: UIImage?, for state: State) {}
    open override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 30) }
}
open class UIStepper: UIControl {
    open var value: Double = 0
    open var minimumValue: Double = 0
    open var maximumValue: Double = 100
    open var stepValue: Double = 1
    open var isContinuous = true
    open var autorepeat = true
    open var wraps = false
    open override var intrinsicContentSize: CGSize { CGSize(width: 94, height: 32) }
}
open class UISegmentedControl: UIControl {
    public static let noSegment = -1
    var segments: [Any] = []
    open var selectedSegmentIndex = UISegmentedControl.noSegment
    open var selectedSegmentTintColor: UIColor?
    open var isMomentary = false
    open var apportionsSegmentWidthsByContent = false
    open var numberOfSegments: Int { segments.count }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(items: [Any]?) { self.init(frame: .zero); segments = items ?? [] }
    open func insertSegment(withTitle title: String?, at segment: Int, animated: Bool) { segments.insert(title ?? "", at: max(0, min(segment, segments.count))) }
    open func insertSegment(with image: UIImage?, at segment: Int, animated: Bool) { segments.insert(image as Any, at: max(0, min(segment, segments.count))) }
    open func insertSegment(action: UIAction, at segment: Int, animated: Bool) { segments.insert(action.title, at: max(0, min(segment, segments.count))) }
    open func removeSegment(at segment: Int, animated: Bool) { if segments.indices.contains(segment) { segments.remove(at: segment) } }
    open func removeAllSegments() { segments = [] }
    open func setTitle(_ title: String?, forSegmentAt segment: Int) { if segments.indices.contains(segment) { segments[segment] = title ?? "" } }
    open func titleForSegment(at segment: Int) -> String? { segments.indices.contains(segment) ? segments[segment] as? String : nil }
    open func setImage(_ image: UIImage?, forSegmentAt segment: Int) { if segments.indices.contains(segment) { segments[segment] = image as Any } }
    open func setEnabled(_ enabled: Bool, forSegmentAt segment: Int) {}
    open func setWidth(_ width: CGFloat, forSegmentAt segment: Int) {}
    open func setTitleTextAttributes(_ attributes: [NSAttributedString.Key: Any]?, for state: State) {}
    open override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 32) }
}
open class UIDatePicker: UIControl {
    public enum Mode: Int, Sendable { case time, date, dateAndTime, countDownTimer, yearAndMonth }
    public enum Style: Int, Sendable { case automatic, wheels, compact, inline }
    open var date = Date()
    open var datePickerMode = Mode.dateAndTime
    open var preferredDatePickerStyle = Style.automatic
    open var datePickerStyle: Style { preferredDatePickerStyle == .automatic ? .compact : preferredDatePickerStyle }
    open var minimumDate: Date?
    open var maximumDate: Date?
    open var minuteInterval = 1
    open var countDownDuration: TimeInterval = 0
    open var locale: Locale?
    open var calendar: Calendar! = .current
    open var timeZone: TimeZone?
    open func setDate(_ date: Date, animated: Bool) { self.date = date }
}
open class UIPageControl: UIControl {
    open var numberOfPages = 0
    open var currentPage = 0
    open var hidesForSinglePage = false
    open var pageIndicatorTintColor: UIColor?
    open var currentPageIndicatorTintColor: UIColor?
    open var allowsContinuousInteraction = true
    open override var intrinsicContentSize: CGSize { CGSize(width: CGFloat(max(numberOfPages, 1)) * 16 + 12, height: 26) }
}
open class UIRefreshControl: UIControl {
    open var isRefreshing: Bool { false }
    open var attributedTitle: NSAttributedString?
    open func beginRefreshing() {}
    open func endRefreshing() {}
}
open class UIColorWell: UIControl {
    open var selectedColor: UIColor?
    open var supportsAlpha = true
    open var title: String?
}

open class UIProgressView: UIView {
    public enum Style: Int, Sendable { case `default`, bar }
    open var progress: Float = 0
    open var progressViewStyle = Style.default
    open var progressTintColor: UIColor?
    open var trackTintColor: UIColor?
    open var observedProgress: Progress?
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(progressViewStyle style: Style) { self.init(frame: .zero); progressViewStyle = style }
    open func setProgress(_ progress: Float, animated: Bool) { self.progress = max(0, min(1, progress)) }
    open override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 4) }
}

open class UIActivityIndicatorView: UIView {
    public enum Style: Int, Sendable { case medium = 100, large = 101 }
    open var style = Style.medium
    open var hidesWhenStopped = true
    open var color: UIColor! = .secondaryLabel
    open private(set) var isAnimating = false
    public init(style: Style) { self.style = style; super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open func startAnimating() { isAnimating = true }
    open func stopAnimating() { isAnimating = false }
    open override var intrinsicContentSize: CGSize { style == .large ? CGSize(width: 37, height: 37) : CGSize(width: 20, height: 20) }
}

// MARK: - Effects

open class UIVisualEffect: NSObject {
    public override init() { super.init() }
}
open class UIBlurEffect: UIVisualEffect {
    public enum Style: Int, Sendable {
        case extraLight, light, dark, regular = 4, prominent
        case systemUltraThinMaterial, systemThinMaterial, systemMaterial, systemThickMaterial, systemChromeMaterial
        case systemUltraThinMaterialLight, systemThinMaterialLight, systemMaterialLight, systemThickMaterialLight, systemChromeMaterialLight
        case systemUltraThinMaterialDark, systemThinMaterialDark, systemMaterialDark, systemThickMaterialDark, systemChromeMaterialDark
    }
    public let style: Style
    public init(style: Style) { self.style = style; super.init() }
}
open class UIVibrancyEffect: UIVisualEffect {
    public init(blurEffect: UIBlurEffect) { super.init() }
    public convenience init(blurEffect: UIBlurEffect, style: Int) { self.init(blurEffect: blurEffect) }
}
open class UIGlassEffect: UIVisualEffect {
    public enum Style: Int, Sendable { case regular, clear }
    public var isInteractive = false
    public var tintColor: UIColor?
    public override init() { super.init() }
    public convenience init(style: Style) { self.init() }
}
open class UIGlassContainerEffect: UIVisualEffect { public var spacing: CGFloat = 0 }
open class UIVisualEffectView: UIView {
    open var effect: UIVisualEffect?
    public let contentView = UIView()
    public init(effect: UIVisualEffect?) { self.effect = effect; super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}

// MARK: - Containers

open class UIStackView: UIView {
    public enum Distribution: Int, Sendable { case fill, fillEqually, fillProportionally, equalSpacing, equalCentering }
    public enum Alignment: Int, Sendable {
        case fill, leading, firstBaseline, center, trailing, lastBaseline
        public static var top: Alignment { .leading }
        public static var bottom: Alignment { .trailing }
    }
    public static let spacingUseDefault: CGFloat = .greatestFiniteMagnitude
    public static let spacingUseSystem: CGFloat = 8
    open var axis = NSLayoutConstraint.Axis.horizontal
    open var distribution = Distribution.fill
    open var alignment = Alignment.fill
    open var spacing: CGFloat = 0
    open var isBaselineRelativeArrangement = false
    open var isLayoutMarginsRelativeArrangement = false
    open private(set) var arrangedSubviews: [UIView] = []
    private var customSpacing: [ObjectIdentifier: CGFloat] = [:]

    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(arrangedSubviews views: [UIView]) {
        self.init(frame: .zero)
        views.forEach(addArrangedSubview)
    }
    open func addArrangedSubview(_ view: UIView) { insertArrangedSubview(view, at: arrangedSubviews.count) }
    open func insertArrangedSubview(_ view: UIView, at stackIndex: Int) {
        arrangedSubviews.removeAll { $0 === view }
        arrangedSubviews.insert(view, at: max(0, min(stackIndex, arrangedSubviews.count)))
        view.translatesAutoresizingMaskIntoConstraints = false
        if view.superview !== self { addSubview(view) }
    }
    /// Arranges the visible arranged subviews along the axis (UIKitLayout.swift), then the other subviews.
    open override func layoutSubviews() {
        super.layoutSubviews()
        _arrangeSubviews()
    }
    open func removeArrangedSubview(_ view: UIView) { arrangedSubviews.removeAll { $0 === view } }
    open override func willRemoveSubview(_ subview: UIView) { arrangedSubviews.removeAll { $0 === subview } }
    open func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) { customSpacing[ObjectIdentifier(arrangedSubview)] = spacing }
    open func customSpacing(after arrangedSubview: UIView) -> CGFloat { customSpacing[ObjectIdentifier(arrangedSubview)] ?? UIStackView.spacingUseDefault }
}

public protocol UIScrollViewDelegate: NSObjectProtocol {}

open class UIScrollView: UIView {
    public enum ContentInsetAdjustmentBehavior: Int, Sendable { case automatic, scrollableAxes, never, always }
    public enum KeyboardDismissMode: Int, Sendable { case none, onDrag, interactive, onDragWithAccessory, interactiveWithAccessory }
    public enum IndicatorStyle: Int, Sendable { case `default`, black, white }
    public struct DecelerationRate: RawRepresentable, Hashable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let normal = DecelerationRate(rawValue: 0.998)
        public static let fast = DecelerationRate(rawValue: 0.99)
    }
    open var contentSize: CGSize = .zero
    open var contentOffset: CGPoint = .zero
    open var contentInset = UIEdgeInsets.zero
    open var adjustedContentInset: UIEdgeInsets { contentInset }
    open var contentInsetAdjustmentBehavior = ContentInsetAdjustmentBehavior.automatic
    open var automaticallyAdjustsScrollIndicatorInsets = true
    open weak var delegate: UIScrollViewDelegate?
    open var showsVerticalScrollIndicator = true
    open var showsHorizontalScrollIndicator = true
    open var indicatorStyle = IndicatorStyle.default
    open var scrollIndicatorInsets = UIEdgeInsets.zero
    open var verticalScrollIndicatorInsets = UIEdgeInsets.zero
    open var horizontalScrollIndicatorInsets = UIEdgeInsets.zero
    open var isScrollEnabled = true
    open var isPagingEnabled = false
    open var isDirectionalLockEnabled = false
    open var bounces = true
    open var alwaysBounceVertical = false
    open var alwaysBounceHorizontal = false
    open var bouncesZoom = true
    open var scrollsToTop = true
    open var delaysContentTouches = true
    open var canCancelContentTouches = true
    open var decelerationRate = DecelerationRate.normal
    open var keyboardDismissMode = KeyboardDismissMode.none
    open var zoomScale: CGFloat = 1
    open var minimumZoomScale: CGFloat = 1
    open var maximumZoomScale: CGFloat = 1
    open var refreshControl: UIRefreshControl?
    open var isDragging: Bool { false }
    open var isTracking: Bool { false }
    open var isDecelerating: Bool { false }
    open var isZooming: Bool { false }
    open var isZoomBouncing: Bool { false }
    public let panGestureRecognizer = UIPanGestureRecognizer()
    public let pinchGestureRecognizer: UIPinchGestureRecognizer? = UIPinchGestureRecognizer()
    public private(set) lazy var contentLayoutGuide = UILayoutGuide(owner: self, kind: .scrollContent)
    public private(set) lazy var frameLayoutGuide = UILayoutGuide(owner: self, kind: .scrollFrame)

    open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) { self.contentOffset = contentOffset }
    open func scrollRectToVisible(_ rect: CGRect, animated: Bool) {}
    open func setZoomScale(_ scale: CGFloat, animated: Bool) { zoomScale = max(minimumZoomScale, min(maximumZoomScale, scale)) }
    open func zoom(to rect: CGRect, animated: Bool) {}
    open func flashScrollIndicators() {}
    open func touchesShouldCancel(in view: UIView) -> Bool { true }
}

public protocol UITextViewDelegate: UIScrollViewDelegate {}

public struct UIDataDetectorTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let phoneNumber = UIDataDetectorTypes(rawValue: 1 << 0)
    public static let link = UIDataDetectorTypes(rawValue: 1 << 1)
    public static let address = UIDataDetectorTypes(rawValue: 1 << 2)
    public static let calendarEvent = UIDataDetectorTypes(rawValue: 1 << 3)
    public static let shipmentTrackingNumber = UIDataDetectorTypes(rawValue: 1 << 4)
    public static let flightNumber = UIDataDetectorTypes(rawValue: 1 << 5)
    public static let lookupSuggestion = UIDataDetectorTypes(rawValue: 1 << 6)
    public static let money = UIDataDetectorTypes(rawValue: 1 << 7)
    public static let physicalValue = UIDataDetectorTypes(rawValue: 1 << 8)
    public static let all = UIDataDetectorTypes(rawValue: UInt.max)
}

open class UITextView: UIScrollView, UITextInput, _UITextEditing {
    public static let textDidChangeNotification = Notification.Name("UITextViewTextDidChangeNotification")
    public static let textDidBeginEditingNotification = Notification.Name("UITextViewTextDidBeginEditingNotification")
    public static let textDidEndEditingNotification = Notification.Name("UITextViewTextDidEndEditingNotification")

    /// The text and its attributes: `text`, `attributedText` and `textStorage` are views of the same storage.
    public let textStorage = NSTextStorage(string: "")
    public let textContainer = NSTextContainer()
    public let layoutManager = NSLayoutManager()
    open var text: String! {
        get { textStorage.string }
        set { textStorage.setAttributedString(NSAttributedString(string: newValue ?? "", attributes: baseAttributes)) }
    }
    open var attributedText: NSAttributedString! {
        get { NSAttributedString(attributedString: textStorage) }
        set { textStorage.setAttributedString(newValue ?? NSAttributedString(string: "")) }
    }
    open var font: UIFont? { didSet { restyle() } }
    open var textColor: UIColor? { didSet { restyle() } }
    open var textAlignment: NSTextAlignment = .natural
    open var isEditable = true
    open var isSelectable = true
    open var allowsEditingTextAttributes = false
    open var dataDetectorTypes: UIDataDetectorTypes = []
    open var typingAttributes: [NSAttributedString.Key: Any] = [:]
    open var linkTextAttributes: [NSAttributedString.Key: Any]! = [:]
    open var textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    open var adjustsFontForContentSizeCategory = false
    open var clearsOnInsertion = false
    open var usesStandardTextScaling = false
    open var isFindInteractionEnabled = false
    open var keyboardType = UIKeyboardType.default
    open var keyboardAppearance = UIKeyboardAppearance.default
    open var returnKeyType = UIReturnKeyType.default
    open var enablesReturnKeyAutomatically = false
    open var isSecureTextEntry = false
    open var autocapitalizationType = UITextAutocapitalizationType.sentences
    open var autocorrectionType = UITextAutocorrectionType.default
    open var spellCheckingType = UITextSpellCheckingType.default
    open var smartQuotesType = UITextSmartQuotesType.default
    open var smartDashesType = UITextSmartDashesType.default
    open var smartInsertDeleteType = UITextSmartInsertDeleteType.default
    open var inlinePredictionType = UITextInlinePredictionType.default
    open var textContentType: UITextContentType!
    open weak var inputDelegate: UITextInputDelegate?
    private var accessory: UIView?
    private var customInput: UIView?
    open override var inputAccessoryView: UIView? { get { accessory } set { accessory = newValue } }
    open override var inputView: UIView? { get { customInput } set { customInput = newValue } }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font { attributes[.font] = font }
        if let textColor { attributes[.foregroundColor] = textColor }
        return attributes
    }
    private func restyle() {
        guard textStorage.length > 0 else { return }
        textStorage.addAttributes(baseAttributes, range: NSRange(location: 0, length: textStorage.length))
    }

    public init(frame: CGRect, textContainer: NSTextContainer?) { super.init(frame: frame) }
    public convenience override init(frame: CGRect) { self.init(frame: frame, textContainer: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(usingTextLayoutManager: Bool) { self.init(frame: .zero, textContainer: nil) }

    var _string: String { get { textStorage.string } set { textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: newValue) } }
    public var selectedRange = NSRange(location: 0, length: 0)
    open var hasText: Bool { textStorage.length > 0 }
    open func insertText(_ text: String) { replace(UITextRange(range: selectedRange), withText: text) }
    open func deleteBackward() {
        if selectedRange.length > 0 { replace(UITextRange(range: selectedRange), withText: "") }
        else if selectedRange.location > 0 { replace(UITextRange(range: NSRange(location: selectedRange.location - 1, length: 1)), withText: "") }
    }
    open var selectedTextRange: UITextRange? {
        get { UITextRange(range: selectedRange) }
        set { if let newValue { selectedRange = newValue.range } }
    }
    open var markedTextRange: UITextRange? { nil }
    open var beginningOfDocument: UITextPosition { UITextPosition(offset: 0) }
    open var endOfDocument: UITextPosition { UITextPosition(offset: textStorage.length) }
    open func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = position.offset + offset
        return target < 0 || target > textStorage.length ? nil : UITextPosition(offset: target)
    }
    open func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { toPosition.offset - from.offset }
    open func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        UITextRange(range: NSRange(location: min(fromPosition.offset, toPosition.offset), length: abs(toPosition.offset - fromPosition.offset)))
    }
    open func text(in range: UITextRange) -> String? {
        guard range.range.location + range.range.length <= textStorage.length else { return nil }
        return (textStorage.string as NSString).substring(with: range.range)
    }
    /// Replaces the characters, keeping the storage's attributes around them, and moves the caret after the insertion.
    open func replace(_ range: UITextRange, withText text: String) {
        let location = max(0, min(textStorage.length, range.range.location))
        let safe = NSRange(location: location, length: max(0, min(range.range.length, textStorage.length - location)))
        textStorage.replaceCharacters(in: safe, with: text)
        selectedRange = NSRange(location: safe.location + (text as NSString).length, length: 0)
    }
    open func scrollRangeToVisible(_ range: NSRange) {}
    open func selectAll(_ sender: Any?) { selectedRange = NSRange(location: 0, length: textStorage.length) }
    open func caretRect(for position: UITextPosition) -> CGRect { .zero }
    open func firstRect(for range: UITextRange) -> CGRect { .zero }
    open func closestPosition(to point: CGPoint) -> UITextPosition? { beginningOfDocument }
}

open class UIInputView: UIView {
    public enum Style: Int, Sendable { case `default`, keyboard }
    public let inputViewStyle: Style
    open var allowsSelfSizing = false
    public init(frame: CGRect, inputViewStyle: Style) { self.inputViewStyle = inputViewStyle; super.init(frame: frame) }
    public required init?(coder: NSCoder) { inputViewStyle = .default; super.init(coder: coder) }
}

open class UIPickerView: UIView {
    open weak var dataSource: AnyObject?
    open weak var delegate: AnyObject?
    open var numberOfComponents: Int { 0 }
    open func numberOfRows(inComponent component: Int) -> Int { 0 }
    open func reloadAllComponents() {}
    open func reloadComponent(_ component: Int) {}
    open func selectRow(_ row: Int, inComponent component: Int, animated: Bool) {}
    open func selectedRow(inComponent component: Int) -> Int { -1 }
}
public protocol UIPickerViewDataSource: NSObjectProtocol {}
public protocol UIPickerViewDelegate: NSObjectProtocol {}

// MARK: - Tables and collections (never populated: the data source is not asked)

public protocol UITableViewDataSource: NSObjectProtocol {}
public protocol UITableViewDelegate: UIScrollViewDelegate {}
public protocol UICollectionViewDataSource: NSObjectProtocol {}
public protocol UICollectionViewDelegate: UIScrollViewDelegate {}
public protocol UICollectionViewDelegateFlowLayout: UICollectionViewDelegate {}

open class UITableViewCell: UIView {
    public enum CellStyle: Int, Sendable { case `default`, value1, value2, subtitle }
    public enum SelectionStyle: Int, Sendable { case none, blue, gray, `default` }
    public enum AccessoryType: Int, Sendable { case none, disclosureIndicator, detailDisclosureButton, checkmark, detailButton }
    public let contentView = UIView()
    public let textLabel: UILabel? = UILabel()
    public let detailTextLabel: UILabel? = UILabel()
    public let imageView: UIImageView? = UIImageView()
    open var reuseIdentifier: String?
    open var selectionStyle = SelectionStyle.default
    open var accessoryType = AccessoryType.none
    open var accessoryView: UIView?
    open var backgroundView: UIView?
    open var selectedBackgroundView: UIView?
    open var isSelected = false
    open var isHighlighted = false
    open var separatorInset = UIEdgeInsets.zero
    open var contentConfiguration: Any?
    open var backgroundConfiguration: UIBackgroundConfiguration?
    public init(style: CellStyle, reuseIdentifier: String?) { self.reuseIdentifier = reuseIdentifier; super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open func prepareForReuse() {}
    open func setSelected(_ selected: Bool, animated: Bool) { isSelected = selected }
    open func setHighlighted(_ highlighted: Bool, animated: Bool) { isHighlighted = highlighted }
}
open class UITableViewHeaderFooterView: UIView {
    public let contentView = UIView()
    public let textLabel: UILabel? = UILabel()
    open var reuseIdentifier: String?
    open var contentConfiguration: Any?
    public init(reuseIdentifier: String?) { self.reuseIdentifier = reuseIdentifier; super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
open class UITableView: UIScrollView {
    public enum Style: Int, Sendable { case plain, grouped, insetGrouped }
    public enum ScrollPosition: Int, Sendable { case none, top, middle, bottom }
    public enum RowAnimation: Int, Sendable { case fade, right, left, top, bottom, none, middle, automatic = 100 }
    public static let automaticDimension: CGFloat = -1
    public let style: Style
    open weak var dataSource: UITableViewDataSource?
    open var rowHeight = UITableView.automaticDimension
    open var estimatedRowHeight = UITableView.automaticDimension
    open var sectionHeaderHeight = UITableView.automaticDimension
    open var sectionFooterHeight = UITableView.automaticDimension
    open var sectionHeaderTopPadding: CGFloat = 22
    open var separatorStyle = 1
    open var separatorColor: UIColor?
    open var separatorInset = UIEdgeInsets.zero
    open var backgroundView: UIView?
    open var tableHeaderView: UIView?
    open var tableFooterView: UIView?
    open var allowsSelection = true
    open var allowsMultipleSelection = false
    open var isEditing = false
    open var indexPathForSelectedRow: IndexPath? { nil }
    open var indexPathsForSelectedRows: [IndexPath]? { nil }
    open var visibleCells: [UITableViewCell] { [] }
    open var numberOfSections: Int { 0 }
    public init(frame: CGRect, style: Style) { self.style = style; super.init(frame: frame) }
    public convenience override init(frame: CGRect) { self.init(frame: frame, style: .plain) }
    public required init?(coder: NSCoder) { style = .plain; super.init(coder: coder) }
    open func numberOfRows(inSection section: Int) -> Int { 0 }
    open func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {}
    open func register(_ aClass: AnyClass?, forHeaderFooterViewReuseIdentifier identifier: String) {}
    open func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? { nil }
    open func dequeueReusableCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell(style: .default, reuseIdentifier: identifier)
    }
    open func dequeueReusableHeaderFooterView(withIdentifier identifier: String) -> UITableViewHeaderFooterView? { nil }
    open func cellForRow(at indexPath: IndexPath) -> UITableViewCell? { nil }
    open func reloadData() {}
    open func reloadRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    open func reloadSections(_ sections: IndexSet, with animation: RowAnimation) {}
    open func insertRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    open func deleteRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    open func beginUpdates() {}
    open func endUpdates() {}
    open func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) { updates?(); completion?(true) }
    open func selectRow(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {}
    open func deselectRow(at indexPath: IndexPath, animated: Bool) {}
    open func scrollToRow(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {}
    open func setEditing(_ editing: Bool, animated: Bool) { isEditing = editing }
}

open class UICollectionViewLayout: NSObject {
    public override init() { super.init() }
    open func invalidateLayout() {}
    open var collectionViewContentSize: CGSize { .zero }
}
open class UICollectionViewFlowLayout: UICollectionViewLayout {
    public static let automaticSize = CGSize(width: 1.79769e308, height: 1.79769e308)
    public enum ScrollDirection: Int, Sendable { case vertical, horizontal }
    open var scrollDirection = ScrollDirection.vertical
    open var minimumLineSpacing: CGFloat = 10
    open var minimumInteritemSpacing: CGFloat = 10
    open var itemSize = CGSize(width: 50, height: 50)
    open var estimatedItemSize = CGSize.zero
    open var sectionInset = UIEdgeInsets.zero
    open var headerReferenceSize = CGSize.zero
    open var footerReferenceSize = CGSize.zero
    open var sectionHeadersPinToVisibleBounds = false
}
open class UICollectionReusableView: UIView {
    open var reuseIdentifier: String? { nil }
    open func prepareForReuse() {}
}
open class UICollectionViewCell: UICollectionReusableView {
    public let contentView = UIView()
    open var isSelected = false
    open var isHighlighted = false
    open var backgroundView: UIView?
    open var selectedBackgroundView: UIView?
    open var contentConfiguration: Any?
    open var backgroundConfiguration: UIBackgroundConfiguration?
}
open class UICollectionView: UIScrollView {
    public struct ScrollPosition: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let top = ScrollPosition(rawValue: 1)
        public static let centeredVertically = ScrollPosition(rawValue: 2)
        public static let bottom = ScrollPosition(rawValue: 4)
        public static let left = ScrollPosition(rawValue: 8)
        public static let centeredHorizontally = ScrollPosition(rawValue: 16)
        public static let right = ScrollPosition(rawValue: 32)
    }
    public static let elementKindSectionHeader = "UICollectionElementKindSectionHeader"
    public static let elementKindSectionFooter = "UICollectionElementKindSectionFooter"
    open var collectionViewLayout: UICollectionViewLayout
    open weak var dataSource: UICollectionViewDataSource?
    open var backgroundView: UIView?
    open var allowsSelection = true
    open var allowsMultipleSelection = false
    open var visibleCells: [UICollectionViewCell] { [] }
    open var indexPathsForSelectedItems: [IndexPath]? { nil }
    open var indexPathsForVisibleItems: [IndexPath] { [] }
    open var numberOfSections: Int { 0 }
    public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) { collectionViewLayout = layout; super.init(frame: frame) }
    public required init?(coder: NSCoder) { collectionViewLayout = UICollectionViewFlowLayout(); super.init(coder: coder) }
    open func numberOfItems(inSection section: Int) -> Int { 0 }
    open func register(_ cellClass: AnyClass?, forCellWithReuseIdentifier identifier: String) {}
    open func register(_ viewClass: AnyClass?, forSupplementaryViewOfKind elementKind: String, withReuseIdentifier identifier: String) {}
    open func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell { UICollectionViewCell(frame: .zero) }
    open func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell? { nil }
    open func reloadData() {}
    open func reloadItems(at indexPaths: [IndexPath]) {}
    open func reloadSections(_ sections: IndexSet) {}
    open func insertItems(at indexPaths: [IndexPath]) {}
    open func deleteItems(at indexPaths: [IndexPath]) {}
    open func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) { updates?(); completion?(true) }
    open func selectItem(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {}
    open func deselectItem(at indexPath: IndexPath, animated: Bool) {}
    open func scrollToItem(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {}
    open func setCollectionViewLayout(_ layout: UICollectionViewLayout, animated: Bool) { collectionViewLayout = layout }
}
