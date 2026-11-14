// Slider, Stepper, ProgressView, Gauge.

private func clamp01(_ v: Double) -> Double { v.isNaN ? 0 : max(0, min(1, v)) }

// MARK: - Slider

public struct Slider<Label: View, ValueLabel: View>: View {
    let fraction: Double
    let minLabel: AnyView?
    let maxLabel: AnyView?
    var axLabel: String?
    @Environment(\.isEnabled) private var isEnabled

    init<V: BinaryFloatingPoint>(value: Binding<V>, bounds: ClosedRange<V>, minLabel: AnyView?, maxLabel: AnyView?) {
        let span = Double(bounds.upperBound - bounds.lowerBound)
        fraction = span > 0 ? clamp01(Double(value.wrappedValue - bounds.lowerBound) / span) : 0
        self.minLabel = minLabel
        self.maxLabel = maxLabel
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let minLabel { minLabel }
            track
            if let maxLabel { maxLabel }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .axInfo {
            $0.isElement = true
            $0.role = "slider"
            $0.addTraits = [.adjustable]
            $0.children = .ignore
            $0.label = axLabel
            $0.value = "\(Int((fraction * 100).rounded()))%"
            $0.isTapTarget = true
            $0.systemHitSlop = true
            $0.isEnabled = isEnabled
        }
    }

    private var track: some View {
        let f = fraction
        return GeometryReader { proxy in
            let w = proxy.size.width
            let x = f * max(0, w - 28)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(SystemColor.secondaryFill)).frame(width: w, height: 4)
                Capsule().fill(Color.accentColor).frame(width: x + 14, height: 4)
                Circle().fill(Color.white).frame(width: 28, height: 28).knobShadow().offset(x: x)
            }
            .frame(width: w, height: 28, alignment: .leading)
        }
        .frame(height: 28)
    }
}

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil)
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil)
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil)
        axLabel = axPlainString(label())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil)
        axLabel = axPlainString(label())
    }
}

extension Slider {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()))
        axLabel = axPlainString(label())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()))
        axLabel = axPlainString(label())
    }
}

// MARK: - Stepper

public struct Stepper<Label: View>: View {
    let label: Label
    let canDecrement: Bool
    let canIncrement: Bool
    var axValue: String?
    @Environment(\.isEnabled) private var isEnabled

    init(label: Label, canDecrement: Bool, canIncrement: Bool, axValue: String? = nil) {
        self.label = label
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.axValue = axValue
    }

    public var body: some View {
        HStack {
            ControlLabel(label: label)
            control
        }
        .opacity(isEnabled ? 1 : 0.5)
        .axInfo {
            $0.isElement = true
            $0.role = "stepper"
            $0.addTraits = [.adjustable]
            $0.children = .combine
            $0.value = axValue
            $0.isTapTarget = true
            $0.systemHitSlop = true
            $0.isEnabled = isEnabled
        }
    }

    private var control: some View {
        let ink = Color(SystemColor.label)
        return HStack(spacing: 0) {
            ZStack {
                Capsule().fill(ink).frame(width: 14, height: 2)
            }
            .frame(width: 46.5, height: 32).opacity(canDecrement ? 1 : 0.3)
            Rectangle().fill(Color(SystemColor.separator)).frame(width: 1, height: 16)
            ZStack {
                Capsule().fill(ink).frame(width: 14, height: 2)
                Capsule().fill(ink).frame(width: 2, height: 14)
            }
            .frame(width: 46.5, height: 32).opacity(canIncrement ? 1 : 0.3)
        }
        .frame(width: 94, height: 32)
        .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Stepper {
    public init<V: Strideable>(value: Binding<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label(), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)")
    }
    public init<V: Strideable>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label(), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)")
    }
    public init(onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ViewBuilder label: () -> Label) {
        self.init(label: label(), canDecrement: onDecrement != nil, canIncrement: onIncrement != nil)
    }
}

extension Stepper where Label == Text {
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)")
    }
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)")
    }
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(title), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)")
    }
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(title), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)")
    }
    public init(_ titleKey: LocalizedStringKey, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: onDecrement != nil, canIncrement: onIncrement != nil)
    }
}

// MARK: - Spinner and bars

private struct SpinnerTick: Shape {
    let index: Int
    nonisolated func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let tick = Path(roundedRect: CGRect(x: c.x - 1.2, y: c.y - 10, width: 2.6, height: 4.8), cornerRadius: 1.2, style: .circular)
        let t = CGAffineTransform(translationX: -c.x, y: -c.y)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(index) * .pi / 4))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        return tick.applying(t)
    }
}

struct Spinner: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                SpinnerTick(index: i).fill(Color(SystemColor.gray).opacity(1 - Double(i) * 0.115))
            }
        }
        .frame(width: 20, height: 20)
        .scaleEffect(size / 20)
        .frame(width: size, height: size)
    }
}

struct LinearBar: View {
    let fraction: Double
    var height: CGFloat = 4
    var body: some View {
        let f = clamp01(fraction)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(SystemColor.secondaryFill)).frame(width: proxy.size.width, height: height)
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * f, height: height)
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
    }
}

// MARK: - ProgressView

public struct ProgressViewStyleConfiguration {
    public struct Label: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView?
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view?.resolve(ctx, into: &out) }
    }
    public struct CurrentValueLabel: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView?
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view?.resolve(ctx, into: &out) }
    }
    public let fractionCompleted: Double?
    public let label: Label
    public let currentValueLabel: CurrentValueLabel
}

@MainActor @preconcurrency
public protocol ProgressViewStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ProgressViewStyleConfiguration
}

struct ProgressStyleBox {
    enum Kind { case automatic, linear, circular }
    var kind: Kind = .automatic
    var custom: (@MainActor (ProgressViewStyleConfiguration) -> AnyView)?
}
enum ProgressStyleKey: EnvironmentKey { static let defaultValue = ProgressStyleBox() }
extension EnvironmentValues {
    var progressStyleBox: ProgressStyleBox {
        get { self[ProgressStyleKey.self] }
        set { self[ProgressStyleKey.self] = newValue }
    }
}

public struct LinearProgressViewStyle: ProgressViewStyle {
    public init() {}
    public init(tint: Color?) {}
    public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { EmptyView() }
}
public struct CircularProgressViewStyle: ProgressViewStyle {
    public init() {}
    public init(tint: Color?) {}
    public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { EmptyView() }
}
public struct DefaultProgressViewStyle: ProgressViewStyle {
    public init() {}
    public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { EmptyView() }
}
extension ProgressViewStyle where Self == LinearProgressViewStyle { public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() } }
extension ProgressViewStyle where Self == CircularProgressViewStyle { public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() } }
extension ProgressViewStyle where Self == DefaultProgressViewStyle { public static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() } }

extension View {
    public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
        env {
            if style is LinearProgressViewStyle { $0.progressStyleBox = ProgressStyleBox(kind: .linear) }
            else if style is CircularProgressViewStyle { $0.progressStyleBox = ProgressStyleBox(kind: .circular) }
            else if style is DefaultProgressViewStyle { $0.progressStyleBox = ProgressStyleBox() }
            else {
                $0.progressStyleBox = ProgressStyleBox(kind: .automatic, custom: { config in
                    AnyView(_ProgressStyleApplier(style: style, config: config))
                })
            }
        }
    }
}

struct _ProgressStyleApplier<S: ProgressViewStyle>: View {
    let style: S
    let config: ProgressViewStyleConfiguration
    var body: some View { style.makeBody(configuration: config) }
}

public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    let fraction: Double?
    let label: AnyView?
    let currentValueLabel: AnyView?
    @Environment(\.progressStyleBox) private var styleBox

    init(fraction: Double?, label: AnyView?, currentValueLabel: AnyView?) {
        self.fraction = fraction
        self.label = label
        self.currentValueLabel = currentValueLabel
    }

    static func fraction<V: BinaryFloatingPoint>(_ value: V?, _ total: V) -> Double? {
        guard let value else { return nil }
        return total > 0 ? clamp01(Double(value / total)) : 0
    }

    public var body: some View {
        styled.axInfo {
            $0.isElement = true
            $0.role = "progress"
            $0.children = .combine
            $0.addTraits = [.updatesFrequently]
            if let fraction { $0.value = "\(Int((fraction * 100).rounded()))%" }
        }
    }

    @ViewBuilder private var styled: some View {
        if let custom = styleBox.custom {
            custom(ProgressViewStyleConfiguration(fractionCompleted: fraction, label: .init(view: label), currentValueLabel: .init(view: currentValueLabel)))
        } else {
            switch styleBox.kind {
            case .linear: linear
            case .circular: circular
            case .automatic:
                if fraction == nil { circular } else { linear }
            }
        }
    }

    private var linear: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { label }
            LinearBar(fraction: fraction ?? 0.3)
            if let currentValueLabel {
                currentValueLabel.font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var circular: some View {
        HStack(spacing: 8) {
            if let fraction {
                ZStack {
                    Circle().stroke(Color(SystemColor.secondaryFill), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            } else {
                Spinner()
            }
            if let label { label.font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() { self.init(fraction: nil, label: nil, currentValueLabel: nil) }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        self.init(fraction: ProgressView.fraction(value, total), label: nil, currentValueLabel: nil)
    }
}
extension ProgressView where CurrentValueLabel == EmptyView {
    public init(@ViewBuilder label: () -> Label) { self.init(fraction: nil, label: AnyView(label()), currentValueLabel: nil) }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ViewBuilder label: () -> Label) {
        self.init(fraction: ProgressView.fraction(value, total), label: AnyView(label()), currentValueLabel: nil)
    }
}
extension ProgressView {
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ViewBuilder label: () -> Label, @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        self.init(fraction: ProgressView.fraction(value, total), label: AnyView(label()), currentValueLabel: AnyView(currentValueLabel()))
    }
}
extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    public init(_ titleKey: LocalizedStringKey) { self.init(fraction: nil, label: AnyView(Text(titleKey)), currentValueLabel: nil) }
    public init<S: StringProtocol>(_ title: S) { self.init(fraction: nil, label: AnyView(Text(title)), currentValueLabel: nil) }
    public init<V: BinaryFloatingPoint>(_ titleKey: LocalizedStringKey, value: V?, total: V = 1.0) {
        self.init(fraction: ProgressView.fraction(value, total), label: AnyView(Text(titleKey)), currentValueLabel: nil)
    }
    public init<S: StringProtocol, V: BinaryFloatingPoint>(_ title: S, value: V?, total: V = 1.0) {
        self.init(fraction: ProgressView.fraction(value, total), label: AnyView(Text(title)), currentValueLabel: nil)
    }
}

// MARK: - Gauge

enum GaugeStyleKind {
    enum Kind { case linearCapacity, accessoryLinear, accessoryLinearCapacity, accessoryCircular, accessoryCircularCapacity }
}

public protocol GaugeStyle {}
public struct DefaultGaugeStyle: GaugeStyle { public init() {} }
public struct LinearCapacityGaugeStyle: GaugeStyle { public init() {} }
public struct AccessoryLinearGaugeStyle: GaugeStyle { public init() {} }
public struct AccessoryLinearCapacityGaugeStyle: GaugeStyle { public init() {} }
public struct AccessoryCircularGaugeStyle: GaugeStyle { public init() {} }
public struct AccessoryCircularCapacityGaugeStyle: GaugeStyle { public init() {} }

extension GaugeStyle where Self == DefaultGaugeStyle { public static var automatic: DefaultGaugeStyle { DefaultGaugeStyle() } }
extension GaugeStyle where Self == LinearCapacityGaugeStyle { public static var linearCapacity: LinearCapacityGaugeStyle { LinearCapacityGaugeStyle() } }
extension GaugeStyle where Self == AccessoryLinearGaugeStyle { public static var accessoryLinear: AccessoryLinearGaugeStyle { AccessoryLinearGaugeStyle() } }
extension GaugeStyle where Self == AccessoryLinearCapacityGaugeStyle { public static var accessoryLinearCapacity: AccessoryLinearCapacityGaugeStyle { AccessoryLinearCapacityGaugeStyle() } }
extension GaugeStyle where Self == AccessoryCircularGaugeStyle { public static var accessoryCircular: AccessoryCircularGaugeStyle { AccessoryCircularGaugeStyle() } }
extension GaugeStyle where Self == AccessoryCircularCapacityGaugeStyle { public static var accessoryCircularCapacity: AccessoryCircularCapacityGaugeStyle { AccessoryCircularCapacityGaugeStyle() } }

enum GaugeStyleKey: EnvironmentKey { static let defaultValue = GaugeStyleKind.Kind.linearCapacity }
extension EnvironmentValues {
    var gaugeStyleKind: GaugeStyleKind.Kind {
        get { self[GaugeStyleKey.self] }
        set { self[GaugeStyleKey.self] = newValue }
    }
}
extension View {
    public func gaugeStyle<S: GaugeStyle>(_ style: S) -> some View {
        env {
            switch style {
            case is AccessoryLinearGaugeStyle: $0.gaugeStyleKind = .accessoryLinear
            case is AccessoryLinearCapacityGaugeStyle: $0.gaugeStyleKind = .accessoryLinearCapacity
            case is AccessoryCircularGaugeStyle: $0.gaugeStyleKind = .accessoryCircular
            case is AccessoryCircularCapacityGaugeStyle: $0.gaugeStyleKind = .accessoryCircularCapacity
            default: $0.gaugeStyleKind = .linearCapacity
            }
        }
    }
}

public struct Gauge<Label: View, CurrentValueLabel: View, BoundsLabel: View, MarkedValueLabels: View>: View {
    let fraction: Double
    let label: AnyView
    let current: AnyView?
    let minLabel: AnyView?
    let maxLabel: AnyView?
    @Environment(\.gaugeStyleKind) private var kind

    init(fraction: Double, label: AnyView, current: AnyView?, minLabel: AnyView?, maxLabel: AnyView?) {
        self.fraction = clamp01(fraction)
        self.label = label
        self.current = current
        self.minLabel = minLabel
        self.maxLabel = maxLabel
    }

    static func fraction<V: BinaryFloatingPoint>(_ v: V, _ b: ClosedRange<V>) -> Double {
        let span = Double(b.upperBound - b.lowerBound)
        return span > 0 ? Double(v - b.lowerBound) / span : 0
    }

    public var body: some View {
        gaugeBody.axInfo {
            $0.isElement = true
            $0.role = "gauge"
            $0.children = .combine
            $0.value = "\(Int((fraction * 100).rounded()))%"
        }
    }

    @ViewBuilder private var gaugeBody: some View {
        switch kind {
        case .linearCapacity, .accessoryLinearCapacity, .accessoryLinear: linear
        case .accessoryCircular: circular(open: true)
        case .accessoryCircularCapacity: circular(open: false)
        }
    }

    private var linear: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label
                Spacer(minLength: 8)
                if let current { current.foregroundStyle(.secondary) }
            }
            LinearBar(fraction: fraction)
            if minLabel != nil || maxLabel != nil {
                HStack {
                    if let minLabel { minLabel }
                    Spacer(minLength: 8)
                    if let maxLabel { maxLabel }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func circular(open: Bool) -> some View {
        let span = open ? 0.75 : 1.0
        let rotation: Double = open ? 135 : -90
        return ZStack {
            Circle().trim(from: 0, to: span).rotation(.degrees(rotation))
                .stroke(Color(SystemColor.secondaryFill), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().trim(from: 0, to: span * max(fraction, 0.001)).rotation(.degrees(rotation))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if let current { current.font(.system(size: 16, weight: .medium)) }
        }
        .padding(2.5)
        .frame(width: 56, height: 56)
    }
}

extension Gauge where CurrentValueLabel == EmptyView, BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label) {
        self.init(fraction: Gauge.fraction(value, bounds), label: AnyView(label()), current: nil, minLabel: nil, maxLabel: nil)
    }
}
extension Gauge where BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        self.init(fraction: Gauge.fraction(value, bounds), label: AnyView(label()), current: AnyView(currentValueLabel()), minLabel: nil, maxLabel: nil)
    }
}
extension Gauge where MarkedValueLabels == EmptyView {
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, @ViewBuilder currentValueLabel: () -> CurrentValueLabel, @ViewBuilder minimumValueLabel: () -> BoundsLabel, @ViewBuilder maximumValueLabel: () -> BoundsLabel) {
        self.init(fraction: Gauge.fraction(value, bounds), label: AnyView(label()), current: AnyView(currentValueLabel()),
                  minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()))
    }
}
