// Assorted APIs without a visible effect in a static frame, plus the few that only write the
// environment (redaction, preferred color scheme, default app storage).

// MARK: - Redaction

public struct RedactionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
    public static let privacy = RedactionReasons(rawValue: 1 << 1)
    public static let invalidated = RedactionReasons(rawValue: 1 << 2)
}

enum RedactionReasonsKey: EnvironmentKey { static let defaultValue: RedactionReasons = [] }

extension EnvironmentValues {
    /// Set by `redacted(reason:)`. The drawing side of redaction is not implemented yet.
    public var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }
}

// MARK: - Preferred color scheme

/// Written by `preferredColorScheme(_:)` so the root can adopt it later.
enum PreferredColorSchemeKey: PreferenceKey {
    static let defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) { value = nextValue() ?? value }
}

// MARK: - Default app storage

enum InertDefaultAppStorageKey: EnvironmentKey { static let defaultValue: UserDefaults? = nil }

extension EnvironmentValues {
    /// Set by `defaultAppStorage(_:)`; `@AppStorage` should read this when it has no explicit store.
    var defaultAppStorageStore: UserDefaults? {
        get { self[InertDefaultAppStorageKey.self] }
        set { self[InertDefaultAppStorageKey.self] = newValue }
    }
}

// MARK: - Typesetting language

public struct TypesettingLanguage: Sendable {
    let language: Locale.Language?
    public static let automatic = TypesettingLanguage(language: nil)
    public static func explicit(_ language: Locale.Language) -> TypesettingLanguage { TypesettingLanguage(language: language) }
}

// MARK: - View modifiers

extension View {
    // Environment only
    public func redacted(reason: RedactionReasons) -> some View { env { $0.redactionReasons.formUnion(reason) } }
    public func unredacted() -> some View { env { $0.redactionReasons = [] } }
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        env { if let colorScheme { $0.colorScheme = colorScheme } }
            .preference(key: PreferredColorSchemeKey.self, value: colorScheme)
    }
    public func defaultAppStorage(_ store: UserDefaults) -> some View { env { $0.defaultAppStorageStore = store } }

    // Help / privacy
    public func help(_ text: Text) -> some View { self }
    public func help(_ textKey: LocalizedStringKey) -> some View { self }
    public func help<S: StringProtocol>(_ text: S) -> some View { self }
    public func privacySensitive(_ sensitive: Bool = true) -> some View { self }
    public func typesettingLanguage(_ language: TypesettingLanguage, isEnabled: Bool = true) -> some View { self }

    // System chrome
    public func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    public func statusBar(hidden: Bool) -> some View { self }
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View { self }
    public func defersSystemGestures(on edges: Edge.Set) -> some View { self }
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { self }

    // Activities, URLs, scenes
    public func userActivity(_ activityType: String, isActive: Bool = true,
                             _ update: @escaping (NSUserActivity) -> ()) -> some View { self }
    public func userActivity<P>(_ activityType: String, element: P?,
                                _ update: @escaping (P, NSUserActivity) -> ()) -> some View { self }
    public func onContinueUserActivity(_ activityType: String, perform action: @escaping (NSUserActivity) -> ()) -> some View { self }
    public func onOpenURL(perform action: @escaping (URL) -> ()) -> some View { self }
    public func handlesExternalEvents(preferring: Set<String>, allowing: Set<String>) -> some View { self }

    // File dialogs
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                             onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View { self }
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                             onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                             onCompletion: @escaping (Result<[URL], Error>) -> Void,
                             onCancellation: @escaping () -> Void) -> some View { self }
    public func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, document: D?, contentType: UTType,
                                              defaultFilename: String? = nil,
                                              onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
    public func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, document: D?, contentTypes: [UTType],
                                              defaultFilename: String? = nil,
                                              onCompletion: @escaping (Result<URL, Error>) -> Void,
                                              onCancellation: @escaping () -> Void = {}) -> some View { self }
    public func fileExporter<C: Collection, D: FileDocument>(isPresented: Binding<Bool>, documents: C, contentType: UTType,
                                                             onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View
    where C.Element == D { self }
    public func fileExporter<T: Transferable>(isPresented: Binding<Bool>, item: T?, contentTypes: [UTType] = [],
                                              defaultFilename: String? = nil,
                                              onCompletion: @escaping (Result<URL, Error>) -> Void,
                                              onCancellation: @escaping () -> Void = {}) -> some View { self }
    public func fileMover(isPresented: Binding<Bool>, file: URL?,
                          onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
    public func fileMover<C: Collection>(isPresented: Binding<Bool>, files: C,
                                         onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View where C.Element == URL { self }
}
