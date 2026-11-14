// UIImage from an ImageRenderer's pixels (SwiftUI/Views/ImageRenderer.swift).

import SwiftUI

extension UIImage {
    public convenience init(cgImage: CGImage) { self.init(source: .rendered(cgImage.rendered.rescaled(to: 1))) }
    public convenience init(cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation) {
        self.init(source: .rendered(cgImage.rendered.rescaled(to: scale)))
    }
    public var cgImage: CGImage? {
        if case .rendered(let rendered) = source { return CGImage(rendered: rendered) }
        return nil
    }
}

extension ImageRenderer {
    public var uiImage: UIImage? {
        rendered(scale: scale).map { UIImage(source: .rendered($0)) }
    }
}
