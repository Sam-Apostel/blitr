// DatePicker, ColorPicker, DisclosureGroup, GroupBox, ControlGroup.

// MARK: - DatePicker

public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let hourAndMinute = DatePickerComponents(rawValue: 1)
    public static let date = DatePickerComponents(rawValue: 2)
}

enum DatePickerGraphicalKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var datePickerGraphical: Bool {
        get { self[DatePickerGraphicalKey.self] }
        set { self[DatePickerGraphicalKey.self] = newValue }
    }
}
func formatted(_ date: Date, _ format: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = format
    return f.string(from: date)
}

struct _DatePill: View {
    let text: String
    /// Height of the pill on iOS 26/27 (nil: label height + 14).
    var glassHeight: CGFloat? = nil
    @Environment(\.designLanguage) private var design
    @Environment(\.isElevatedPresentation) private var inSheet
    var body: some View {
        if design.isGlass {
            // measured: iOS 27.0 simulator (ControlsInputs): 12pt side padding; 34.33pt tall alone,
            // 36pt when the time is shown too; capsule.
            let fill = inSheet ? ControlGlassMetrics.sheetPillFill(design) : SystemColor.tertiaryFill
            return AnyView(Text(verbatim: text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(minHeight: glassHeight)
                .background(Color(fill), in: Capsule()))
        }
        return AnyView(Text(verbatim: text)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8)))
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
    private let _tvOSCheck = tvOSUnavailable("DatePicker")
    let selection: Binding<Date>
    let components: DatePickerComponents
    let label: Label?
    var minimumDate: Date?
    var maximumDate: Date?
    var forcedKind: DatePickerKind?
    @Environment(\.datePickerGraphical) private var datePickerGraphical
    @Environment(\.datePickerStyleBox) private var styleBox
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.designLanguage) private var design

    var date: Date { selection.wrappedValue }

    init(selection: Binding<Date>, components: DatePickerComponents, label: Label?, minimumDate: Date? = nil, maximumDate: Date? = nil) {
        self.selection = selection
        self.components = components
        self.label = label
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
    }

    public var body: some View {
        if forcedKind == nil, let make = styleBox?.make {
            make(DatePickerStyleConfiguration(
                label: .init(view: label.map { AnyView($0) } ?? AnyView(EmptyView())), selection: selection,
                minimumDate: minimumDate, maximumDate: maximumDate, displayedComponents: components))
        } else {
            builtIn(forcedKind ?? styleBox?.kind ?? (datePickerGraphical ? .graphical : .compact))
        }
    }

    private func builtIn(_ kind: DatePickerKind) -> some View {
        let graphical = kind == .graphical
        return VStack(spacing: 8) {
            HStack(spacing: design.isGlass ? 4 : 6) {
                let pillHeight: CGFloat? = components.contains(.hourAndMinute) ? 36 : nil
                ControlLabel(label: label)
                if kind == .field || kind == .stepperField {
                    _DateField(date: date, components: components, stepper: kind == .stepperField)
                } else {
                    if !graphical && components.contains(.date) { _DatePill(text: formatted(date, "MMM d, yyyy"), glassHeight: pillHeight) }
                    if components.contains(.hourAndMinute) { _DatePill(text: formatted(date, "h:mm a"), glassHeight: pillHeight) }
                }
            }
            if graphical && components.contains(.date) { _GraphicalCalendar(date: date) }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .axInfo(context: { ctx in
            let labelText = label.map { axText(resolveNodes($0, ctx.child("axLabel"))) } ?? ""
            var parts: [String] = []
            if components.contains(.date) { parts.append(formatted(date, "MMM d, yyyy")) }
            if components.contains(.hourAndMinute) { parts.append(formatted(date, "h:mm a")) }
            return AccessibilityInfo {
                $0.isElement = true
                $0.role = "datePicker"
                $0.addTraits = graphical ? [.adjustable] : [.button]
                $0.children = .ignore
                $0.label = labelText.isEmpty ? nil : labelText
                $0.value = parts.joined(separator: ", ")
                $0.isTapTarget = true
                $0.systemHitSlop = true
                $0.isEnabled = isEnabled
            }
        })
        .interaction(.date(selection))
    }
}

extension DatePicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(titleKey))
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(titleKey), minimumDate: range.lowerBound, maximumDate: range.upperBound)
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(titleKey), minimumDate: range.lowerBound)
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(titleKey), maximumDate: range.upperBound)
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(title))
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(title), minimumDate: range.lowerBound, maximumDate: range.upperBound)
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(title), minimumDate: range.lowerBound)
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, components: displayedComponents, label: Text(title), maximumDate: range.upperBound)
    }
}

extension DatePicker {
    public init(selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, components: displayedComponents, label: label())
    }
    public init(selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, components: displayedComponents, label: label(), minimumDate: range.lowerBound, maximumDate: range.upperBound)
    }
    public init(selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, components: displayedComponents, label: label(), minimumDate: range.lowerBound)
    }
    public init(selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, components: displayedComponents, label: label(), maximumDate: range.upperBound)
    }
}

// MARK: - ColorPicker

struct ColorWell: View {
    let color: Color
    @Environment(\.designLanguage) private var design
    var body: some View {
        // measured: iOS 27.0 simulator (ControlsInputs): the well is 28pt on iOS 26/27.
        let side: CGFloat = design.isGlass ? 28 : 30
        let k = side / 30
        return ZStack {
            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                .frame(width: side, height: side)
            Circle().fill(Color(SystemColor.background)).frame(width: 24 * k, height: 24 * k)
            Circle().fill(color).frame(width: 21 * k, height: 21 * k)
        }
        .frame(width: side, height: side)
    }
}

public struct ColorPicker<Label: View>: View {
    private let _tvOSCheck = tvOSUnavailable("ColorPicker")
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
        .axInfo {
            $0.isElement = true
            $0.role = "colorPicker"
            $0.addTraits = [.button]
            $0.children = .combine
            $0.isTapTarget = true
            $0.systemHitSlop = true
            $0.isEnabled = isEnabled
        }
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
    private let _tvOSCheck = tvOSUnavailable("DisclosureGroup")
    let label: Label
    let content: Content
    let binding: Binding<Bool>?
    @State private var local = false
    @Environment(\.disclosureGroupStyleBox) private var customStyle
    var forceDefault = false

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

    @Environment(\.designLanguage) private var design
    @Environment(\.renderPlatform) private var platform

    public var body: some View {
        if let custom = customStyle, !forceDefault {
            custom.make(AnyView(label), AnyView(content), Binding(
                get: { binding?.wrappedValue ?? local },
                set: { if let binding { binding.wrappedValue = $0 } else { local = $0 } }))
        } else {
            defaultBody
        }
    }

    private var defaultBody: some View {
        let expanded = binding?.wrappedValue ?? local
        if design.isGlass && platform != .tvOS {
            // measured: iOS 27.0 simulator (ControlsInputs): a 28.33pt row with the label in the
            // tint and a primary-coloured chevron, the content right under it, centred.
            return AnyView(VStack(spacing: 0) {
                HStack {
                    label.foregroundStyle(Color.accentColor)
                    Spacer(minLength: 8)
                    Chevron(direction: expanded ? .down : .right, width: 7, height: 12, weight: 2.2, color: AnyShapeStyle(Color.primary))
                }
                .padding(.vertical, 4)
                .axInfo {
                    $0.isElement = true
                    $0.addTraits = [.button]
                    $0.children = .combine
                    $0.value = expanded ? "expanded" : "collapsed"
                    $0.isTapTarget = true
                }
                if expanded { content.frame(maxWidth: .infinity) }
            })
        }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack {
                label
                Spacer(minLength: 8)
                Chevron(direction: expanded ? .down : .right, width: 7, height: 12, weight: 2.2, color: AnyShapeStyle(Color.accentColor))
            }
            .axInfo {
                $0.isElement = true
                $0.addTraits = [.button]
                $0.children = .combine
                $0.value = expanded ? "expanded" : "collapsed"
                $0.isTapTarget = true
            }
            if expanded { content }
        })
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
    private let _tvOSCheck = tvOSUnavailable("GroupBox")
    let label: Label
    let content: Content
    @Environment(\.designLanguage) private var design
    @Environment(\.groupBoxStyleBox) private var customStyle
    var forceDefault = false

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }
    public init(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        if let custom = customStyle, !forceDefault {
            custom.make(AnyView(label), AnyView(content))
        } else {
            defaultBody
        }
    }

    private var defaultBody: some View {
        if design.isGlass {
            // measured: iOS 27.0 simulator (ControlsInputs): 16pt padding, the content 2pt under
            // the label and centred, an 8pt corner.
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                if !(Label.self is EmptyView.Type) { label.font(.headline) }
                content.frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(SystemColor.secondaryBackground), in: RoundedRectangle(cornerRadius: ControlGlassMetrics.groupBoxRadius)))
        }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            if !(Label.self is EmptyView.Type) { label.font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(SystemColor.secondaryBackground), in: RoundedRectangle(cornerRadius: 8)))
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
    var labelView: AnyView?
    var forceDefault = false

    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public init<C: View, L: View>(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) where Content == C {
        self.content = content()
        self.labelView = AnyView(label())
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        if !forceDefault, let box = ctx.env.controlGroupStyleBox, let styled = _styledControlGroup(box, content: AnyView(content), label: labelView) {
            resolveView(styled, ctx.child("styled"), into: &out)
            return
        }
        if ctx.env.designLanguage.isGlass, ctx.env.renderPlatform != .tvOS {
            // measured: iOS 27.0 simulator (ControlsInputs): a 32pt capsule across the width,
            // equal segments, 14pt primary-coloured labels, no separators.
            let nodes = resolveNodes(content, ctx.child("group").with { $0.font = .system(size: 14); $0.foregroundStyle = AnyShapeStyle(Color.primary) })
            let view = HStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                    _NodeView(pair.element).frame(maxWidth: .infinity).frame(height: 32)
                }
            }
            .background(Color(SystemColor.tertiaryFill), in: Capsule())
            resolveView(view, ctx.child("view"), into: &out)
            return
        }
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
