import SwiftUI

// Custom conformances to the style protocols that have makeBody(configuration:) (GroupBoxStyle has its own file).
// Each style also reads the environment, which must work on a style like it does on a view.

struct StackedLabeledContentStyle: LabeledContentStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration.label.font(.caption).foregroundStyle(.secondary)
            configuration.content.font(.body.weight(.semibold))
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct PlusMinusDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: configuration.isExpanded ? "minus.circle.fill" : "plus.circle.fill")
                    configuration.label
                    Spacer()
                }
            }
            if configuration.isExpanded {
                configuration.content.padding(.leading, 28)
            }
        }
    }
}

struct RedMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.red.opacity(0.15), in: Capsule())
            .tint(.red)
    }
}

struct VerticalControlGroupStyle: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) { configuration.content }
        }
    }
}

struct SpeedometerGaugeStyle: GaugeStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).rotation(.degrees(135))
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            Circle().trim(from: 0, to: 0.75 * configuration.value).rotation(.degrees(135))
                .stroke(scheme == .dark ? Color.yellow : Color.purple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            VStack(spacing: 0) {
                configuration.currentValueLabel.font(.title3.bold())
                configuration.label.font(.caption2)
            }
        }
        .frame(width: 90, height: 90)
    }
}

struct ChipDatePickerStyle: DatePickerStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Text(configuration.selection, format: .dateTime.year().month().day())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.green.opacity(0.2), in: Capsule())
            if configuration.displayedComponents.contains(.hourAndMinute) {
                Image(systemName: "clock")
            }
        }
    }
}

private let exampleDate = Date(timeIntervalSince1970: 1_750_000_000)

struct CustomContainerStylesExample: View {
    @State private var expanded = true
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Custom labeled content", value: "Stacked")
                .labeledContentStyle(StackedLabeledContentStyle())
            LabeledContent("Disabled", value: "Dimmed by the style")
                .labeledContentStyle(StackedLabeledContentStyle())
                .disabled(true)
            LabeledContent("Automatic", value: "Trailing")
                .labeledContentStyle(.automatic)

            DisclosureGroup("Expanded custom disclosure", isExpanded: $expanded) { Text("Shown content") }
                .disclosureGroupStyle(PlusMinusDisclosureStyle())
            DisclosureGroup("Collapsed custom disclosure", isExpanded: $collapsed) { Text("Hidden") }
                .disclosureGroupStyle(PlusMinusDisclosureStyle())
            DisclosureGroup("Automatic disclosure", isExpanded: $expanded) { Text("Built-in look") }
                .disclosureGroupStyle(.automatic)
            Spacer()
        }
        .padding()
    }
}

struct CustomControlStylesExample: View {
    @State private var date = exampleDate
    @State private var notes = "Plain text editor"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Menu("Custom menu") { Button("One") {} }.menuStyle(RedMenuStyle())
                Menu("Button menu") { Button("One") {} }.menuStyle(.button)
                Menu("Automatic") { Button("One") {} }.menuStyle(.automatic)
            }

            ControlGroup {
                Button("Cut", systemImage: "scissors") {}
                Button("Copy", systemImage: "doc.on.doc") {}
            } label: {
                Text("Custom control group")
            }
            .controlGroupStyle(VerticalControlGroupStyle())
            HStack {
                ControlGroup {
                    Button("Back", systemImage: "chevron.left") {}
                    Button("Forward", systemImage: "chevron.right") {}
                }
                .controlGroupStyle(.navigation)
                ControlGroup("More", systemImage: "ellipsis.circle") {
                    Button("A") {}
                    Button("B") {}
                }
                .controlGroupStyle(.menu)
            }

            HStack(spacing: 20) {
                Gauge(value: 0.65) { Text("km/h") } currentValueLabel: { Text("65") }
                    .gaugeStyle(SpeedometerGaugeStyle())
                Gauge(value: 0.4) { Text("Fuel") } currentValueLabel: { Text("40") }
                    .gaugeStyle(.accessoryCircular)
                Gauge(value: 0.4) { Text("Built-in") }
                    .gaugeStyle(.automatic)
            }

            DatePicker("Custom date picker", selection: $date)
                .datePickerStyle(ChipDatePickerStyle())
            DatePicker("Compact", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker("Field (macOS)", selection: $date)
                .datePickerStyle(.field)
            DatePicker("Stepper field (macOS)", selection: $date, displayedComponents: .date)
                .datePickerStyle(.stepperField)

            TextEditor(text: $notes)
                .textEditorStyle(.plain)
                .frame(height: 40)
            Spacer()
        }
        .padding()
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview("Custom container styles") {
    CustomContainerStylesExample()
}

#Preview("Custom control styles") {
    CustomControlStylesExample()
}
