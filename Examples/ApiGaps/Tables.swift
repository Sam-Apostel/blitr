import SwiftUI

// Table: on iPhone only the first column shows, as a plain list; on iPad (and macOS) the table draws
// a header row and all columns. Render with --device ipad-pro-11 to see the columns.

struct Planet: Identifiable {
    let id: Int
    var name: String
    var moons: Int
    var kind: String
    var satellites: [Planet]? = nil
}

private let planets = [
    Planet(id: 1, name: "Mercury", moons: 0, kind: "Rocky"),
    Planet(id: 2, name: "Venus", moons: 0, kind: "Rocky"),
    Planet(id: 3, name: "Earth", moons: 1, kind: "Rocky", satellites: [Planet(id: 31, name: "Moon", moons: 0, kind: "Moon")]),
    Planet(id: 4, name: "Mars", moons: 2, kind: "Rocky"),
    Planet(id: 5, name: "Jupiter", moons: 95, kind: "Gas giant"),
    Planet(id: 6, name: "Saturn", moons: 146, kind: "Gas giant"),
]

struct SortableTableExample: View {
    @State private var sortOrder = [KeyPathComparator(\Planet.moons, order: .reverse)]
    @State private var selection: Set<Planet.ID> = [5]

    var body: some View {
        Table(planets.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name)
            TableColumn("Moons", value: \.moons) { planet in
                Text("\(planet.moons)").monospacedDigit()
            }
            .width(80)
            .alignment(.numeric)
            TableColumn("Kind", value: \.kind) { planet in
                Label(planet.kind, systemImage: planet.kind == "Rocky" ? "circle.fill" : "circle.dotted")
            }
            .width(min: 120, ideal: 160)
        }
    }
}

struct RowBuilderTableExample: View {
    @State private var selected: Planet.ID? = 3
    @State private var customization = TableColumnCustomization<Planet>()
    @State private var showsKind = true

    var body: some View {
        Table(of: Planet.self, selection: $selected, columnCustomization: $customization) {
            TableColumn("Name") { planet in
                Text(planet.name).fontWeight(.semibold)
            }
            .customizationID("name")
            TableColumn("Moons") { Text($0.moons, format: .number) }
                .alignment(.trailing)
                .customizationID("moons")
            if showsKind {
                TableColumn("Kind", value: \.kind)
                    .defaultVisibility(.visible)
                    .disabledCustomizationBehavior(.visibility)
            }
        } rows: {
            Section("Inner planets") {
                ForEach(planets.prefix(4)) { planet in
                    TableRow(planet)
                        .contextMenu { Button("Inspect") {} }
                        .draggable(planet.name)
                }
            }
            Section("Outer planets") {
                DisclosureTableRow(planets[4], isExpanded: .constant(true)) {
                    TableRow(Planet(id: 51, name: "Europa", moons: 0, kind: "Moon"))
                    TableRow(Planet(id: 52, name: "Io", moons: 0, kind: "Moon"))
                }
                TableRow(planets[5])
                    .itemProvider { NSItemProvider() }
            }
        }
        .tableStyle(.inset)
    }
}

struct PlainTableExample: View {
    var body: some View {
        VStack(spacing: 0) {
            Table(planets) {
                TableColumn("Name", value: \.name)
                TableColumn("Kind", value: \.kind)
            }
            .tableColumnHeaders(.hidden)
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .padding()
            Table(planets, children: \.satellites) {
                TableColumn("Name", value: \.name)
                TableColumnForEach(["A", "B"], id: \.self) { suffix in
                    TableColumn("Moons \(suffix)") { Text("\($0.moons)") }
                }
            }
        }
    }
}

#Preview("Sortable table") {
    SortableTableExample()
}

#Preview("Rows and sections") {
    RowBuilderTableExample()
}

#Preview("Headers hidden, hierarchy") {
    PlainTableExample()
}
