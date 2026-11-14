// `import StoreKit`: no products load (the App Store is not reachable here), review requests do nothing,
// and the store views are drawn as placeholders of their size.
@_exported import SwiftUI

public struct StoreKitError: Error, Sendable { let reason: String }

public struct Product: Identifiable, Hashable, Sendable {
    public enum ProductType: Hashable, Sendable { case consumable, nonConsumable, nonRenewable, autoRenewable }
    public let id: String
    public let type: ProductType
    public let displayName: String
    public let description: String
    public let displayPrice: String
    public let price: Decimal
    /// Nothing is found: products come from the App Store.
    public static func products<Identifiers: Collection>(for identifiers: Identifiers) async throws -> [Product] where Identifiers.Element == String { [] }
}
public enum Transaction: Sendable {
    public static var currentEntitlements: AsyncStream<VerificationResult<Int>> { AsyncStream { $0.finish() } }
    public static var updates: AsyncStream<VerificationResult<Int>> { AsyncStream { $0.finish() } }
    public static var unfinished: AsyncStream<VerificationResult<Int>> { AsyncStream { $0.finish() } }
}
public enum VerificationResult<SignedType: Sendable>: Sendable {
    case unverified(SignedType, StoreKitError)
    case verified(SignedType)
}
public enum AppStore {
    public static func sync() async throws {}
    public static var canMakePayments: Bool { false }
    @MainActor public static func requestReview(in scene: AnyObject) {}
}

public struct RequestReviewAction: Sendable {
    public func callAsFunction() {}
}
private enum RequestReviewKey: EnvironmentKey { static let defaultValue = RequestReviewAction() }
extension EnvironmentValues {
    /// Does nothing when called.
    public var requestReview: RequestReviewAction { self[RequestReviewKey.self] }
}

open class SKStoreReviewController: NSObject {
    public class func requestReview() {}
    public class func requestReview(in windowScene: AnyObject) {}
}

/// The App Store's purchase views are drawn as a neutral panel: product data never loads here.
struct StorePlaceholder: View {
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.12))
            VStack(spacing: 6) {
                Image(systemName: "bag").font(.title2)
                Text(title).font(.footnote)
            }
            .foregroundStyle(.secondary)
        }
        .frame(minHeight: 80)
        .onAppear { ShimDiagnostics.warn("\(title) shows App Store products, which are not available here; drawn as a placeholder") }
    }
}
public struct ProductView<Icon: View>: View {
    let id: String
    public init(id: String, prefersPromotionalIcon: Bool = false) where Icon == EmptyView { self.id = id }
    public init(id: String, prefersPromotionalIcon: Bool = false, @ViewBuilder icon: () -> Icon) { self.id = id }
    public var body: some View { StorePlaceholder(title: "ProductView") }
}
public struct StoreView: View {
    public init<C: Collection>(ids: C) where C.Element == String {}
    public var body: some View { StorePlaceholder(title: "StoreView") }
}
public struct SubscriptionStoreView: View {
    public init(groupID: String) {}
    public init<C: Collection>(productIDs: C) where C.Element == String {}
    public var body: some View { StorePlaceholder(title: "SubscriptionStoreView") }
}
extension View {
    public func storeButton(_ visibility: Visibility, for buttonKinds: Any...) -> some View { self }
    public func subscriptionStoreControlStyle(_ style: Any) -> some View { self }
    public func manageSubscriptionsSheet(isPresented: Binding<Bool>) -> some View { self }
    public func offerCodeRedemption(isPresented: Binding<Bool>, onCompletion: @escaping (Result<Void, Error>) -> Void = { _ in }) -> some View { self }
}
