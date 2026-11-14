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
        env { $0.textFieldBordered = style is RoundedBorderTextFieldStyle }
    }
}

struct _FieldBody: View {
    let text: String
    let placeholder: AnyView?
    var secure = false
    @Environment(\.textFieldBordered) private var bordered
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shown = secure ? String(repeating: "\u{2022}", count: text.count) : text
        let content = Group {
            if text.isEmpty {
                if let placeholder { placeholder.foregroundStyle(Color(SystemColor.placeholderText)) }
            } else {
                Text(verbatim: shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.5)
        if bordered {
            content
                .padding(.horizontal, 7)
                .frame(minHeight: 34)
                .background(Color(SystemColor.background), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(SystemColor.separator), lineWidth: 0.5))
        } else {
            content
        }
    }
}

public struct TextField<Label: View>: View {
    let text: String
    let placeholder: AnyView?

    init(text: String, placeholder: AnyView?) {
        self.text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        _FieldBody(text: text, placeholder: placeholder)
            .axInfo(context: { ctx in .textInput(role: "textField", text: text, placeholder: placeholder, ctx) })
    }
}

extension TextField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)))
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(titleKey)))
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(title)))
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis? = nil) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(title)))
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void = {}) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)))
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)))
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
        self.init(text: text.wrappedValue, placeholder: prompt.map { AnyView($0) } ?? AnyView(label()))
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

    init(text: String, placeholder: AnyView?) {
        self.text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        _FieldBody(text: text, placeholder: placeholder, secure: true)
            .axInfo(context: { ctx in .textInput(role: "secureTextField", text: text, placeholder: placeholder, ctx) })
    }
}

extension SecureField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(titleKey)))
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(titleKey)))
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(text: text.wrappedValue, placeholder: AnyView(Text(title)))
    }
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.init(text: text.wrappedValue, placeholder: AnyView(prompt ?? Text(title)))
    }
}

extension SecureField {
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: text.wrappedValue, placeholder: prompt.map { AnyView($0) } ?? AnyView(label()))
    }
}

// MARK: - TextEditor

public struct TextEditor: View {
    let text: String
    public init(text: Binding<String>) { self.text = text.wrappedValue }

    public var body: some View {
        Text(verbatim: text)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .axInfo(context: { ctx in .textInput(role: "textEditor", text: text, placeholder: nil, ctx) })
    }
}
