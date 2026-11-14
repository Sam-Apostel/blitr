// `import Translation`: the system translation overlay and sessions are inert. A translation task's
// action is not run (it would wait for the system's language models).
@_exported import SwiftUI

public struct TranslationError: Error, Sendable { let reason: String }

public final class TranslationSession: @unchecked Sendable {
    public struct Configuration: Equatable, Hashable, Sendable {
        public var source: Locale.Language?
        public var target: Locale.Language?
        public var version = 0
        public init(source: Locale.Language? = nil, target: Locale.Language? = nil) { self.source = source; self.target = target }
        public mutating func invalidate() { version += 1 }
    }
    public struct Request: Sendable {
        public var sourceText: String
        public var clientIdentifier: String?
        public init(sourceText: String, clientIdentifier: String? = nil) { self.sourceText = sourceText; self.clientIdentifier = clientIdentifier }
    }
    public struct Response: Sendable {
        public let sourceLanguage: Locale.Language
        public let targetLanguage: Locale.Language
        public let sourceText: String
        public let targetText: String
        public let clientIdentifier: String?
    }
    public let sourceLanguage: Locale.Language?
    public let targetLanguage: Locale.Language?
    public init(installedSource: Locale.Language, target: Locale.Language? = nil) { sourceLanguage = installedSource; targetLanguage = target }
    public func prepareTranslation() async throws { throw TranslationError(reason: "unavailable") }
    public func translate(_ string: String) async throws -> Response { throw TranslationError(reason: "unavailable") }
    public func translations(from batch: [Request]) async throws -> [Response] { throw TranslationError(reason: "unavailable") }
}

public final class LanguageAvailability: @unchecked Sendable {
    public enum Status: Sendable { case installed, supported, unsupported }
    public init() {}
    public var supportedLanguages: [Locale.Language] { get async { [] } }
    public func status(from source: Locale.Language, to target: Locale.Language?) async throws -> Status { .unsupported }
}

extension View {
    /// The translation overlay is not drawn.
    public func translationPresentation(isPresented: Binding<Bool>, text: String, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                        arrowEdge: Edge = .top, replacementAction: ((String) -> Void)? = nil) -> some View {
        if isPresented.wrappedValue { ShimDiagnostics.warn("translationPresentation is presented: the translation overlay is not drawn") }
        return self
    }
    public func translationTask(_ configuration: TranslationSession.Configuration?, action: @escaping (TranslationSession) async -> Void) -> some View { self }
    public func translationTask(source: Locale.Language? = nil, target: Locale.Language? = nil, action: @escaping (TranslationSession) async -> Void) -> some View { self }
}
