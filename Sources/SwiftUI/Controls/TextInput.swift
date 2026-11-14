// TextField, SecureField, TextEditor. A screenshot has no focus or caret: the field shows its
// current text, or the placeholder when empty.

public protocol TextFieldStyle {}
public struct DefaultTextFieldStyle: TextFieldStyle { public init() {} }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {} }
public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {} }

extension TextFieldStyle where Self == DefaultTextFieldStyle { public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() } }
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() } }
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() } }

enum TextFieldBorderedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var textFieldBordered: Bool {
        get { self[TextFieldBorderedKey.self] }
        set { self[TextFieldBorderedKey.self] = newValue }
    }
}
extension View {
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        if style is SquareBorderTextFieldStyle { Runtime.current?.warn("SquareBorderTextFieldStyle (macOS) is drawn with a rounded border") }
        return env { $0.textFieldBordered = style is RoundedBorderTextFieldStyle || style is SquareBorderTextFieldStyle }
    }
}

struct _FieldBody: View {
    let text: String
    let placeholder: AnyView?
    var secure = false
    @Environment(\.textFieldBordered) private var bordered
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.renderPlatform) private var platform
    @Environment(\.designLanguage) private var design
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if platform == .tvOS { return AnyView(_TVFieldBody(text: text, placeholder: placeholder, secure: secure)) }
        let glass = design.isGlass
        let shown = secure ? String(repeating: "\u{2022}", count: text.count) : text
        let content = Group {
            if text.isEmpty {
                if let placeholder { placeholder.foregroundStyle(Color(SystemColor.placeholderText)) }
            } else if secure && glass {
                // measured: iOS 27.0 simulator (ControlsInputs): 7.33pt dots 10pt apart.
                HStack(spacing: TextFieldMetrics.dotPitch - TextFieldMetrics.dot) {
                    ForEach(0..<text.count, id: \.self) { _ in
                        Circle().fill(ForegroundStyle()).frame(width: TextFieldMetrics.dot, height: TextFieldMetrics.dot)
                    }
                }
                .padding(.leading, TextFieldMetrics.dotInset)
            } else {
                Text(verbatim: shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.5)
        if bordered && glass {
            // measured: iOS 27.0 simulator (ControlsInputs): 34pt, 8pt text inset, a hairline
            // CCCCCC / 333333 border, 4pt corners.
            let shape = RoundedRectangle(cornerRadius: TextFieldMetrics.borderRadius)
            return AnyView(content
                .padding(.horizontal, TextFieldMetrics.borderedInset)
                .frame(minHeight: 34)
                .background(Color(SystemColor.background), in: shape)
                .overlay(shape.strokeBorder(Color(TextFieldMetrics.border), lineWidth: 1 / max(1, displayScale))))
        }
        if !bordered && glass {
            // A plain field is 22pt tall (measured: iOS 27.0 simulator).
            return AnyView(content.frame(minHeight: TextFieldMetrics.plainHeight))
        }
        if bordered {
            return AnyView(content
                .padding(.horizontal, 7)
                .frame(minHeight: 34)
                .background(Color(SystemColor.background), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(SystemColor.separator), lineWidth: 0.5)))
        } else {
            return AnyView(content)
        }
    }
}

/// iOS 26/27 text field metrics. measured: iOS 27.0 simulator (ControlsInputs).
enum TextFieldMetrics {
    static let plainHeight: CGFloat = 22
    static let borderedInset: CGFloat = 8
    static let borderRadius: CGFloat = 4
    static let border = DynamicColor(0xCCCCCC, 0x333333)
    static let dot: CGFloat = 7.33
    static let dotPitch: CGFloat = 10
    static let dotInset: CGFloat = 0.67
}

public struct TextField<Label: View>: View {
    let text: String
    let placeholder: AnyView?
    /// Scripted steps type into the binding (Interaction/).
    var binding: Binding<String>?

    init(text: String, placeholder: AnyView?, binding: Binding<String>? = nil) {
        self.text = text
        self.placeholder = placeholder
        self.binding = binding
    }

    public var body: some View {
        _FieldBody(text: text, placeholder: placeholder)
            .axInfo(context: { ctx in .textInput(role: "textField", text: text, placeholder: placeholder, ctx) })
            .focusElement(role: "textField", activate: { Runtime.current?.warn("select on a text field would open the tvOS keyboard; text entry is not simulated") })
            .interaction { ctx in .textInput(binding, kind: "text field", ctx) }
    }
}

extension TextField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)), binding: text)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(titleKey)), binding: text)
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(title)), binding: text)
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(title)), binding: text)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void = {}) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)), binding: text)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)), binding: text)
    }
    public init<F: ParseableFormatStyle>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String {
        self.init(text: format.format(value.wrappedValue), placeholder: AnyView(prompt ?? Text(titleKey)))
    }
    public init<S: StringProtocol, F: ParseableFormatStyle>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String {
        self.init(text: format.format(value.wrappedValue), placeholder: AnyView(prompt ?? Text(title)))
    }
    public init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, prompt: Text? = nil) {
        self.init(text: formatter.string(for: value.wrappedValue) ?? "", placeholder: AnyView(prompt ?? Text(titleKey)))
    }
    public init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter, prompt: Text? = nil) {
        self.init(text: formatter.string(for: value.wrappedValue) ?? "", placeholder: AnyView(prompt ?? Text(title)))
    }
}

extension TextField {
    public init(text: Binding<String>, prompt: Text? = nil, axis: Axis? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: text.wrappedValue, placeholder: prompt.map { AnyView($0) } ?? AnyView(label()), binding: text)
    }
    public init<F: ParseableFormatStyle>(value: Binding<F.FormatInput>, format: F, prompt: Text? = nil, @ViewBuilder label: () -> Label)
    where F.FormatOutput == String {
        self.init(text: format.format(value.wrappedValue), placeholder: prompt.map { AnyView($0) } ?? AnyView(label()))
    }
}

// MARK: - SecureField

public struct SecureField<Label: View>: View {
    let text: String
    let placeholder: AnyView?
    var binding: Binding<String>?

    init(text: String, placeholder: AnyView?, binding: Binding<String>? = nil) {
        self.text = text
        self.placeholder = placeholder
        self.binding = binding
    }

    public var body: some View {
        _FieldBody(text: text, placeholder: placeholder, secure: true)
            .axInfo(context: { ctx in .textInput(role: "secureTextField", text: text, placeholder: placeholder, ctx) })
            .focusElement(role: "secureField", activate: { Runtime.current?.warn("select on a text field would open the tvOS keyboard; text entry is not simulated") })
            .interaction { ctx in .textInput(binding, kind: "secure field", ctx) }
    }
}

extension SecureField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)), binding: text)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(titleKey)), binding: text)
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(title)), binding: text)
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(title)), binding: text)
    }
}

extension SecureField {
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: text.wrappedValue, placeholder: prompt.map { AnyView($0) } ?? AnyView(label()), binding: text)
    }
}

// MARK: - TextEditor

public struct TextEditor: View {
    private let _tvOSCheck = tvOSUnavailable("TextEditor")
    let text: String
    var binding: Binding<String>?
    public init(text: Binding<String>) { self.text = text.wrappedValue; self.binding = text }

    public var body: some View {
        Text(verbatim: text)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(_TextEditorBorder())
            .axInfo(context: { ctx in .textInput(role: "textEditor", text: text, placeholder: nil, ctx) })
            .focusElement(role: "textEditor", activate: { Runtime.current?.warn("select on a text field would open the tvOS keyboard; text entry is not simulated") })
            .interaction { ctx in .textInput(binding, kind: "text editor", ctx) }
    }
}
