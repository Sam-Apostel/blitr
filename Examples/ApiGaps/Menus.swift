import SwiftUI

// Menu initialisers with a primary action, the menu indicator, menu order and the deprecated ContextMenu.
// A menu is drawn closed, so the items never show; the indicator does.

struct MenusExample: View {
    @State private var flavor = "Vanilla"
    @State private var log: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Menu("Text and primary action") {
                Button("Duplicate") {}
                Button("Rename") {}
            } primaryAction: {
                log.append("primary")
            }

            Menu("With an image", systemImage: "folder") {
                Button("Open") {}
            } primaryAction: {
                log.append("open")
            }

            Menu {
                Button("Add", systemImage: "plus") {}
                Divider()
                Button("Delete", role: .destructive) {}
            } label: {
                Label("Label closure", systemImage: "ellipsis.circle")
            } primaryAction: {
                log.append("label")
            }
            .menuOrder(.fixed)
            .menuActionDismissBehavior(.disabled)

            Divider()

            Menu("Bordered, indicator visible") { Button("One") {} }
                .buttonStyle(.bordered)
                .menuIndicator(.visible)
            Menu("Bordered, indicator hidden") { Button("One") {} }
                .buttonStyle(.bordered)
                .menuIndicator(.hidden)

            Picker("Menu picker", selection: $flavor) {
                Text("Vanilla").tag("Vanilla")
                Text("Chocolate").tag("Chocolate")
            }
            .pickerStyle(.menu)
            Picker("Menu picker, indicator hidden", selection: $flavor) {
                Text("Vanilla").tag("Vanilla")
                Text("Chocolate").tag("Chocolate")
            }
            .pickerStyle(.menu)
            .menuIndicator(.hidden)

            Divider()

            Text("Long press me: contextMenu(menuItems:preview:)")
                .contextMenu {
                    Button("Copy") {}
                    Button("Share") {}
                } preview: {
                    Text("Preview").padding()
                }
            Text("Deprecated ContextMenu value")
                .contextMenu(legacyMenu)
            Text("Optional ContextMenu, nil")
                .contextMenu(flavor.isEmpty ? legacyMenu : nil)
            Spacer()
        }
        .padding()
        .menuOrder(.priority)
    }

    private var legacyMenu: ContextMenu<Button<Text>> {
        ContextMenu { Button("Legacy item") {} }
    }
}

#Preview("Menus") {
    MenusExample()
}
