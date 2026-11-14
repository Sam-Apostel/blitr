// macOS and watchOS style members: checkbox toggles, radio-group pickers, link and accessory-bar buttons,
// square-bordered text fields, and the watchOS and macOS list styles. Drawn with macOS metrics (estimated).

// MARK: - Toggle

/// macOS: a 14pt rounded square, filled with the accent color and checked when on.
public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        _Checkbox(isOn: configuration.isOn, label: AnyView(configuration.label))
    }
}
extension ToggleStyle where Self == CheckboxToggleStyle {
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

struct _Checkbox: View {
    let isOn: Bool
    let label: AnyView
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(SystemColor.background)))
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(isOn ? Color.clear : Color(SystemColor.gray3), lineWidth: 1)
                if isOn {
                    CheckmarkShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 8, height: 6.5)
                }
            }
            .frame(width: 14, height: 14)
            label
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Picker

/// macOS: the options as radio buttons, one per line.
public struct RadioGroupPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == RadioGroupPickerStyle {
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}
enum PickerRadioKey: EnvironmentKey { static let defaultValue = false }

struct _RadioCircle: View {
    let isOn: Bool
    var body: some View {
        ZStack {
            Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(SystemColor.background)))
            Circle().stroke(isOn ? Color.clear : Color(SystemColor.gray3), lineWidth: 1)
            if isOn { Circle().fill(Color.white).frame(width: 6, height: 6) }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Buttons

/// macOS: the label as a link, in the link color.
public struct LinkButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        configuration.label.foregroundStyle(Color(SystemColor.link))
    }
}
extension PrimitiveButtonStyle where Self == LinkButtonStyle {
    public static var link: LinkButtonStyle { LinkButtonStyle() }
}

/// macOS accessory bar (a filter bar above a list): a small rounded button; the action variant is borderless.
public struct AccessoryBarButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 5))
    }
}
public struct AccessoryBarActionButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
    }
}
extension PrimitiveButtonStyle where Self == AccessoryBarButtonStyle {
    public static var accessoryBar: AccessoryBarButtonStyle { AccessoryBarButtonStyle() }
}
extension PrimitiveButtonStyle where Self == AccessoryBarActionButtonStyle {
    public static var accessoryBarAction: AccessoryBarActionButtonStyle { AccessoryBarActionButtonStyle() }
}

// MARK: - Text fields

/// macOS: a field with a square border.
public struct SquareBorderTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}

// MARK: - Lists

/// watchOS: rows as separate platters (drawn as the inset grouped list, with a warning).
public struct CarouselListStyle: ListStyle { public init() {} }
/// watchOS: rows that curve away at the top and bottom of the screen (drawn as the inset grouped list).
public struct EllipticalListStyle: ListStyle { public init() {} }
/// macOS: a plain list in a border (drawn as the plain list).
public struct BorderedListStyle: ListStyle {
    public init() {}
    public init(alternatesRowBackgrounds: Bool) {}
}
extension ListStyle where Self == CarouselListStyle { public static var carousel: CarouselListStyle { CarouselListStyle() } }
extension ListStyle where Self == EllipticalListStyle { public static var elliptical: EllipticalListStyle { EllipticalListStyle() } }
extension ListStyle where Self == BorderedListStyle {
    public static var bordered: BorderedListStyle { BorderedListStyle() }
    public static func bordered(alternatesRowBackgrounds: Bool) -> BorderedListStyle { BorderedListStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

extension ListStyle {
    /// The drawn look for the platform styles above, or nil for the others.
    var _platformKind: ListStyleKind? {
        switch self {
        case is CarouselListStyle, is EllipticalListStyle:
            ShimDiagnostics.warn("\(Self.self) (watchOS) is drawn as the inset grouped list")
            return .insetGrouped
        case is BorderedListStyle:
            ShimDiagnostics.warn("BorderedListStyle (macOS) is drawn as the plain list, without its border")
            return .plain
        default: return nil
        }
    }
}
