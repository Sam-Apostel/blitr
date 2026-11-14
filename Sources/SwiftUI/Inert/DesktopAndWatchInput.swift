// Input from hardware a screenshot does not have (the Digital Crown, the pasteboard commands, the pointer)
// and macOS window behaviour. Nothing here changes a static frame; `inspector` is the exception and is drawn
// as the sheet it adapts to on iPhone.

// MARK: - Digital Crown (watchOS)

public struct DigitalCrownRotationalSensitivity: Hashable, Sendable {
    let raw: Int
    public static let low = DigitalCrownRotationalSensitivity(raw: 0)
    public static let medium = DigitalCrownRotationalSensitivity(raw: 1)
    public static let high = DigitalCrownRotationalSensitivity(raw: 2)
}

public struct DigitalCrownEvent: Sendable {
    public let offset: Double
    public let velocity: Double
}

extension View {
    public func digitalCrownRotation<V: BinaryFloatingPoint>(_ binding: Binding<V>) -> some View { self }
    public func digitalCrownRotation<V: BinaryFloatingPoint>(_ binding: Binding<V>, from minValue: V, through maxValue: V, by stride: V.Stride? = nil,
                                                             sensitivity: DigitalCrownRotationalSensitivity = .high, isContinuous: Bool = false,
                                                             isHapticFeedbackEnabled: Bool = true) -> some View { self }
    public func digitalCrownRotation<V: BinaryFloatingPoint>(_ binding: Binding<V>, from minValue: V, through maxValue: V, by stride: V.Stride? = nil,
                                                             sensitivity: DigitalCrownRotationalSensitivity = .high, isContinuous: Bool = false,
                                                             isHapticFeedbackEnabled: Bool = true, onChange: @escaping (DigitalCrownEvent) -> Void = { _ in },
                                                             onIdle: @escaping () -> Void = {}) -> some View { self }
    public func digitalCrownRotation<V: BinaryFloatingPoint>(detent: Binding<V>, from minValue: V, through maxValue: V, by stride: V.Stride? = nil,
                                                             sensitivity: DigitalCrownRotationalSensitivity = .high, isContinuous: Bool = false,
                                                             isHapticFeedbackEnabled: Bool = true, onChange: @escaping (DigitalCrownEvent) -> Void = { _ in },
                                                             onIdle: @escaping () -> Void = {}) -> some View where V.Stride: BinaryFloatingPoint { self }
    public func digitalCrownAccessory(_ visibility: Visibility) -> some View { self }
    public func digitalCrownAccessory<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View { self }
}

// MARK: - Focused objects

extension View {
    public func focusedObject<T: ObservableObject>(_ object: T) -> some View { self }
    public func focusedObject<T: ObservableObject>(_ object: T?) -> some View { self }
    public func focusedSceneObject<T: ObservableObject>(_ object: T) -> some View { self }
    public func focusedSceneObject<T: ObservableObject>(_ object: T?) -> some View { self }
}

// MARK: - Pasteboard commands and drag sources

extension View {
    public func itemProvider(_ action: Optional<() -> NSItemProvider?>) -> some View { self }
    public func onCopyCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View { self }
    public func onCutCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View { self }
    public func onPasteCommand(of supportedContentTypes: [UTType], perform payloadAction: @escaping ([NSItemProvider]) -> Void) -> some View { self }
    public func onPasteCommand<Payload>(of supportedContentTypes: [UTType], validator: @escaping ([NSItemProvider]) -> Payload?,
                                        perform payloadAction: @escaping (Payload) -> Void) -> some View { self }
    public func onDeleteCommand(perform action: (() -> Void)?) -> some View { self }
    public func copyable<T: Transferable>(_ items: @autoclosure @escaping () -> [T]) -> some View { self }
    public func cuttable<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping () -> [T]) -> some View { self }
    public func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void,
                                                  validator: @escaping ([T]) -> [T] = { $0 }) -> some View { self }
}

// MARK: - Pointer and hover

public struct PointerStyle: Sendable {
    let name: String
    public static let `default` = PointerStyle(name: "default")
    public static let horizontalText = PointerStyle(name: "horizontalText")
    public static let verticalText = PointerStyle(name: "verticalText")
    public static let rectSelection = PointerStyle(name: "rectSelection")
    public static let grabIdle = PointerStyle(name: "grabIdle")
    public static let grabActive = PointerStyle(name: "grabActive")
    public static let link = PointerStyle(name: "link")
    public static let zoomIn = PointerStyle(name: "zoomIn")
    public static let zoomOut = PointerStyle(name: "zoomOut")
    public static let columnResize = PointerStyle(name: "columnResize")
    public static let rowResize = PointerStyle(name: "rowResize")
    public static func image(_ image: Image, hotSpot: UnitPoint) -> PointerStyle { PointerStyle(name: "image") }
}

extension View {
    public func pointerStyle(_ style: PointerStyle?) -> some View { self }
    public func pointerVisibility(_ visibility: Visibility) -> some View { self }
    public func defaultHoverEffect(_ effect: HoverEffect?) -> some View { self }
}

// MARK: - macOS windows

extension View {
    public func navigationDocument(_ url: URL) -> some View { self }
    public func navigationDocument<D: Transferable>(_ document: D) -> some View { self }
    public func presentedWindowStyle<S: WindowStyle>(_ style: S) -> some View { self }
    public func presentedWindowToolbarStyle<S: WindowToolbarStyle>(_ style: S) -> some View { self }
    public func windowResizeBehavior(_ behavior: WindowInteractionBehavior) -> some View { self }
    public func windowMinimizeBehavior(_ behavior: WindowInteractionBehavior) -> some View { self }
    public func windowDismissBehavior(_ behavior: WindowInteractionBehavior) -> some View { self }
    public func windowFullScreenBehavior(_ behavior: WindowInteractionBehavior) -> some View { self }
    public func fileDialogMessage(_ message: Text?) -> some View { self }
    public func fileDialogMessage(_ messageKey: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload
    public func fileDialogMessage<S: StringProtocol>(_ message: S) -> some View { self }
    public func fileDialogConfirmationLabel(_ label: Text?) -> some View { self }
}

// MARK: - Inspector

extension View {
    /// In a compact width the inspector is a sheet; a regular-width trailing column is not drawn (warns).
    public func inspector<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View {
        let content = content()
        if isPresented.wrappedValue, _currentSizeClass(horizontal: true) == .regular {
            Runtime.current?.warn("inspector(isPresented:) in a regular width is a trailing column, which is not drawn")
        }
        return sheet(isPresented: _currentSizeClass(horizontal: true) == .regular ? .constant(false) : isPresented) { content }
    }
    public func inspectorColumnWidth(_ width: CGFloat) -> some View { self }
    public func inspectorColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View { self }
}
