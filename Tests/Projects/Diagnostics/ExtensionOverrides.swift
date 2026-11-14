import SwiftUI
import UIKit

// Overrides in extensions compile on iOS only because UIKit's members are @objc dynamic. The tool leaves
// them out with a warning each (Tests/Projects/run.sh checks the warnings); the override in the class body
// below is kept, and its text is drawn.

extension UINavigationController {
    @available(iOS 15.0, *)
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = { true }()
    }
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { print("shake") }
        super.motionEnded(motion, with: event)
    }
}

class Fruit { var name: String { "fruit" } }
final class Apple: Fruit { override var name: String { "Bramley, kept from the class body" } }

struct ExtensionOverridesView: View {
    var body: some View {
        Text(Apple().name).padding()
    }
}

#Preview { ExtensionOverridesView() }
