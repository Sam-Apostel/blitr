import SwiftUI

// Prints what the device profile gives an app: size classes, safe-area insets, screen size, idiom.
// Render it on different devices to see them change:
//   swiftui-screenshot render Examples/Devices.swift --device ipad-pro-13 --orientation landscape

struct DeviceInfo: View {
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.colorScheme) private var scheme

    private func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact?: return "compact"
        case .regular?: return "regular"
        case nil: return "nil"
        @unknown default: return "?"
        }
    }

    private func pt(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", Double(v)) }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = UIScreen.main.bounds.size
            NavigationStack {
                Form {
                    Section("Size classes") {
                        LabeledContent("horizontal", value: name(horizontal))
                        LabeledContent("vertical", value: name(vertical))
                    }
                    Section("Screen") {
                        LabeledContent("UIScreen.bounds", value: "\(pt(screen.width)) x \(pt(screen.height))")
                        LabeledContent("scale", value: "\(pt(UIScreen.main.scale))x")
                        LabeledContent("idiom", value: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone")
                        LabeledContent("orientation", value: UIDevice.current.orientation == .portrait ? "portrait" : "landscape")
                        LabeledContent("GeometryReader", value: "\(pt(proxy.size.width)) x \(pt(proxy.size.height))")
                    }
                    Section("Safe area insets") {
                        LabeledContent("top", value: pt(insets.top))
                        LabeledContent("leading", value: pt(insets.leading))
                        LabeledContent("bottom", value: pt(insets.bottom))
                        LabeledContent("trailing", value: pt(insets.trailing))
                    }
                    Section {
                        Label("Compact width stacks, regular width sits side by side", systemImage: "rectangle.split.2x1")
                        layoutDemo
                    } header: {
                        Text("Adaptive layout")
                    }
                }
                .navigationTitle("Device")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder private var layoutDemo: some View {
        let blocks = HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8).fill(.blue).frame(height: 36)
            RoundedRectangle(cornerRadius: 8).fill(.green).frame(height: 36)
        }
        if horizontal == .regular { blocks } else {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8).fill(.blue).frame(height: 36)
                RoundedRectangle(cornerRadius: 8).fill(.green).frame(height: 36)
            }
        }
    }
}

#Preview("Device info") { DeviceInfo() }

#Preview("Device info (landscape)", traits: .landscapeLeft) { DeviceInfo() }
