import Foundation
import OrchardKit

// Compiled into both the iPhone app and the TV app.

/// "31.5 kg", without a trailing ".0".
func kilogramsText(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value)) kg" : String(format: "%.1f kg", value)
}

extension Tree {
    /// SF Symbol standing for the fruit.
    var symbolName: String {
        switch fruit {
        case .apple: "drop.fill"
        case .pear: "leaf.fill"
        case .plum: "circle.fill"
        case .cherry: "heart.fill"
        }
    }

    var age: Int { Season.year - plantedYear }
}

enum Season {
    /// Fixed, so renders do not change with the calendar.
    static let year = 2026
}
