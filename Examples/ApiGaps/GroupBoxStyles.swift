import SwiftUI

// GroupBoxStyle: a custom conformance with makeBody(configuration:), a style that wraps the built-in
// look with GroupBox(configuration), and .automatic. The custom style reads the environment.

struct CardGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label.font(.caption.weight(.bold)).foregroundStyle(.orange)
            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme == .dark ? Color.orange.opacity(0.25) : Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TintedDefaultGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        GroupBox(configuration).foregroundStyle(.purple)
    }
}

extension GroupBoxStyle where Self == CardGroupBoxStyle {
    static var card: CardGroupBoxStyle { CardGroupBoxStyle() }
}

#Preview("Group box styles") {
    VStack(alignment: .leading, spacing: 14) {
        GroupBox("Custom group box") { Text("Orange card, label on top") }
            .groupBoxStyle(CardGroupBoxStyle())
        GroupBox {
            Text("Label closure, static member style")
        } label: {
            Label("Storage", systemImage: "externaldrive")
        }
        .groupBoxStyle(.card)
        GroupBox("Wrapped default") { Text("GroupBox(configuration)") }
            .groupBoxStyle(TintedDefaultGroupBoxStyle())
        VStack {
            GroupBox("Automatic") { Text("Built-in look") }
                .groupBoxStyle(.automatic)
            GroupBox { Text("No label, inherits the card style") }
        }
        .groupBoxStyle(.card)
        Spacer()
    }
    .padding()
}
