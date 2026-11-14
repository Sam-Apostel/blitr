// UIKit's AttributedString attribute scope (`a.uiKit.font`, `AttributeContainer().foregroundColor = UIColor.red`).
// Its dynamic member lookup is disfavored, so where SwiftUI's attribute of the same name also fits
// (`a.foregroundColor = .white`, `a.font = .body`) SwiftUI's wins, as it does on iOS.
import Foundation
import SwiftUI

extension AttributeScopes {
    public var uiKit: UIKitAttributes.Type { UIKitAttributes.self }

    public struct UIKitAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let paragraphStyle: ParagraphStyleAttribute
        public let kern: KernAttribute
        public let tracking: TrackingAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let strikethroughColor: StrikethroughColorAttribute
        public let underlineColor: UnderlineColorAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let ligature: LigatureAttribute
        public let obliqueness: ObliquenessAttribute
        public let expansion: ExpansionAttribute
        public let foundation: AttributeScopes.FoundationAttributes

        public enum FontAttribute: AttributedStringKey {
            public typealias Value = UIFont
            public static let name = "NSFont"
        }
        public enum ForegroundColorAttribute: AttributedStringKey {
            public typealias Value = UIColor
            public static let name = "NSColor"
        }
        public enum BackgroundColorAttribute: AttributedStringKey {
            public typealias Value = UIColor
            public static let name = "NSBackgroundColor"
        }
        public enum ParagraphStyleAttribute: AttributedStringKey {
            public typealias Value = NSParagraphStyle
            public static let name = "NSParagraphStyle"
        }
        public enum KernAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "NSKern"
        }
        public enum TrackingAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "NSTracking"
        }
        public enum StrikethroughStyleAttribute: AttributedStringKey {
            public typealias Value = NSUnderlineStyle
            public static let name = "NSStrikethrough"
        }
        public enum UnderlineStyleAttribute: AttributedStringKey {
            public typealias Value = NSUnderlineStyle
            public static let name = "NSUnderline"
        }
        public enum StrikethroughColorAttribute: AttributedStringKey {
            public typealias Value = UIColor
            public static let name = "NSStrikethroughColor"
        }
        public enum UnderlineColorAttribute: AttributedStringKey {
            public typealias Value = UIColor
            public static let name = "NSUnderlineColor"
        }
        public enum BaselineOffsetAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "NSBaselineOffset"
        }
        public enum LigatureAttribute: AttributedStringKey {
            public typealias Value = Int
            public static let name = "NSLigature"
        }
        public enum ObliquenessAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "NSObliqueness"
        }
        public enum ExpansionAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "NSExpansion"
        }
    }
}

extension AttributeDynamicLookup {
    @_disfavoredOverload
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.UIKitAttributes, T>) -> T { fatalError() }
}
