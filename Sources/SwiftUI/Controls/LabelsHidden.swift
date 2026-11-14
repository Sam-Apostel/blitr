// `.labelsHidden()`: controls keep their label for accessibility but do not show it.

enum LabelsHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }
}

extension View {
    public func labelsHidden() -> some View { env { $0.labelsHidden = true } }
    public func labelsVisibility(_ visibility: Visibility) -> some View { env { $0.labelsHidden = visibility == .hidden } }
}

/// A control's leading label plus the flexible gap after it; resolves to nothing when labels are hidden,
/// so the control hugs its own size.
struct ControlLabel<Label: View>: View, PrimitiveView {
    typealias Body = Never
    let label: Label
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        if ctx.env.labelsHidden { return }
        resolveView(label, ctx, into: &out)
        out.append(SpacerNode(axis: ctx.env.stackAxis, minLength: 8))
    }
}
