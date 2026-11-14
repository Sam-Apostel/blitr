// Inert stand-ins for the UIKit singletons and classes app code touches next to SwiftUI.
// Everything is non-isolated so it can be called from any closure the app writes.

public struct UIEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init() { top = 0; left = 0; bottom = 0; right = 0 }
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static let zero = UIEdgeInsets()
}

open class UIResponder: NSObject {
    public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
    public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
    public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
    public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
    public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
    public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    @discardableResult open func becomeFirstResponder() -> Bool { true }
    @discardableResult open func resignFirstResponder() -> Bool { true }
}

// MARK: - Screen / device

public final class UIScreen {
    public static let main = UIScreen()
    public var bounds: CGRect { CGRect(origin: .zero, size: _currentCanvasSize()) }
    public var nativeBounds: CGRect {
        let s = scale
        return CGRect(x: 0, y: 0, width: bounds.width * s, height: bounds.height * s)
    }
    public var scale: CGFloat { let c = _currentConfiguration(); return c.scale ?? c.device.scale }
    public var nativeScale: CGFloat { scale }
    public var brightness: CGFloat = 0.5
    public static let brightnessDidChangeNotification = Notification.Name("UIScreenBrightnessDidChangeNotification")
}

public final class UIDevice {
    public enum BatteryState: Int, Sendable { case unknown, unplugged, charging, full }
    public enum Orientation: Int, Sendable { case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown }
    public static let current = UIDevice()
    public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChangeNotification")
    public var userInterfaceIdiom: UIUserInterfaceIdiom { _currentConfiguration().device.idiom == .pad ? .pad : .phone }
    public var name: String { userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    public var model: String { name }
    public var localizedModel: String { name }
    public var systemName: String { "iOS" }
    public var systemVersion: String { "18.0" }
    public var orientation: Orientation {
        switch _currentConfiguration().device.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        }
    }
    public var isBatteryMonitoringEnabled = false
    public var batteryLevel: Float { 1 }
    public var batteryState: BatteryState { .unknown }
    public var identifierForVendor: UUID? { UUID(uuidString: "00000000-0000-0000-0000-000000000000") }
    public func beginGeneratingDeviceOrientationNotifications() {}
    public func endGeneratingDeviceOrientationNotifications() {}
}

// MARK: - Application

open class UIScene: UIResponder {}
open class UIWindowScene: UIScene {
    public var windows: [UIWindow] { [] }
}
open class UIWindow: UIView {}

func _currentSafeInsets() -> UIEdgeInsets {
    let a = _currentConfiguration().device.safeArea
    return UIEdgeInsets(top: a.top, left: a.leading, bottom: a.bottom, right: a.trailing)
}

public final class UIApplication: UIResponder {
    public struct OpenExternalURLOptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let universalLinksOnly = OpenExternalURLOptionsKey(rawValue: "UIApplicationOpenURLOptionUniversalLinksOnly")
    }
    public struct LaunchOptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
    }
    public enum State: Int, Sendable { case active, inactive, background }

    public static let shared = UIApplication()
    public static let openSettingsURLString = "app-settings:"
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
    public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")

    public var connectedScenes: Set<UIScene> { [] }
    public var windows: [UIWindow] { [] }
    public var applicationState: State { .active }
    public var applicationIconBadgeNumber = 0
    public var isIdleTimerDisabled = false
    public var supportsMultipleScenes: Bool { false }

    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {
        completion?(false)
    }
    public func canOpenURL(_ url: URL) -> Bool { false }
    public func registerForRemoteNotifications() {}
}

public protocol UIApplicationDelegate: NSObjectProtocol {}

public final class UIPasteboard {
    public static let general = UIPasteboard()
    public var string: String?
    public var strings: [String]?
    public var url: URL?
}

public enum UIAccessibility {
    public static var isVoiceOverRunning: Bool { false }
    public static var isReduceMotionEnabled: Bool { false }
    public static var isReduceTransparencyEnabled: Bool { false }
    public static var isBoldTextEnabled: Bool { false }
    public static var isDarkerSystemColorsEnabled: Bool { false }
    public static var isSwitchControlRunning: Bool { false }
}

// MARK: - Haptics (no hardware)

open class UIFeedbackGenerator {
    public init() {}
    open func prepare() {}
}
public final class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int, Sendable { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) { super.init() }
    public override init() { super.init() }
    public func impactOccurred() {}
    public func impactOccurred(intensity: CGFloat) {}
}
public final class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int, Sendable { case success, warning, error }
    public override init() { super.init() }
    public func notificationOccurred(_ notificationType: FeedbackType) {}
}
public final class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    public override init() { super.init() }
    public func selectionChanged() {}
}

// MARK: - Views and controllers (placeholders: only their type names matter to SwiftUI)

public class CALayer {
    public var cornerRadius: CGFloat = 0
    public var borderWidth: CGFloat = 0
    public var masksToBounds = false
    public var opacity: Float = 1
    public var shadowOpacity: Float = 0
    public var shadowRadius: CGFloat = 3
    public init() {}
}

public enum NSTextAlignment: Int, Sendable { case left, center, right, justified, natural }

open class UIView: UIResponder {
    public enum ContentMode: Int, Sendable { case scaleToFill, scaleAspectFit, scaleAspectFill, redraw, center, top, bottom, left, right }
    public var frame: CGRect = .zero
    public var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
    public var center: CGPoint = .zero
    public var backgroundColor: UIColor?
    public var tintColor: UIColor!
    public var alpha: CGFloat = 1
    public var isHidden = false
    public var isOpaque = true
    public var clipsToBounds = false
    public var isUserInteractionEnabled = true
    public var translatesAutoresizingMaskIntoConstraints = true
    public var contentMode: ContentMode = .scaleToFill
    public var tag = 0
    public var layer = CALayer()
    public private(set) var subviews: [UIView] = []
    public private(set) weak var superview: UIView?
    public var safeAreaInsets: UIEdgeInsets { _currentSafeInsets() }

    public override init() { super.init() }
    public init(frame: CGRect) { self.frame = frame; super.init() }

    public func addSubview(_ view: UIView) { view.superview = self; subviews.append(view) }
    public func removeFromSuperview() { superview?.subviews.removeAll { $0 === self }; superview = nil }
    public func sizeToFit() {}
    public func setNeedsLayout() {}
    public func layoutIfNeeded() {}
    public func setNeedsDisplay() {}
    public func endEditing(_ force: Bool) -> Bool { true }
    public func setContentHuggingPriority(_ priority: Float, for axis: Int) {}
    public func setContentCompressionResistancePriority(_ priority: Float, for axis: Int) {}
}

open class UILabel: UIView {
    public var text: String?
    public var font: UIFont!
    public var textColor: UIColor!
    public var textAlignment: NSTextAlignment = .natural
    public var numberOfLines = 1
}
open class UIImageView: UIView {
    public var image: UIImage?
    public init(image: UIImage?) { self.image = image; super.init() }
    public override init() { super.init() }
    public override init(frame: CGRect) { super.init(frame: frame) }
}
open class UIControl: UIView {
    public struct State: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State([])
        public static let highlighted = State(rawValue: 1)
        public static let disabled = State(rawValue: 2)
        public static let selected = State(rawValue: 4)
    }
    public var isEnabled = true
    public var isSelected = false
}
open class UIButton: UIControl {
    public func setTitle(_ title: String?, for state: State) {}
    public func setImage(_ image: UIImage?, for state: State) {}
    public func setTitleColor(_ color: UIColor?, for state: State) {}
}
open class UITextField: UIControl {
    public var text: String?
    public var placeholder: String?
    public var font: UIFont?
    public var textColor: UIColor?
    public var textAlignment: NSTextAlignment = .natural
}
open class UISwitch: UIControl { public var isOn = false }
open class UISlider: UIControl {
    public var value: Float = 0
    public var minimumValue: Float = 0
    public var maximumValue: Float = 1
}
open class UIScrollView: UIView {
    public var contentSize: CGSize = .zero
    public var contentOffset: CGPoint = .zero
    public var contentInset = UIEdgeInsets.zero
    public var showsVerticalScrollIndicator = true
    public var showsHorizontalScrollIndicator = true
    public var isScrollEnabled = true
}
open class UITextView: UIScrollView {
    public var text: String!
    public var font: UIFont?
    public var textColor: UIColor?
    public var isEditable = true
    public var isSelectable = true
    public var textAlignment: NSTextAlignment = .natural
}
open class UIActivityIndicatorView: UIView {
    public enum Style: Int, Sendable { case medium = 100, large = 101 }
    public var hidesWhenStopped = true
    public var color: UIColor!
    public init(style: Style) { super.init() }
    public override init() { super.init() }
    public func startAnimating() {}
    public func stopAnimating() {}
}

open class UIViewController: UIResponder {
    public var view: UIView! = UIView()
    public var title: String?
    public var preferredContentSize: CGSize = .zero
    public override init() { super.init() }
    open func viewDidLoad() {}
    open func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)? = nil) { completion?() }
    open func dismiss(animated: Bool, completion: (() -> Void)? = nil) { completion?() }
}

open class UIHostingController<Content: View>: UIViewController {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init() }
}

// MARK: - Representables

/// What a UIKit-backed view becomes in a headless render: a labelled placeholder box.
public struct _RepresentablePlaceholder: View, PrimitiveView {
    public typealias Body = Never
    let typeName: String
    public init(typeName: String) { self.typeName = typeName }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        ctx.runtime.warn("\(typeName) wraps a UIKit view, which cannot be rendered; showing a placeholder")
        let box = ZStack {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Text(typeName).font(.caption).foregroundStyle(.secondary).padding(4)
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
        resolveView(box, ctx, into: &out)
    }
}

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
}
extension UIViewRepresentable {
    public var body: _RepresentablePlaceholder { _RepresentablePlaceholder(typeName: String(describing: Self.self)) }
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
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
}
extension UIViewControllerRepresentable {
    public var body: _RepresentablePlaceholder { _RepresentablePlaceholder(typeName: String(describing: Self.self)) }
    public static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator) {}
}
extension UIViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void {}
}

// MARK: - @UIApplicationDelegateAdaptor

@propertyWrapper
public struct UIApplicationDelegateAdaptor<DelegateType: NSObject & UIApplicationDelegate>: DynamicProperty {
    final class Box { var delegate: DelegateType? }
    let box = Box()
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {}

    public var wrappedValue: DelegateType {
        if let d = box.delegate { return d }
        // Swift cannot construct an arbitrary NSObject subclass from a metatype (its init() is not
        // `required`), so reading the delegate instance is the one thing this shim cannot do.
        fatalError("@UIApplicationDelegateAdaptor: the \(DelegateType.self) instance is not available when rendering")
    }
}
extension UIApplicationDelegateAdaptor where DelegateType: ObservableObject {
    public var projectedValue: ObservedObject<DelegateType>.Wrapper { ObservedObject<DelegateType>.Wrapper(object: wrappedValue) }
}
