// SwiftUI's AttributedString attribute scope (`a.font`, `run.foregroundColor`, `AttributeContainer().kern`),
// as Apple declares it. Text(AttributedString) draws these attributes (see Text.attributedRuns).
import Foundation

extension AttributeScopes {
    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }

    public struct SwiftUIAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let kern: KerningAttribute
        public let tracking: TrackingAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: AttributeScopes.FoundationAttributes

        public enum FontAttribute: AttributedStringKey {
            public typealias Value = Font
            public static let name = "SwiftUI.Font"
        }
        public enum ForegroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.ForegroundColor"
        }
        public enum BackgroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.BackgroundColor"
        }
        public enum StrikethroughStyleAttribute: AttributedStringKey {
            public typealias Value = Text.LineStyle
            public static let name = "SwiftUI.StrikethroughStyle"
        }
        public enum UnderlineStyleAttribute: AttributedStringKey {
            public typealias Value = Text.LineStyle
            public static let name = "SwiftUI.UnderlineStyle"
        }
        public enum KerningAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.Kern"
        }
        public enum TrackingAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.Tracking"
        }
        public enum BaselineOffsetAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.BaselineOffset"
        }
    }
}

extension AttributeDynamicLookup {
    // Only the key path's type is used by AttributedString's dynamic members; the value is never read.
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T { fatalError() }
}
