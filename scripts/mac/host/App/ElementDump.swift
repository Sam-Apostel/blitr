import UIKit

// Walks the key window's accessibility hierarchy in process and writes each accessibility element's
// role, label, value, identifier, traits and frame (in points, window coordinates). Roles follow the
// renderer's `--accessibility-tree` names so the two can be matched by role and label.

enum ElementDump {
    @MainActor static func write(to url: URL) {
        AccessibilityActivation.enable()
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return }
        window.layoutIfNeeded()
        var elements: [[String: Any]] = []
        var visited = Set<ObjectIdentifier>()
        walk(window, window: window, depth: 0, into: &elements, visited: &visited)
        let screen = window.screen
        var doc: [String: Any] = [
            "version": 1,
            "device": UIDevice.current.name,
            "model": modelIdentifier(),
            "systemVersion": UIDevice.current.systemVersion,
            "size": ["width": window.bounds.width, "height": window.bounds.height],
            "scale": screen.scale,
            "colorScheme": window.traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
            "safeArea": ["top": window.safeAreaInsets.top, "bottom": window.safeAreaInsets.bottom,
                         "left": window.safeAreaInsets.left, "right": window.safeAreaInsets.right],
            "elements": elements,
        ]
        // The focused item (tvOS, or iOS with a keyboard): its frame in window coordinates.
        if let item = UIFocusSystem.focusSystem(for: window)?.focusedItem {
            let space = (item as? UIView).map { $0.superview ?? $0 } as UICoordinateSpace?
                ?? item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace ?? window
            let f = space.convert(item.frame, to: window)
            var focused: [String: Any] = ["frame": ["x": round2(f.minX), "y": round2(f.minY), "width": round2(f.width), "height": round2(f.height)]]
            if let object = item as? NSObject, let label = object.accessibilityLabel, !label.isEmpty { focused["label"] = label }
            doc["focused"] = focused
        }
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    private static func modelIdentifier() -> String {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
    }

    @MainActor private static func walk(_ object: NSObject, window: UIWindow, depth: Int,
                                        into elements: inout [[String: Any]], visited: inout Set<ObjectIdentifier>) {
        guard depth < 200, visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.accessibilityElementsHidden { return }

        if object.isAccessibilityElement {
            elements.append(describe(object, window: window))
            return
        }
        for child in children(of: object) {
            walk(child, window: window, depth: depth + 1, into: &elements, visited: &visited)
        }
    }

    @MainActor private static func children(of object: NSObject) -> [NSObject] {
        if let explicit = object.accessibilityElements as? [NSObject], !explicit.isEmpty { return explicit }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        }
        if let view = object as? UIView { return view.subviews }
        return []
    }

    @MainActor private static func describe(_ object: NSObject, window: UIWindow) -> [String: Any] {
        let traits = object.accessibilityTraits
        let frame = window.convert(object.accessibilityFrame, from: nil)
        var item: [String: Any] = [
            "role": role(traits),
            "label": object.accessibilityLabel ?? "",
            "traits": traitNames(traits),
            "frame": ["x": round2(frame.minX), "y": round2(frame.minY), "width": round2(frame.width), "height": round2(frame.height)],
        ]
        if let value = object.accessibilityValue, !value.isEmpty { item["value"] = value }
        if let identifiable = object as? UIAccessibilityIdentification, let id = identifiable.accessibilityIdentifier, !id.isEmpty {
            item["identifier"] = id
        }
        item["class"] = String(describing: type(of: object))
        return item
    }

    private static func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }

    /// UIKit's toggle trait has no public constant.
    private static let toggleTrait = UIAccessibilityTraits(rawValue: 1 << 53)
    private static let tabBarTrait: UIAccessibilityTraits = .tabBar

    private static func role(_ t: UIAccessibilityTraits) -> String {
        if t.contains(tabBarTrait) { return "tabBar" }
        if t.contains(.searchField) { return "searchField" }
        if t.contains(toggleTrait) { return "switch" }
        if t.contains(.adjustable) { return "adjustable" }
        if t.contains(.link) { return "link" }
        if t.contains(.button) { return "button" }
        if t.contains(.header) { return "header" }
        if t.contains(.image) { return "image" }
        if t.contains(.staticText) { return "staticText" }
        return "group"
    }

    private static func traitNames(_ t: UIAccessibilityTraits) -> [String] {
        let names: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.link, "link"), (.header, "header"), (.image, "image"), (.staticText, "staticText"),
            (.selected, "selected"), (toggleTrait, "toggle"), (.adjustable, "adjustable"), (.searchField, "searchField"),
            (.tabBar, "tabBar"), (.notEnabled, "notEnabled"), (.summaryElement, "summaryElement"),
            (.updatesFrequently, "updatesFrequently"), (.startsMediaSession, "startsMediaSession"),
            (.allowsDirectInteraction, "allowsDirectInteraction"), (.causesPageTurn, "causesPageTurn"),
            (.playsSound, "playsSound"), (.keyboardKey, "keyboardKey"),
        ]
        return names.filter { t.contains($0.0) }.map(\.1)
    }
}

/// SwiftUI only builds its accessibility tree when an assistive technology is running. Turning on the
/// automation flag (what XCTest does) makes the hosting views vend their elements in process.
enum AccessibilityActivation {
    private static var done = false
    @MainActor static func enable() {
        guard !done else { return }
        done = true
        let path = "/usr/lib/libAccessibility.dylib"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        typealias SetEnabled = @convention(c) (Bool) -> Void
        if let symbol = dlsym(handle, "_AXSSetAutomationEnabled") {
            unsafeBitCast(symbol, to: SetEnabled.self)(true)
        }
        if let symbol = dlsym(handle, "_AXSApplicationAccessibilitySetEnabled") {
            unsafeBitCast(symbol, to: SetEnabled.self)(true)
        }
    }
}
