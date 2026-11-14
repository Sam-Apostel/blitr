// `import PDFKit`: documents report their page count and page sizes (read from the file's page objects);
// pages draw and thumbnail as blank white sheets, and PDFView is shown as a placeholder.
@_exported import Foundation
import UIKit

public enum PDFDisplayBox: Int, Sendable { case mediaBox, cropBox, bleedBox, trimBox, artBox }
public enum PDFDisplayMode: Int, Sendable { case singlePage, singlePageContinuous, twoUp, twoUpContinuous }
public enum PDFDisplayDirection: Int, Sendable { case vertical, horizontal }

open class PDFPage: NSObject, @unchecked Sendable {
    let mediaBox: CGRect
    open weak var document: PDFDocument?
    open var label: String?
    open var rotation = 0
    open var string: String? { nil }
    open var attributedString: NSAttributedString? { nil }
    open var numberOfCharacters: Int { 0 }
    open var annotations: [AnyObject] { [] }
    init(mediaBox: CGRect) { self.mediaBox = mediaBox; super.init() }
    public override init() { mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792); super.init() }
    public convenience init?(image: UIImage) { self.init(mediaBox: CGRect(origin: .zero, size: image.size)) }
    open func bounds(for box: PDFDisplayBox) -> CGRect { mediaBox }
    open func setBounds(_ bounds: CGRect, for box: PDFDisplayBox) {}
    /// Fills the page white: the page's content is not rendered here.
    open func draw(with box: PDFDisplayBox, to context: CGContext) {
        ShimDiagnostics.warn("PDFPage.draw: PDF content is not rendered here; pages draw blank")
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.restoreGState()
    }
    open func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
        ShimDiagnostics.warn("PDFPage.thumbnail: PDF content is not rendered here; thumbnails are blank")
        let scale = min(size.width / max(mediaBox.width, 1), size.height / max(mediaBox.height, 1))
        let target = CGSize(width: max(1, mediaBox.width * scale), height: max(1, mediaBox.height * scale))
        return UIGraphicsImageRenderer(size: target).image { $0.cgContext.setFillColor(CGColor(gray: 1, alpha: 1)); $0.fill(CGRect(origin: .zero, size: target)) }
    }
    open func dataRepresentation() -> Data? { nil }
}

open class PDFDocument: NSObject, @unchecked Sendable {
    public let documentURL: URL?
    private var pages: [PDFPage]
    open weak var delegate: AnyObject?
    open var documentAttributes: [AnyHashable: Any]?
    open var isEncrypted: Bool { false }
    open var isLocked: Bool { false }
    open var string: String? { nil }
    open var pageCount: Int { pages.count }

    public override init() { documentURL = nil; pages = []; super.init() }
    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, url: url)
    }
    public convenience init?(data: Data) { self.init(data: data, url: nil) }
    private init?(data: Data, url: URL?) {
        guard data.starts(with: Array("%PDF".utf8)) else { return nil }
        documentURL = url
        pages = PDFDocument.pageBoxes(String(decoding: data, as: UTF8.self)).map(PDFPage.init(mediaBox:))
        super.init()
        pages.forEach { $0.document = self }
    }

    /// Media boxes of the page objects (the default letter size where a page names none).
    static func pageBoxes(_ text: String) -> [CGRect] {
        guard let pageRegex = try? NSRegularExpression(pattern: #"/Type\s*/Page(?![s\w])"#),
              let boxRegex = try? NSRegularExpression(pattern: #"/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]"#) else { return [] }
        let ns = text as NSString
        let boxes = boxRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> CGRect? in
            let v = (1...4).compactMap { Double(ns.substring(with: m.range(at: $0))) }
            return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]) : nil
        }
        let count = pageRegex.numberOfMatches(in: text, range: NSRange(location: 0, length: ns.length))
        let fallback = boxes.last ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        return (0..<count).map { $0 < boxes.count && boxes.count >= count ? boxes[$0] : fallback }
    }

    open func page(at index: Int) -> PDFPage? { pages.indices.contains(index) ? pages[index] : nil }
    open func index(for page: PDFPage) -> Int { pages.firstIndex { $0 === page } ?? NSNotFound }
    open func insert(_ page: PDFPage, at index: Int) { pages.insert(page, at: max(0, min(index, pages.count))); page.document = self }
    open func removePage(at index: Int) { if pages.indices.contains(index) { pages.remove(at: index) } }
    open func exchangePage(at indexA: Int, withPageAt indexB: Int) { pages.swapAt(indexA, indexB) }
    open func dataRepresentation() -> Data? { nil }
    @discardableResult open func write(to url: URL) -> Bool { false }
    open func unlock(withPassword password: String) -> Bool { true }
    open func findString(_ string: String, withOptions options: NSString.CompareOptions = []) -> [AnyObject] { [] }
}

/// Shown as a placeholder when wrapped in a representable (PDF pages are not rendered).
open class PDFView: UIView {
    open var document: PDFDocument?
    open var autoScales = false
    open var displayMode = PDFDisplayMode.singlePageContinuous
    open var displayDirection = PDFDisplayDirection.vertical
    open var displaysPageBreaks = true
    open var displayBox = PDFDisplayBox.cropBox
    open var displaysAsBook = false
    open var pageBreakMargins = UIEdgeInsets.zero
    open var minScaleFactor: CGFloat = 0.25
    open var maxScaleFactor: CGFloat = 4
    open var scaleFactor: CGFloat = 1
    open var scaleFactorForSizeToFit: CGFloat { 1 }
    open var usePageViewController = false
    open var currentPage: PDFPage? { document?.page(at: 0) }
    open weak var delegate: AnyObject?
    open func go(to page: PDFPage) {}
    open func goToNextPage(_ sender: Any?) {}
    open func goToPreviousPage(_ sender: Any?) {}
    open func usePageViewController(_ enable: Bool, withViewOptions options: [AnyHashable: Any]? = nil) { usePageViewController = enable }
}
