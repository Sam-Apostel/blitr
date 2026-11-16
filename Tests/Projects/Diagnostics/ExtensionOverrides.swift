import SwiftUI
import UIKit

// Overrides in extensions compile on iOS only because UIKit's members are @objc dynamic. The tool rewrites
// them (Tests/Projects/run.sh and Tests/Interaction/run.sh check the results):
// - of the app's own classes: moved into the class body, so viewDidLoad and draw(_:) below run;
// - UIWindow's motion events: a dynamic replacement, so the `shake` step reaches the handler below;
// - anything else (the navigation controller's viewDidLoad): left out with a warning.

extension UINavigationController {
    @available(iOS 15.0, *)
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = { true }()
    }
}

extension Notification.Name {
    static let deviceShook = Notification.Name("deviceShook")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceShook, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

class Fruit { var name: String { "fruit" } }
final class Apple: Fruit { override var name: String { "Bramley, kept from the class body" } }

/// Draws a filled circle; its draw(_:) is declared in an extension.
final class DotView: UIView {}

extension DotView {
    override func draw(_ rect: CGRect) {
        UIColor.systemTeal.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
    }
    override var intrinsicContentSize: CGSize { CGSize(width: 60, height: 60) }
}

/// A controller whose view is set up in viewDidLoad, declared in an extension.
final class GreetingController: UIViewController {
    let label = UILabel()
}

extension GreetingController {
    override func viewDidLoad() {
        super.viewDidLoad()
        label.text = "Set up in viewDidLoad"
        label.textColor = .systemIndigo
        label.frame = CGRect(x: 0, y: 0, width: 240, height: 30)
        view.addSubview(label)
    }
}

struct Dot: UIViewRepresentable {
    func makeUIView(context: Context) -> DotView {
        let view = DotView()
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: DotView, context: Context) {}
}

struct Greeting: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GreetingController { GreetingController() }
    func updateUIViewController(_ controller: GreetingController, context: Context) {}
}

struct ExtensionOverridesView: View {
    @State private var shakes = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(Apple().name)
            Dot().frame(width: 60, height: 60)
            Greeting().frame(width: 240, height: 30)
            Text("Shakes: \(shakes)")
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .deviceShook)) { _ in shakes += 1 }
    }
}

#Preview { ExtensionOverridesView() }
