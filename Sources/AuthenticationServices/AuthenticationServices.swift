// `import AuthenticationServices`: SignInWithAppleButton drawn in Apple's published style (black, white,
// white outline; Apple logo and "Sign in with Apple" / "Continue with Apple" / "Sign up with Apple").
// Authorization requests never complete: there is nobody to sign in.
@_exported import SwiftUI
import UIKit

public typealias ASPresentationAnchor = UIWindow

public struct ASAuthorizationError: Error, Hashable, Sendable {
    public enum Code: Int, Sendable { case unknown = 1000, canceled, invalidResponse, notHandled, failed, notInteractive, matchedExcludedCredential = 1007, credentialImport, credentialExport }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static var unknown: Code { .unknown }
    public static var canceled: Code { .canceled }
    public static var failed: Code { .failed }
}

public struct ASAuthorizationScope: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fullName = ASAuthorizationScope(rawValue: "full_name")
    public static let email = ASAuthorizationScope(rawValue: "email")
}

public protocol ASAuthorizationCredential: AnyObject {}
public protocol ASAuthorizationProvider: AnyObject {}

open class ASAuthorizationRequest: NSObject, @unchecked Sendable {
    open var provider: ASAuthorizationProvider? { nil }
}
open class ASAuthorizationOpenIDRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var requestedScopes: [ASAuthorizationScope]?
    open var state: String?
    open var nonce: String?
}
open class ASAuthorizationAppleIDRequest: ASAuthorizationOpenIDRequest, @unchecked Sendable {
    open var user: String?
}
open class ASAuthorizationAppleIDProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public enum CredentialState: Int, Sendable { case revoked, authorized, notFound, transferred }
    public override init() { super.init() }
    open func createRequest() -> ASAuthorizationAppleIDRequest { ASAuthorizationAppleIDRequest() }
    open func getCredentialState(forUserID userID: String, completion: @escaping (CredentialState, Error?) -> Void) { completion(.notFound, nil) }
    open func credentialState(forUserID userID: String) async throws -> CredentialState { .notFound }
}
open class ASAuthorizationAppleIDCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public enum UserDetectionStatus: Int, Sendable { case unsupported, unknown, likelyReal }
    open var user: String { "" }
    open var state: String? { nil }
    open var authorizedScopes: [ASAuthorizationScope] { [] }
    open var authorizationCode: Data? { nil }
    open var identityToken: Data? { nil }
    open var email: String? { nil }
    open var fullName: PersonNameComponents? { nil }
    open var realUserStatus: UserDetectionStatus { .unknown }
}
open class ASAuthorization: NSObject, @unchecked Sendable {
    public let provider: ASAuthorizationProvider
    public let credential: ASAuthorizationCredential
    init(provider: ASAuthorizationProvider, credential: ASAuthorizationCredential) { self.provider = provider; self.credential = credential; super.init() }
}

// Passkeys.
open class ASAuthorizationPlatformPublicKeyCredentialProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public let relyingPartyIdentifier: String
    public init(relyingPartyIdentifier: String) { self.relyingPartyIdentifier = relyingPartyIdentifier; super.init() }
    open func createCredentialRegistrationRequest(challenge: Data, name: String, userID: Data) -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest {
        ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest()
    }
    open func createCredentialAssertionRequest(challenge: Data) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
        ASAuthorizationPlatformPublicKeyCredentialAssertionRequest()
    }
}
open class ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var userVerificationPreference = "preferred"
    open var attestationPreference = "none"
}
open class ASAuthorizationPlatformPublicKeyCredentialAssertionRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var userVerificationPreference = "preferred"
    open var allowedCredentials: [Any] = []
}
open class ASAuthorizationPlatformPublicKeyCredentialRegistration: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    open var rawAttestationObject: Data? { nil }
    open var rawClientDataJSON: Data { Data() }
    open var credentialID: Data { Data() }
}
open class ASAuthorizationPlatformPublicKeyCredentialAssertion: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    open var rawAuthenticatorData: Data! { Data() }
    open var userID: Data! { Data() }
    open var signature: Data! { Data() }
    open var rawClientDataJSON: Data { Data() }
    open var credentialID: Data { Data() }
}
open class ASAuthorizationPasswordProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    open func createRequest() -> ASAuthorizationPasswordRequest { ASAuthorizationPasswordRequest() }
}
open class ASAuthorizationPasswordRequest: ASAuthorizationRequest, @unchecked Sendable {}
open class ASPasswordCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public let user: String
    public let password: String
    public init(user: String, password: String) { self.user = user; self.password = password; super.init() }
}

public protocol ASAuthorizationControllerDelegate: AnyObject {}
public protocol ASAuthorizationControllerPresentationContextProviding: AnyObject {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}
open class ASAuthorizationController: NSObject, @unchecked Sendable {
    public struct RequestOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let preferImmediatelyAvailableCredentials = RequestOptions(rawValue: 1)
    }
    public let authorizationRequests: [ASAuthorizationRequest]
    open weak var delegate: ASAuthorizationControllerDelegate?
    open weak var presentationContextProvider: ASAuthorizationControllerPresentationContextProviding?
    public init(authorizationRequests: [ASAuthorizationRequest]) { self.authorizationRequests = authorizationRequests; super.init() }
    /// Shows nothing and never completes: there is nobody to sign in.
    open func performRequests() {}
    open func performRequests(options: RequestOptions) {}
    open func performAutoFillAssistedRequests() {}
    open func cancel() {}
}

open class ASWebAuthenticationSession: NSObject, @unchecked Sendable {
    public typealias CompletionHandler = (URL?, Error?) -> Void
    open var prefersEphemeralWebBrowserSession = false
    open weak var presentationContextProvider: AnyObject?
    open var canStart: Bool { false }
    public init(url URL: URL, callbackURLScheme: String?, completionHandler: @escaping CompletionHandler) { super.init() }
    @discardableResult open func start() -> Bool { false }
    open func cancel() {}
}

// MARK: - SignInWithAppleButton

public struct SignInWithAppleButton: View {
    public struct Label: Hashable, Sendable {
        let title: String
        public static let signIn = Label(title: "Sign in with Apple")
        public static let `continue` = Label(title: "Continue with Apple")
        public static let signUp = Label(title: "Sign up with Apple")
    }
    public struct Style: Hashable, Sendable {
        let kind: Int
        public static let black = Style(kind: 0)
        public static let white = Style(kind: 1)
        public static let whiteOutline = Style(kind: 2)
    }
    let label: Label
    @Environment(\.signInWithAppleButtonStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    public init(_ label: Label = .signIn, onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
                onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.label = label
    }

    public var body: some View {
        let resolved = style ?? (colorScheme == .dark ? .white : .black)
        let fill = resolved == .black ? Color.black : Color.white
        let ink = resolved == .black ? Color.white : Color.black
        GeometryReader { proxy in
            let h = max(proxy.size.height, 30)
            let size = min(max(h * 0.43, 12), 28)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill)
                if resolved == .whiteOutline {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black, lineWidth: 1)
                }
                HStack(spacing: size * 0.25) {
                    _AppleLogo().fill(ink).frame(width: size * 0.82, height: size)
                        .offset(y: -size * 0.08)
                    Text(label.title).font(.system(size: size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 140, minHeight: 30)
        .accessibilityLabel(Text(label.title))
        .accessibilityAddTraits(.isButton)
    }
}

private enum SignInWithAppleButtonStyleKey: EnvironmentKey { static let defaultValue: SignInWithAppleButton.Style? = nil }
extension EnvironmentValues {
    var signInWithAppleButtonStyle: SignInWithAppleButton.Style? {
        get { self[SignInWithAppleButtonStyleKey.self] }
        set { self[SignInWithAppleButtonStyleKey.self] = newValue }
    }
}
extension View {
    public func signInWithAppleButtonStyle(_ style: SignInWithAppleButton.Style) -> some View {
        environment(\.signInWithAppleButtonStyle, style)
    }
}

