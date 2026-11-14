// Slider, Stepper, ProgressView, Gauge.

private func clamp01(_ v: Double) -> Double { v.isNaN ? 0 : max(0, min(1, v)) }

// MARK: - Slider

public struct Slider<Label: View, ValueLabel: View>: View {
    private let _tvOSCheck = tvOSUnavailable("Slider")
    let fraction: Double
    let minLabel: AnyView?
    let maxLabel: AnyView?
    var axLabel: String?
    /// Number of steps across the range (tick marks, iOS 26) and the neutral value's position, if given.
    var tickCount: Int?
    var neutralFraction: Double?
    /// What scripted steps can do to the slider (Interaction/).
    var handlers: InteractionHandlers?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var colorScheme

    init<V: BinaryFloatingPoint>(value: Binding<V>, bounds: ClosedRange<V>, minLabel: AnyView?, maxLabel: AnyView?,
                                 step: V.Stride? = nil, neutralValue: V? = nil) where V.Stride: BinaryFloatingPoint {
        let span = Double(bounds.upperBound - bounds.lowerBound)
        fraction = span > 0 ? clamp01(Double(value.wrappedValue - bounds.lowerBound) / span) : 0
        self.minLabel = minLabel
        self.maxLabel = maxLabel
        if let step, Double(step) > 0, span > 0 {
            let count = Int((span / Double(step)).rounded())
            if count >= 1 && count <= ControlGlassMetrics.sliderMaxTicks { tickCount = count }
        }
        if let neutralValue, span > 0 { neutralFraction = clamp01(Double(neutralValue - bounds.lowerBound) / span) }
        handlers = .slider(value, bounds: bounds, step: step)
    }

    public var body: some View {
        HStack(spacing: design.isGlass ? ControlGlassMetrics.sliderLabelSpacing : 12) {
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
        .interaction(handlers)
    }

    private var track: some View {
        design.isGlass ? AnyView(glassTrack) : AnyView(flatTrack)
    }

    /// iOS 26: 6pt capsule track, pill thumb, tick marks under the track when the slider has a step.
    private var glassTrack: some View {
        let m = ControlGlassMetrics.self
        let f = fraction
        let neutral = neutralFraction
        let ticks = tickCount
        return GeometryReader { proxy in
            let w = proxy.size.width
            let thumbW = m.sliderThumb.width
            let usable = max(0, w - thumbW)
            let x = f * usable
            // Filled part runs from the neutral value (default: the minimum) to the thumb's center.
            let from = neutral.map { $0 * usable + thumbW / 2 } ?? 0
            let to = x + thumbW / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color(m.sliderTrack)).frame(width: w, height: m.sliderTrackHeight)
                    .offset(y: (m.sliderHeight - m.sliderTrackHeight) / 2)
                Capsule().fill(Color.accentColor).frame(width: max(m.sliderTrackHeight, abs(to - from)), height: m.sliderTrackHeight)
                    .offset(x: min(from, to), y: (m.sliderHeight - m.sliderTrackHeight) / 2)
                if let ticks, ticks > 0 {
                    ForEach(0...ticks, id: \.self) { i in
                        Circle().fill(Color(SystemColor.tertiaryLabel)).frame(width: m.sliderTickSize, height: m.sliderTickSize)
                            .offset(x: thumbW / 2 + usable * CGFloat(i) / CGFloat(ticks) - m.sliderTickSize / 2,
                                    y: m.sliderHeight / 2 + m.sliderTrackHeight / 2 + 3)
                    }
                }
                Capsule().fill(Color.white).frame(width: thumbW, height: m.sliderThumb.height)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 3, x: 0, y: 1)
                    .offset(x: x, y: (m.sliderHeight - m.sliderThumb.height) / 2)
            }
            .frame(width: w, height: m.sliderHeight, alignment: .topLeading)
        }
        .frame(height: m.sliderHeight)
    }

    private var flatTrack: some View {
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
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil, step: step)
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil)
        axLabel = axPlainString(label())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil, step: step)
        axLabel = axPlainString(label())
    }
}

extension Slider {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label, @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()))
        axLabel = axPlainString(label())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()), step: step)
        axLabel = axPlainString(label())
    }
    /// iOS 26: the filled part of the track starts at `neutralValue` instead of the minimum.
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, neutralValue: V, @ViewBuilder label: () -> Label, @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: AnyView(minimumValueLabel()), maxLabel: AnyView(maximumValueLabel()), neutralValue: neutralValue)
        axLabel = axPlainString(label())
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, neutralValue: V, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, minLabel: nil, maxLabel: nil, neutralValue: neutralValue)
        axLabel = axPlainString(label())
    }
}

// MARK: - Stepper

public struct Stepper<Label: View>: View {
    private let _tvOSCheck = tvOSUnavailable("Stepper")
    let label: Label
    let canDecrement: Bool
    let canIncrement: Bool
    var axValue: String?
    /// What scripted steps can do to the stepper (Interaction/).
    var handlers: InteractionHandlers?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.designLanguage) private var design

    init(label: Label, canDecrement: Bool, canIncrement: Bool, axValue: String? = nil, handlers: InteractionHandlers? = nil) {
        self.label = label
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.axValue = axValue
        self.handlers = handlers
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
        .interaction(handlers)
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
        .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: design.isGlass ? ControlGlassMetrics.stepperSize.height / 2 : 8))
    }
}

extension Stepper {
    public init<V: Strideable>(value: Binding<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label(), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: nil, step: step))
    }
    public init<V: Strideable>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label(), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: bounds, step: step))
    }
    public init(onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ViewBuilder label: () -> Label) {
        self.init(label: label(), canDecrement: onDecrement != nil, canIncrement: onIncrement != nil, handlers: .stepper(onIncrement: onIncrement, onDecrement: onDecrement))
    }
}

extension Stepper where Label == Text {
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: nil, step: step))
    }
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: bounds, step: step))
    }
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(title), canDecrement: true, canIncrement: true, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: nil, step: step))
    }
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(title), canDecrement: value.wrappedValue > bounds.lowerBound, canIncrement: value.wrappedValue < bounds.upperBound, axValue: "\(value.wrappedValue)", handlers: .stepper(value, bounds: bounds, step: step))
    }
    public init(_ titleKey: LocalizedStringKey, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: Text(titleKey), canDecrement: onDecrement != nil, canIncrement: onIncrement != nil, handlers: .stepper(onIncrement: onIncrement, onDecrement: onDecrement))
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
        .modifier(ClockSpinModifier())
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
    /// tvOS draws larger indicators (est.: a 60pt spinner, an 8pt bar).
    @Environment(\.renderPlatform) private var platform

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
            case .circular: if platform == .tvOS { circular } else { circularIOS }
            case .automatic:
                if fraction != nil { linear } else if platform == .tvOS { circular } else { circularIOS }
            }
        }
    }

    private var linear: some View {
        // measured: iOS 27.0 simulator (ControlsIndicators): label, bar and current value 4pt
        // apart, the current value in caption. tvOS keeps its estimate.
        let tv = platform == .tvOS
        return VStack(alignment: .leading, spacing: tv ? 6 : 4) {
            if let label { label }
            LinearBar(fraction: fraction ?? 0.3, height: tv ? 8 : 4)
            if let currentValueLabel {
                currentValueLabel.font(tv ? .footnote : .caption).foregroundStyle(.secondary)
            }
        }
    }

    private var circular: some View {
        HStack(spacing: 8) {
            if let fraction {
                ZStack {
                    Circle().stroke(Color(SystemColor.secondaryFill), lineWidth: platform == .tvOS ? 6 : 3)
                    Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: platform == .tvOS ? 6 : 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: platform == .tvOS ? 60 : 20, height: platform == .tvOS ? 60 : 20)
            } else {
                Spinner(size: platform == .tvOS ? 60 : 20)
            }
            if let label { label.font(.footnote).foregroundStyle(.secondary) }
        }
    }

    /// iOS: the label sits under the indicator in the secondary colour, at the inherited font.
    /// measured: iOS 27.0 simulator (ControlsIndicators): a 20pt spinner, "Loading" 6.5pt below.
    /// A determinate circular ProgressView is drawn as a spinner too.
    private var circularIOS: some View {
        VStack(spacing: 6.5) {
            Spinner(size: 20)
            if let label { label.foregroundStyle(.secondary) }
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
            $0.gaugeCustomStyleBox = nil
            switch style {
            case is AccessoryLinearGaugeStyle: $0.gaugeStyleKind = .accessoryLinear
            case is AccessoryLinearCapacityGaugeStyle: $0.gaugeStyleKind = .accessoryLinearCapacity
            case is AccessoryCircularGaugeStyle, is CircularGaugeStyle: $0.gaugeStyleKind = .accessoryCircular
            case is AccessoryCircularCapacityGaugeStyle: $0.gaugeStyleKind = .accessoryCircularCapacity
            case is DefaultGaugeStyle, is LinearCapacityGaugeStyle, is LinearGaugeStyle: $0.gaugeStyleKind = .linearCapacity
            default:
                $0.gaugeStyleKind = .linearCapacity
                $0.gaugeCustomStyleBox = GaugeStyleBox { AnyView(_GaugeStyleApplier(style: style, configuration: $0)) }
            }
        }
    }
}

public struct Gauge<Label: View, CurrentValueLabel: View, BoundsLabel: View, MarkedValueLabels: View>: View {
    private let _tvOSCheck = tvOSUnavailable("Gauge")
    let fraction: Double
    let label: AnyView
    let current: AnyView?
    let minLabel: AnyView?
    let maxLabel: AnyView?
    @Environment(\.gaugeStyleKind) private var kind
    @Environment(\.gaugeCustomStyleBox) private var customStyle
    var forcedKind: GaugeStyleKind.Kind?
    @Environment(\.accentColor) private var explicitTint

    init(fraction: Double, label: AnyView, current: AnyView?, minLabel: AnyView?, maxLabel: AnyView?, forcedKind: GaugeStyleKind.Kind? = nil) {
        self.forcedKind = forcedKind
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
        if forcedKind == nil, let customStyle {
            customStyle.make(GaugeStyleConfiguration(
                value: fraction, label: .init(view: label), currentValueLabel: current.map { .init(view: $0) },
                minimumValueLabel: minLabel.map { .init(view: $0) }, maximumValueLabel: maxLabel.map { .init(view: $0) }))
        } else {
            builtInBody
        }
    }

    @ViewBuilder private var builtInBody: some View {
        switch forcedKind ?? kind {
        case .linearCapacity: capacity
        case .accessoryLinearCapacity, .accessoryLinear: linear
        case .accessoryCircular: circular(open: true)
        case .accessoryCircularCapacity: circular(open: false)
        }
    }

    /// The default (linearCapacity) gauge on iOS: label centred above a 16pt capsule bar with the
    /// bounds labels beside it, the current value centred below. measured: iOS 27.0 simulator
    /// (ControlsIndicators): bar 16pt, bounds labels 8pt from the bar, rows 10.67pt and 6.33pt
    /// apart, tertiary-fill track.
    private var capacity: some View {
        VStack(spacing: 0) {
            label
            HStack(spacing: 8) {
                if let minLabel { minLabel }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(SystemColor.tertiaryFill))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(16, proxy.size.width * fraction))
                    }
                }
                .frame(height: 16)
                if let maxLabel { maxLabel }
            }
            .padding(.top, 10.67)
            if let current { current.padding(.top, 6.33) }
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

    /// Accessory circular gauges. measured: iOS 27.0 simulator (ControlsIndicators): 58pt,
    /// 6pt strokes in the primary colour (unless tinted); the open gauge is a full 270° arc with a
    /// ring marking the value and the label under the gap, the capacity gauge a 35% track with
    /// the filled part from the top; current value about 25pt (17.67pt cap height).
    private func circular(open: Bool) -> some View {
        let span = open ? 0.75 : 1.0
        let rotation: Double = open ? 135 : -90
        let line: CGFloat = 6, side: CGFloat = 58
        let color = explicitTint ?? Color.primary
        let radius = (side - line) / 2
        let angle = (rotation + 360 * span * fraction) * .pi / 180
        return ZStack {
            if open {
                Circle().trim(from: 0, to: span).rotation(.degrees(rotation))
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                Circle().fill(Color(SystemColor.background)).frame(width: line - 2, height: line - 2)
                    .overlay(Circle().stroke(color, lineWidth: 2).frame(width: line + 2, height: line + 2))
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
                label.font(.caption2).offset(y: radius - 2)
            } else {
                Circle().stroke(color.opacity(0.35), lineWidth: line)
                Circle().trim(from: 0, to: max(fraction, 0.001)).rotation(.degrees(rotation))
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            if let current { current.font(.system(size: 25)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, line + 2) }
        }
        .padding(line / 2)
        .frame(width: side, height: side)
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
