// `UIColor(resource:)` / `UIImage(resource:)` for generated asset symbols (SwiftUI/Compat/AssetResources.swift).

import SwiftUI

extension UIColor {
    public convenience init(resource: ColorResource) { self.init(named: resource.name)! }
}

extension UIImage {
    public convenience init(resource: ImageResource) { self.init(named: resource.name)! }
}
