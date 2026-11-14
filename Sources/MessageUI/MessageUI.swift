// `import MessageUI`: no mail or messages account is set up, so composing is not offered.
@_exported import Foundation
import UIKit

public enum MFMailComposeResult: Int, Sendable { case cancelled, saved, sent, failed }
public enum MessageComposeResult: Int, Sendable { case cancelled, sent, failed }
public protocol MFMailComposeViewControllerDelegate: AnyObject {}
public protocol MFMessageComposeViewControllerDelegate: AnyObject {}

open class MFMailComposeViewController: UINavigationController {
    public class func canSendMail() -> Bool { false }
    open weak var mailComposeDelegate: MFMailComposeViewControllerDelegate?
    open func setToRecipients(_ toRecipients: [String]?) {}
    open func setCcRecipients(_ ccRecipients: [String]?) {}
    open func setSubject(_ subject: String) {}
    open func setMessageBody(_ body: String, isHTML: Bool) {}
    open func addAttachmentData(_ attachment: Data, mimeType: String, fileName filename: String) {}
}
open class MFMessageComposeViewController: UINavigationController {
    public class func canSendText() -> Bool { false }
    public class func canSendAttachments() -> Bool { false }
    open weak var messageComposeDelegate: MFMessageComposeViewControllerDelegate?
    open var recipients: [String]?
    open var body: String?
}
