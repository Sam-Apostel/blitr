// `import SafariServices`: the in-app browser as a shell (a placeholder when wrapped).
@_exported import Foundation
import UIKit

open class SFSafariViewController: UIViewController {
    open class Configuration: NSObject {
        open var entersReaderIfAvailable = false
        open var barCollapsingEnabled = true
        public override init() { super.init() }
    }
    public enum DismissButtonStyle: Int, Sendable { case done, close, cancel }
    public let url: URL
    open weak var delegate: AnyObject?
    open var preferredBarTintColor: UIColor?
    open var preferredControlTintColor: UIColor?
    open var dismissButtonStyle = DismissButtonStyle.done
    public init(url URL: URL) { url = URL; super.init(nibName: nil, bundle: nil) }
    public init(url URL: URL, configuration: Configuration) { url = URL; super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { url = URL(fileURLWithPath: "/"); super.init(coder: coder) }
}
public protocol SFSafariViewControllerDelegate: AnyObject {}
