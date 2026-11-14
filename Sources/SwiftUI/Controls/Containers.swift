// DatePicker, ColorPicker, DisclosureGroup, GroupBox, ControlGroup.

// MARK: - DatePicker

public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let hourAndMinute = DatePickerComponents(rawValue: 1)
    public static let date = DatePickerComponents(rawValue: 2)
}

public protocol DatePickerStyle {}
public struct DefaultDatePickerStyle: DatePickerStyle { public init() {} }
public struct CompactDatePickerStyle: DatePickerStyle { public init() {} }
public struct GraphicalDatePickerStyle: DatePickerStyle { public init() {} }
public struct WheelDatePickerStyle: DatePickerStyle { public init() {} }
extension DatePickerStyle where Self == DefaultDatePickerStyle { public static var automatic: DefaultDatePickerStyle { DefaultDatePickerStyle() } }
extension DatePickerStyle where Self == CompactDatePickerStyle { public static var compact: CompactDatePickerStyle { CompactDatePickerStyle() } }
extension DatePickerStyle where Self == GraphicalDatePickerStyle { public static var graphical: GraphicalDatePickerStyle { GraphicalDatePickerStyle() } }
extension DatePickerStyle where Self == WheelDatePickerStyle { public static var wheel: WheelDatePickerStyle { WheelDatePickerStyle() } }

enum DatePickerGraphicalKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var datePickerGraphical: Bool {
        get { self[DatePickerGraphicalKey.self] }
        set { self[DatePickerGraphicalKey.self] = newValue }
    }
}
extension View {
    /// Compact and graphical are drawn; the wheel style is drawn as compact.
    public func datePickerStyle<S: DatePickerStyle>(_ style: S) -> some View {
        env { $0.datePickerGraphical = style is GraphicalDatePickerStyle }
    }
}

private func formatted(_ date: Date, _ format: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = format
    return f.string(from: date)
}

struct _DatePill: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct _GraphicalCalendar: View {
    let date: Date
    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let first = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? date
        let offset = cal.component(.weekday, from: first) - 1
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let rows = (offset + days + 6) / 7
        let selected = comps.day ?? 1
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: formatted(date, "LLLL yyyy")).fontWeight(.semibold)
                Chevron(direction: .right, width: 5, height: 9, weight: 2, color: AnyShapeStyle(Color.accentColor))
                Spacer()
                Chevron(direction: .left, width: 8, height: 14, weight: 2.4, color: AnyShapeStyle(Color.accentColor))
                Spacer().frame(width: 28)
                Chevron(direction: .right, width: 8, height: 14, weight: 2.4, color: AnyShapeStyle(Color.accentColor))
            }
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { pair in
                    Text(pair.element).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            let day = r * 7 + c - offset + 1
                            ZStack {
                                if day >= 1 && day <= days {
                                    if day == selected { Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40) }
                                    Text(verbatim: "\(day)").font(.system(size: 20))
                                        .foregroundStyle(day == selected ? Color.accentColor : Color(SystemColor.label))
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: 44)
                        }
                    }
                }
            }
        }
    }
}

public struct DatePicker<Label: View>: View {
    let date: Date
    let components: DatePickerComponents
    let label: Label?
    @Environment(\.datePickerGraphical) private var graphical
    @Environment(\.isEnabled) private var isEnabled

    init(date: Date, components: DatePickerComponents, label: Label?) {
        self.date = date
        self.components = components
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ControlLabel(label: label)
                if !graphical && components.contains(.date) { _DatePill(text: formatted(date, "MMM d, yyyy")) }
                if components.contains(.hourAndMinute) { _DatePill(text: formatted(date, "h:mm a")) }
            }
            if graphical && components.contains(.date) { _GraphicalCalendar(date: date) }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

extension DatePicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(titleKey))
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(titleKey))
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(titleKey))
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(titleKey))
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(title))
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(title))
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(title))
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: Text(title))
    }
}

extension DatePicker {
    public init(selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: label())
    }
    public init(selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: label())
    }
    public init(selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: label())
    }
    public init(selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(date: selection.wrappedValue, components: displayedComponents, label: label())
    }
}

// MARK: - ColorPicker

struct ColorWell: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                .frame(width: 30, height: 30)
            Circle().fill(Color(SystemColor.background)).frame(width: 24, height: 24)
            Circle().fill(color).frame(width: 21, height: 21)
        }
        .frame(width: 30, height: 30)
    }
}

public struct ColorPicker<Label: View>: View {
    let color: Color
    let label: Label
    @Environment(\.isEnabled) private var isEnabled

    public init(selection: Binding<Color>, supportsOpacity: Bool = true, @ViewBuilder label: () -> Label) {
        self.color = selection.wrappedValue
        self.label = label()
    }

    public var body: some View {
        HStack {
            ControlLabel(label: label)
            ColorWell(color: color)
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ColorPicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(title) }
    }
}

// MARK: - DisclosureGroup

public struct DisclosureGroup<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    let binding: Binding<Bool>?
    @State private var local = false

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.binding = isExpanded
        self.content = content()
        self.label = label()
    }
    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.binding = nil
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        let expanded = binding?.wrappedValue ?? local
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                label
                Spacer(minLength: 8)
                Chevron(direction: expanded ? .down : .right, width: 7, height: 12, weight: 2.2, color: AnyShapeStyle(Color.accentColor))
            }
            if expanded { content }
        }
    }
}

extension DisclosureGroup where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(titleKey) }
    }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

// MARK: - GroupBox

public struct GroupBox<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }
    public init(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !(Label.self is EmptyView.Type) { label.font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(SystemColor.secondaryBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension GroupBox where Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content) { EmptyView() }
    }
}

extension GroupBox where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

// MARK: - ControlGroup

public struct ControlGroup<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public init<C: View, L: View>(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) where Content == C {
        self.content = content()
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = resolveNodes(content, ctx.child("group"))
        let view = HStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 { Rectangle().fill(Color(SystemColor.separator)).frame(width: 1, height: 20) }
                _NodeView(pair.element).padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
        .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8))
        resolveView(view, ctx.child("view"), into: &out)
    }
}
