// The body of UIKit's representables (UIKit/UIKitSystem.swift): UIKit views cannot be drawn here.

/// What a UIKit-backed view becomes in a headless render: a labelled placeholder box.
public struct _RepresentablePlaceholder: View, PrimitiveView {
    public typealias Body = Never
    let typeName: String
    public init(typeName: String) { self.typeName = typeName }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        ctx.runtime.warn("\(typeName) wraps a UIKit view, which cannot be rendered; showing a placeholder")
        let box = ZStack {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Text(typeName).font(.caption).foregroundStyle(.secondary).padding(4)
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
        resolveView(box, ctx, into: &out)
    }
}
