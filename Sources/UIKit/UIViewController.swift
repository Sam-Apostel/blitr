// View controllers: shells that keep their properties. A controller wrapped in a
// UIViewControllerRepresentable is shown by the representable host (UIRepresentable.swift).

import Foundation
import SwiftUI


open class UIViewController: UIResponder, UITraitEnvironment {
    public enum ModalPresentationStyle: Int, Sendable {
        case fullScreen = 0, pageSheet, formSheet, currentContext, custom, overFullScreen, overCurrentContext, popover, none = -1, automatic = -2
    }
    public enum ModalTransitionStyle: Int, Sendable { case coverVertical, flipHorizontal, crossDissolve, partialCurl }

    private var loadedView: UIView?
    open var view: UIView! {
        get {
            if let loadedView { return loadedView }
            loadView()
            if loadedView == nil { loadedView = UIView(frame: CGRect(origin: .zero, size: _currentCanvasSize())) }
            loadedView?.owningController = self
            viewDidLoad()
            return loadedView
        }
        set { loadedView = newValue; newValue?.owningController = self }
    }
    open var viewIfLoaded: UIView? { loadedView }
    open var isViewLoaded: Bool { loadedView != nil }
    open var title: String?
    open var preferredContentSize: CGSize = .zero
    open var modalPresentationStyle = ModalPresentationStyle.automatic
    open var modalTransitionStyle = ModalTransitionStyle.coverVertical
    open var isModalInPresentation = false
    open var definesPresentationContext = false
    open var overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
    open var additionalSafeAreaInsets = UIEdgeInsets.zero
    open var edgesForExtendedLayout = UIRectEdge.all
    open var extendedLayoutIncludesOpaqueBars = false
    open var hidesBottomBarWhenPushed = false
    open var restorationIdentifier: String?
    open var preferredStatusBarStyle: UIStatusBarStyle { .default }
    open var prefersStatusBarHidden: Bool { false }
    open var prefersHomeIndicatorAutoHidden: Bool { false }
    open var childForStatusBarStyle: UIViewController? { nil }
    open var childForStatusBarHidden: UIViewController? { nil }
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    open var traitCollection: UITraitCollection { .current }
    open var navigationItem: UINavigationItem { storedNavigationItem }
    private lazy var storedNavigationItem = UINavigationItem(title: title ?? "")
    open var tabBarItem: UITabBarItem! = UITabBarItem()
    open var toolbarItems: [UIBarButtonItem]?
    open var sheetPresentationController: UISheetPresentationController? { UISheetPresentationController(presentedViewController: self, presenting: nil) }
    open var popoverPresentationController: UIPopoverPresentationController? { UIPopoverPresentationController() }
    open var presentationController: UIPresentationController? { sheetPresentationController }
    open var transitionCoordinator: UIViewControllerTransitionCoordinator? { nil }
    open private(set) var children: [UIViewController] = []
    open private(set) weak var parent: UIViewController?
    open private(set) var presentedViewController: UIViewController?
    open private(set) weak var presentingViewController: UIViewController?
    open var navigationController: UINavigationController? {
        var current = parent
        while let c = current { if let nav = c as? UINavigationController { return nav }; current = c.parent }
        return nil
    }
    open var tabBarController: UITabBarController? {
        var current = parent
        while let c = current { if let tab = c as? UITabBarController { return tab }; current = c.parent }
        return nil
    }
    open var splitViewController: UISplitViewController? { nil }
    open var isBeingPresented: Bool { false }
    open var isBeingDismissed: Bool { false }
    open var isMovingToParent: Bool { false }
    open var isMovingFromParent: Bool { false }
    open var isEditing = false
    open override var next: UIResponder? { loadedView?.superview ?? parent }

    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init() }
    public convenience override init() { self.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init() }

    open func loadView() {}
    open func loadViewIfNeeded() { _ = view }
    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewIsAppearing(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewWillLayoutSubviews() {}
    open func viewDidLayoutSubviews() {}
    open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {}
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
    open func didReceiveMemoryWarning() {}
    open func setNeedsStatusBarAppearanceUpdate() {}
    open func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
    open func setNeedsUpdateOfSupportedInterfaceOrientations() {}
    open func setEditing(_ editing: Bool, animated: Bool) { isEditing = editing }
    open func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?, animated: Bool) { self.toolbarItems = toolbarItems }

    /// Presenting records the controller; nothing is shown, and the completion runs at once.
    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedViewController = viewControllerToPresent
        viewControllerToPresent.presentingViewController = self
        completion?()
    }
    open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedViewController?.presentingViewController = nil
        presentedViewController = nil
        completion?()
    }
    open func show(_ vc: UIViewController, sender: Any?) { present(vc, animated: true) }
    open func addChild(_ childController: UIViewController) {
        childController.removeFromParent()
        children.append(childController)
        childController.parent = self
    }
    open func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
    }
    open func willMove(toParent parent: UIViewController?) {}
    open func didMove(toParent parent: UIViewController?) {}
}

public protocol UIViewControllerTransitionCoordinator: AnyObject {}
open class UIPresentationController: NSObject {
    public let presentedViewController: UIViewController
    public init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        self.presentedViewController = presentedViewController
        super.init()
    }
    public weak var delegate: AnyObject?
}
open class UISheetPresentationController: UIPresentationController {
    open class Detent: NSObject {
        public struct Identifier: RawRepresentable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let medium = Identifier(rawValue: "com.apple.UIKit.medium")
            public static let large = Identifier(rawValue: "com.apple.UIKit.large")
        }
        public class func medium() -> Detent { Detent() }
        public class func large() -> Detent { Detent() }
        public class func custom(identifier: Identifier? = nil, resolver: @escaping (Any) -> CGFloat?) -> Detent { Detent() }
    }
    open var detents: [Detent] = [.large()]
    open var selectedDetentIdentifier: Detent.Identifier?
    open var largestUndimmedDetentIdentifier: Detent.Identifier?
    open var prefersGrabberVisible = false
    open var preferredCornerRadius: CGFloat?
    open var prefersScrollingExpandsWhenScrolledToEdge = true
    open var prefersEdgeAttachedInCompactHeight = false
    open func animateChanges(_ changes: () -> Void) { changes() }
}
open class UIPopoverPresentationController: NSObject {
    open var sourceView: UIView?
    open var sourceRect = CGRect.zero
    open var barButtonItem: UIBarButtonItem?
    open var permittedArrowDirections = 0
    public override init() { super.init() }
}

open class UINavigationController: UIViewController {
    public enum Operation: Int, Sendable { case none, push, pop }
    open var viewControllers: [UIViewController] = [] {
        didSet { viewControllers.forEach { addChild($0) } }
    }
    open var topViewController: UIViewController? { viewControllers.last }
    open var visibleViewController: UIViewController? { presentedViewController ?? topViewController }
    open weak var delegate: UINavigationControllerDelegate?
    open var isNavigationBarHidden = false
    open var isToolbarHidden = true
    open var hidesBarsOnSwipe = false
    open var hidesBarsOnTap = false
    public let navigationBar = UINavigationBar()
    public let toolbar = UIToolbar()
    open var interactivePopGestureRecognizer: UIGestureRecognizer? { popGesture }
    open var interactiveContentPopGestureRecognizer: UIGestureRecognizer? { popGesture }
    private let popGesture = UIScreenEdgePanGestureRecognizer()

    public init(rootViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [rootViewController]
        addChild(rootViewController)
    }
    public init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) { super.init(nibName: nil, bundle: nil) }
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open func pushViewController(_ viewController: UIViewController, animated: Bool) { viewControllers.append(viewController) }
    @discardableResult open func popViewController(animated: Bool) -> UIViewController? {
        guard viewControllers.count > 1 else { return nil }
        return viewControllers.removeLast()
    }
    @discardableResult open func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard viewControllers.count > 1 else { return nil }
        let popped = Array(viewControllers.dropFirst())
        viewControllers = Array(viewControllers.prefix(1))
        return popped
    }
    open func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) { self.viewControllers = viewControllers }
    open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) { isNavigationBarHidden = hidden }
    open func setToolbarHidden(_ hidden: Bool, animated: Bool) { isToolbarHidden = hidden }
}
public protocol UINavigationControllerDelegate: NSObjectProtocol {}

open class UITabBarController: UIViewController {
    open var viewControllers: [UIViewController]?
    open var selectedIndex = 0
    open var selectedViewController: UIViewController? { viewControllers.flatMap { $0.indices.contains(selectedIndex) ? $0[selectedIndex] : nil } }
    public let tabBar = UITabBar()
    open weak var delegate: AnyObject?
    open func setViewControllers(_ viewControllers: [UIViewController]?, animated: Bool) { self.viewControllers = viewControllers }
}
open class UISplitViewController: UIViewController {
    public enum Style: Int, Sendable { case unspecified, doubleColumn, tripleColumn }
    public enum Column: Int, Sendable { case primary, supplementary, secondary, compact }
    public init(style: Style) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open func setViewController(_ vc: UIViewController?, for column: Column) {}
    open func show(_ column: Column) {}
}
open class UIPageViewController: UIViewController {}
open class UITableViewController: UIViewController {
    public var tableView: UITableView! = UITableView(frame: .zero, style: .plain)
}
open class UICollectionViewController: UIViewController {}

open class UIAlertController: UIViewController {
    public enum Style: Int, Sendable { case actionSheet, alert }
    public let preferredStyle: Style
    open private(set) var actions: [UIAlertAction] = []
    open private(set) var textFields: [UITextField]?
    open var message: String?
    open var preferredAction: UIAlertAction?
    public init(title: String?, message: String?, preferredStyle: Style) {
        self.preferredStyle = preferredStyle
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.message = message
    }
    public required init?(coder: NSCoder) { preferredStyle = .alert; super.init(coder: coder) }
    open func addAction(_ action: UIAlertAction) { actions.append(action) }
    open func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        let field = UITextField()
        configurationHandler?(field)
        textFields = (textFields ?? []) + [field]
    }
}
open class UIAlertAction: NSObject {
    public enum Style: Int, Sendable { case `default`, cancel, destructive }
    public let title: String?
    public let style: Style
    open var isEnabled = true
    public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) { self.title = title; self.style = style; super.init() }
}

/// Hosts SwiftUI content. As a representable's controller it is drawn as its root view.
open class UIHostingController<Content: View>: UIViewController {
    public var rootView: Content
    public var sizingOptions: UIHostingControllerSizingOptions = []
    public var safeAreaRegions: SafeAreaRegions = .all
    public init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { fatalError("UIHostingController(coder:) is not available") }
    public func sizeThatFits(in size: CGSize) -> CGSize { size }
    var anyRootView: AnyView { AnyView(rootView) }
}
public struct UIHostingControllerSizingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let preferredContentSize = UIHostingControllerSizingOptions(rawValue: 1)
    public static let intrinsicContentSize = UIHostingControllerSizingOptions(rawValue: 2)
}
/// A UIView hosting SwiftUI content (iOS 16's UIHostingConfiguration / `_UIHostingView`).
open class _UIHostingView<Content: View>: UIView {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init(frame: .zero) }
    public required init?(coder: NSCoder) { fatalError("_UIHostingView(coder:) is not available") }
}

// MARK: - System controllers (presented by UIKit apps; shown as placeholders if wrapped)

open class UIImagePickerController: UINavigationController {
    public enum SourceType: Int, Sendable { case photoLibrary, camera, savedPhotosAlbum }
    public enum CameraCaptureMode: Int, Sendable { case photo, video }
    public enum CameraDevice: Int, Sendable { case rear, front }
    public enum CameraFlashMode: Int, Sendable { case off = -1, auto, on }
    public enum QualityType: Int, Sendable { case typeHigh, typeMedium, typeLow, type640x480, typeIFrame1280x720, typeIFrame960x540 }
    public struct InfoKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let mediaType = InfoKey(rawValue: "UIImagePickerControllerMediaType")
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage")
        public static let editedImage = InfoKey(rawValue: "UIImagePickerControllerEditedImage")
        public static let cropRect = InfoKey(rawValue: "UIImagePickerControllerCropRect")
        public static let mediaURL = InfoKey(rawValue: "UIImagePickerControllerMediaURL")
        public static let imageURL = InfoKey(rawValue: "UIImagePickerControllerImageURL")
        public static let mediaMetadata = InfoKey(rawValue: "UIImagePickerControllerMediaMetadata")
        public static let livePhoto = InfoKey(rawValue: "UIImagePickerControllerLivePhoto")
    }
    /// No camera, no photo library: a fresh install in a simulator-like environment.
    public class func isSourceTypeAvailable(_ sourceType: SourceType) -> Bool { sourceType != .camera }
    public class func availableMediaTypes(for sourceType: SourceType) -> [String]? { sourceType == .camera ? nil : ["public.image"] }
    public class func isCameraDeviceAvailable(_ cameraDevice: CameraDevice) -> Bool { false }
    open var sourceType = SourceType.photoLibrary
    open var mediaTypes: [String] = ["public.image"]
    open var allowsEditing = false
    open var cameraCaptureMode = CameraCaptureMode.photo
    open var cameraDevice = CameraDevice.rear
    open var cameraFlashMode = CameraFlashMode.auto
    open var showsCameraControls = true
    open var cameraOverlayView: UIView?
    open var videoQuality = QualityType.typeMedium
    open var videoMaximumDuration: TimeInterval = 600
    open weak var pickerDelegate: AnyObject?
    open func takePicture() {}
}
public protocol UIImagePickerControllerDelegate: NSObjectProtocol {}

open class UIActivity: NSObject {
    public struct ActivityType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let postToFacebook = ActivityType("com.apple.UIKit.activity.PostToFacebook")
        public static let message = ActivityType("com.apple.UIKit.activity.Message")
        public static let mail = ActivityType("com.apple.UIKit.activity.Mail")
        public static let print = ActivityType("com.apple.UIKit.activity.Print")
        public static let copyToPasteboard = ActivityType("com.apple.UIKit.activity.CopyToPasteboard")
        public static let assignToContact = ActivityType("com.apple.UIKit.activity.AssignToContact")
        public static let saveToCameraRoll = ActivityType("com.apple.UIKit.activity.SaveToCameraRoll")
        public static let addToReadingList = ActivityType("com.apple.UIKit.activity.AddToReadingList")
        public static let airDrop = ActivityType("com.apple.UIKit.activity.AirDrop")
        public static let openInIBooks = ActivityType("com.apple.UIKit.activity.OpenInIBooks")
        public static let markupAsPDF = ActivityType("com.apple.UIKit.activity.MarkupAsPDF")
    }
}
open class UIActivityViewController: UIViewController {
    public typealias CompletionWithItemsHandler = (UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void
    public let activityItems: [Any]
    open var excludedActivityTypes: [UIActivity.ActivityType]?
    open var completionWithItemsHandler: CompletionWithItemsHandler?
    public init(activityItems: [Any], applicationActivities: [UIActivity]?) {
        self.activityItems = activityItems
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { activityItems = []; super.init(coder: coder) }
}
open class UIDocumentPickerViewController: UIViewController {
    open weak var delegate: AnyObject?
    open var allowsMultipleSelection = false
    open var directoryURL: URL?
    public init(forOpeningContentTypes contentTypes: [Any], asCopy: Bool = false) { super.init(nibName: nil, bundle: nil) }
    public init(forExporting urls: [URL], asCopy: Bool = false) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
public protocol UIDocumentPickerDelegate: NSObjectProtocol {}

// MARK: - Bars and appearance proxies

/// Appearance customisation (`UINavigationBar.appearance()` and the rest) is accepted and not applied: the
/// system bars are drawn by SwiftUI. Using a proxy warns once.
@preconcurrency @MainActor
enum _AppearanceProxies {
    nonisolated(unsafe) static var proxies: [ObjectIdentifier: AnyObject] = [:]
    static let factories: [ObjectIdentifier: () -> AnyObject] = [
        ObjectIdentifier(UIView.self): { UIView(frame: .zero) },
        ObjectIdentifier(UINavigationBar.self): { UINavigationBar(frame: .zero) },
        ObjectIdentifier(UITabBar.self): { UITabBar(frame: .zero) },
        ObjectIdentifier(UIToolbar.self): { UIToolbar(frame: .zero) },
        ObjectIdentifier(UISearchBar.self): { UISearchBar(frame: .zero) },
        ObjectIdentifier(UILabel.self): { UILabel(frame: .zero) },
        ObjectIdentifier(UIButton.self): { UIButton(frame: .zero) },
        ObjectIdentifier(UISwitch.self): { UISwitch(frame: .zero) },
        ObjectIdentifier(UISlider.self): { UISlider(frame: .zero) },
        ObjectIdentifier(UISegmentedControl.self): { UISegmentedControl(frame: .zero) },
        ObjectIdentifier(UIPageControl.self): { UIPageControl(frame: .zero) },
        ObjectIdentifier(UITextField.self): { UITextField(frame: .zero) },
        ObjectIdentifier(UITextView.self): { UITextView(frame: .zero) },
        ObjectIdentifier(UIScrollView.self): { UIScrollView(frame: .zero) },
        ObjectIdentifier(UITableView.self): { UITableView(frame: .zero, style: .plain) },
        ObjectIdentifier(UICollectionView.self): { UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()) },
        ObjectIdentifier(UIImageView.self): { UIImageView(frame: .zero) },
        ObjectIdentifier(UIStackView.self): { UIStackView(frame: .zero) },
        ObjectIdentifier(UIProgressView.self): { UIProgressView(frame: .zero) },
        ObjectIdentifier(UIActivityIndicatorView.self): { UIActivityIndicatorView(frame: .zero) },
        ObjectIdentifier(UIRefreshControl.self): { UIRefreshControl(frame: .zero) },
        ObjectIdentifier(UIDatePicker.self): { UIDatePicker(frame: .zero) },
        ObjectIdentifier(UIWindow.self): { UIWindow(frame: .zero) },
    ]
    static func proxy<T: AnyObject>(_ type: T.Type, make: (() -> T)? = nil) -> T {
        ShimDiagnostics.warn("\(type).appearance() customisation is not applied; system UI is drawn with its default look")
        if let existing = proxies[ObjectIdentifier(type)] as? T { return existing }
        guard let made = make?() ?? factories[ObjectIdentifier(type)]?() as? T else {
            fatalError("\(type).appearance(): appearance proxies of UIKit subclasses are not available here")
        }
        proxies[ObjectIdentifier(type)] = made
        return made
    }
}

extension UIView {
    public class func appearance() -> Self { _AppearanceProxies.proxy(self) }
    public class func appearance(whenContainedInInstancesOf containerTypes: [AnyObject.Type]) -> Self { appearance() }
    public class func appearance(for trait: UITraitCollection) -> Self { appearance() }
}
extension UIBarItem {
    public class func appearance() -> Self { _AppearanceProxies.proxy(self) { self.init() } }
    public class func appearance(whenContainedInInstancesOf containerTypes: [AnyObject.Type]) -> Self { appearance() }
}

open class UIBarAppearance: NSObject {
    open var backgroundColor: UIColor?
    open var backgroundImage: UIImage?
    open var backgroundEffect: UIBlurEffect?
    open var shadowColor: UIColor?
    open var shadowImage: UIImage?
    public required override init() { super.init() }
    public convenience init(idiom: UIUserInterfaceIdiom) { self.init() }
    open func configureWithDefaultBackground() {}
    open func configureWithOpaqueBackground() {}
    open func configureWithTransparentBackground() {}
}
open class UIBarButtonItemAppearance: NSObject {
    public let normal = UIBarButtonItemStateAppearance()
    public let highlighted = UIBarButtonItemStateAppearance()
    public let disabled = UIBarButtonItemStateAppearance()
    public let focused = UIBarButtonItemStateAppearance()
    public override init() { super.init() }
    public convenience init(style: UIBarButtonItem.Style) { self.init() }
}
open class UIBarButtonItemStateAppearance: NSObject {
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var titlePositionAdjustment = UIOffset.zero
}
open class UINavigationBarAppearance: UIBarAppearance {
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var titlePositionAdjustment = UIOffset.zero
    open var buttonAppearance = UIBarButtonItemAppearance()
    open var backButtonAppearance = UIBarButtonItemAppearance()
    open var doneButtonAppearance = UIBarButtonItemAppearance()
    open func setBackIndicatorImage(_ backIndicatorImage: UIImage?, transitionMaskImage: UIImage?) {}
}
open class UIToolbarAppearance: UIBarAppearance { open var buttonAppearance = UIBarButtonItemAppearance() }
open class UITabBarAppearance: UIBarAppearance {
    open var stackedLayoutAppearance = UITabBarItemAppearance()
    open var inlineLayoutAppearance = UITabBarItemAppearance()
    open var compactInlineLayoutAppearance = UITabBarItemAppearance()
    open var selectionIndicatorTintColor: UIColor?
}
open class UITabBarItemAppearance: NSObject {
    public let normal = UITabBarItemStateAppearance()
    public let selected = UITabBarItemStateAppearance()
    public let disabled = UITabBarItemStateAppearance()
    public let focused = UITabBarItemStateAppearance()
    public override init() { super.init() }
}
open class UITabBarItemStateAppearance: NSObject {
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var iconColor: UIColor?
    open var badgeBackgroundColor: UIColor?
}

open class UINavigationBar: UIView {
    open var standardAppearance = UINavigationBarAppearance()
    open var compactAppearance: UINavigationBarAppearance?
    open var scrollEdgeAppearance: UINavigationBarAppearance?
    open var compactScrollEdgeAppearance: UINavigationBarAppearance?
    open var prefersLargeTitles = false
    open var isTranslucent = true
    open var barStyle = 0
    open var barTintColor: UIColor?
    open var titleTextAttributes: [NSAttributedString.Key: Any]?
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any]?
    open var backIndicatorImage: UIImage?
    open var backIndicatorTransitionMaskImage: UIImage?
    open var shadowImage: UIImage?
    open func setBackgroundImage(_ backgroundImage: UIImage?, for barMetrics: UIBarMetrics) {}
}
public enum UIBarMetrics: Int, Sendable { case `default`, compact, defaultPrompt = 101, compactPrompt }
open class UIToolbar: UIView {
    open var items: [UIBarButtonItem]?
    open var standardAppearance = UIToolbarAppearance()
    open var scrollEdgeAppearance: UIToolbarAppearance?
    open var isTranslucent = true
    open var barTintColor: UIColor?
    open func setItems(_ items: [UIBarButtonItem]?, animated: Bool) { self.items = items }
}
open class UITabBar: UIView {
    open var items: [UITabBarItem]?
    open var selectedItem: UITabBarItem?
    open var standardAppearance = UITabBarAppearance()
    open var scrollEdgeAppearance: UITabBarAppearance?
    open var isTranslucent = true
    open var barTintColor: UIColor?
    open var unselectedItemTintColor: UIColor?
}
open class UISearchBar: UIView {
    open var text: String?
    open var placeholder: String?
    open var searchTextField: UITextField { UITextField() }
    open var searchBarStyle = 0
}

@preconcurrency @MainActor
open class UIBarItem: NSObject {
    open var title: String?
    open var image: UIImage?
    open var isEnabled = true
    open var tag = 0
    open var accessibilityLabel: String?
    public required override init() { super.init() }
    open func setTitleTextAttributes(_ attributes: [NSAttributedString.Key: Any]?, for state: UIControl.State) {}
}
open class UIBarButtonItem: UIBarItem {
    public enum Style: Int, Sendable { case plain, bordered, done, prominent }
    public enum SystemItem: Int, Sendable {
        case done, cancel, edit, save, add, flexibleSpace, fixedSpace, compose, reply, action, organize, bookmarks, search, refresh
        case stop, camera, trash, play, pause, rewind, fastForward, undo, redo, pageCurl, close, writingTools
    }
    open var style = Style.plain
    open var tintColor: UIColor?
    open var customView: UIView?
    open var menu: UIMenu?
    open var primaryAction: UIAction?
    open var width: CGFloat = 0
    public required init() { super.init() }
    public convenience init(title: String?, style: Style, target: Any?, action: Selector?) { self.init(); self.title = title; self.style = style }
    public convenience init(image: UIImage?, style: Style, target: Any?, action: Selector?) { self.init(); self.image = image; self.style = style }
    public convenience init(barButtonSystemItem systemItem: SystemItem, target: Any?, action: Selector?) { self.init() }
    public convenience init(customView: UIView) { self.init(); self.customView = customView }
    public convenience init(systemItem: SystemItem, primaryAction: UIAction? = nil, menu: UIMenu? = nil) { self.init(); self.primaryAction = primaryAction; self.menu = menu }
    public convenience init(title: String? = nil, image: UIImage? = nil, primaryAction: UIAction? = nil, menu: UIMenu? = nil) {
        self.init(); self.title = title; self.image = image; self.primaryAction = primaryAction; self.menu = menu
    }
    public class func flexibleSpace() -> UIBarButtonItem { UIBarButtonItem() }
    public class func fixedSpace(_ width: CGFloat) -> UIBarButtonItem { let item = UIBarButtonItem(); item.width = width; return item }
}
open class UITabBarItem: UIBarItem {
    open var selectedImage: UIImage?
    open var badgeValue: String?
    open var badgeColor: UIColor?
    public required init() { super.init() }
    public convenience init(title: String?, image: UIImage?, selectedImage: UIImage?) { self.init(); self.title = title; self.image = image; self.selectedImage = selectedImage }
    public convenience init(title: String?, image: UIImage?, tag: Int) { self.init(); self.title = title; self.image = image; self.tag = tag }
}
open class UINavigationItem: NSObject {
    public enum LargeTitleDisplayMode: Int, Sendable { case automatic, always, never, inline }
    open var title: String?
    open var prompt: String?
    open var largeTitleDisplayMode = LargeTitleDisplayMode.automatic
    open var leftBarButtonItem: UIBarButtonItem?
    open var rightBarButtonItem: UIBarButtonItem?
    open var leftBarButtonItems: [UIBarButtonItem]?
    open var rightBarButtonItems: [UIBarButtonItem]?
    open var backBarButtonItem: UIBarButtonItem?
    open var backButtonTitle: String?
    open var hidesBackButton = false
    open var titleView: UIView?
    open var searchController: AnyObject?
    open var standardAppearance: UINavigationBarAppearance?
    open var scrollEdgeAppearance: UINavigationBarAppearance?
    public init(title: String) { self.title = title; super.init() }
}

// MARK: - App extensions

/// The items an app extension was given (none: nothing is shared into a render).
open class NSExtensionItem: NSObject, @unchecked Sendable {
    open var attributedTitle: NSAttributedString?
    open var attributedContentText: NSAttributedString?
    open var attachments: [NSItemProvider]?
    open var userInfo: [AnyHashable: Any]?
    public override init() { super.init() }
}
open class NSExtensionContext: NSObject, @unchecked Sendable {
    open var inputItems: [Any] { [] }
    public override init() { super.init() }
    open func completeRequest(returningItems items: [Any]?, completionHandler: ((Bool) -> Void)? = nil) { completionHandler?(true) }
    open func cancelRequest(withError error: Error) {}
    open func open(_ URL: URL, completionHandler: ((Bool) -> Void)? = nil) { completionHandler?(false) }
}
extension UIViewController {
    public var extensionContext: NSExtensionContext? { nil }
}
