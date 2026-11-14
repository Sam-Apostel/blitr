// `import QuickLook`: previews are not presented; QLPreviewController is a shell (a placeholder when wrapped).
@_exported import SwiftUI
import UIKit

extension View {
    public func quickLookPreview(_ item: Binding<URL?>) -> some View {
        if item.wrappedValue != nil { ShimDiagnostics.warn("quickLookPreview is presented: Quick Look previews are not drawn") }
        return self
    }
    public func quickLookPreview<Items: RandomAccessCollection>(_ selection: Binding<Items.Element?>, in items: Items) -> some View where Items.Element == URL {
        if selection.wrappedValue != nil { ShimDiagnostics.warn("quickLookPreview is presented: Quick Look previews are not drawn") }
        return self
    }
}

public protocol QLPreviewItem: AnyObject {
    var previewItemURL: URL? { get }
}
public protocol QLPreviewControllerDataSource: AnyObject {}
public protocol QLPreviewControllerDelegate: AnyObject {}
open class QLPreviewController: UIViewController {
    open weak var dataSource: QLPreviewControllerDataSource?
    open weak var delegate: QLPreviewControllerDelegate?
    open var currentPreviewItemIndex = 0
    open func reloadData() {}
    open func refreshCurrentPreviewItem() {}
    public class func canPreview(_ item: QLPreviewItem) -> Bool { false }
}
