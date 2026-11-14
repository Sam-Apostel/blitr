// `import PassKit`: the Wallet buttons are drawn (PKAddPassButton, AddPassToWalletButton, PKPaymentButton,
// PayWithApplePayButton); passes parse to nothing and the pass library is empty.
@_exported import SwiftUI
import UIKit

public struct PKPassKitError: Error, Sendable {
    public enum Code: Int, Sendable { case unknownError = -1, invalidDataError = 1, unsupportedVersionError, invalidSignature, notEntitledError }
    public let code: Code
}
public enum PKPassType: UInt, Sendable { case barcode, secureElement, any = 18446744073709551615 }

open class PKObject: NSObject, @unchecked Sendable {}
open class PKPass: PKObject, @unchecked Sendable {
    open var serialNumber: String { "" }
    open var passTypeIdentifier: String { "" }
    open var organizationName: String { "" }
    open var localizedName: String { "" }
    open var localizedDescription: String { "" }
    open var relevantDate: Date? { nil }
    open var passURL: URL? { nil }
    open var passType: PKPassType { .barcode }
    /// Pass bundles are not read here: every pass is invalid data.
    public init(data: Data) throws { throw PKPassKitError(code: .invalidDataError) }
    open func localizedValue(forFieldKey key: String) -> Any? { nil }
}
open class PKPassLibrary: NSObject, @unchecked Sendable {
    public enum AddPassesStatus: Int, Sendable { case didAddPasses, shouldReviewPasses, didCancelAddPasses }
    public static let didChangeNotification = Notification.Name("PKPassLibraryDidChangeNotification")
    public class func isPassLibraryAvailable() -> Bool { true }
    public override init() { super.init() }
    open func passes() -> [PKPass] { [] }
    open func passes(of passType: PKPassType) -> [PKPass] { [] }
    open func containsPass(_ pass: PKPass) -> Bool { false }
    open func pass(withPassTypeIdentifier identifier: String, serialNumber: String) -> PKPass? { nil }
    open func addPasses(_ passes: [PKPass], withCompletionHandler completion: ((AddPassesStatus) -> Void)? = nil) { completion?(.didCancelAddPasses) }
    open func addPasses(_ passes: [PKPass]) async -> AddPassesStatus { .didCancelAddPasses }
    open func canAddSecureElementPass(primaryAccountIdentifier: String) -> Bool { false }
}
open class PKAddPassesViewController: UIViewController {
    open weak var delegate: AnyObject?
    public class func canAddPasses() -> Bool { true }
    public init?(pass: PKPass) { super.init(nibName: nil, bundle: nil) }
    public init?(passes: [PKPass]) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
public protocol PKAddPassesViewControllerDelegate: AnyObject {}

public enum PKAddPassButtonStyle: Int, Sendable { case black, blackOutline }

/// The "Add to Apple Wallet" badge.
struct WalletBadge: View {
    var outline: Bool
    var body: some View {
        GeometryReader { proxy in
            let h = max(proxy.size.height, 30)
            HStack(spacing: h * 0.18) {
                WalletGlyph().frame(width: h * 0.52, height: h * 0.4)
                VStack(alignment: .leading, spacing: -h * 0.04) {
                    Text("Add to").font(.system(size: h * 0.24, weight: .regular))
                    Text("Apple Wallet").font(.system(size: h * 0.36, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                }
                .foregroundStyle(Color.white)
            }
            .padding(.horizontal, h * 0.25)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(RoundedRectangle(cornerRadius: h * 0.18, style: .continuous).fill(Color.black))
            .overlay(outline ? RoundedRectangle(cornerRadius: h * 0.18, style: .continuous).strokeBorder(Color(white: 0.65), lineWidth: 1) : nil)
        }
        .frame(minWidth: 120, idealWidth: 220, minHeight: 30, idealHeight: 48)
    }
}
/// Three overlapping cards in Wallet's colours.
struct WalletGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let colors: [Color] = [Color(red: 0.25, green: 0.65, blue: 0.95), Color(red: 1, green: 0.75, blue: 0.1),
                                   Color(red: 0.3, green: 0.8, blue: 0.4), Color(red: 1, green: 0.35, blue: 0.3)]
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: h * 0.12).fill(Color(white: 0.85))
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: h * 0.08).fill(colors[i])
                        .frame(width: w * 0.84, height: h * 0.3)
                        .offset(y: h * 0.06 + CGFloat(i) * h * 0.12)
                }
                RoundedRectangle(cornerRadius: h * 0.1).fill(Color(white: 0.92))
                    .frame(width: w, height: h * 0.45)
                    .offset(y: h * 0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: h * 0.12))
        }
    }
}

open class PKAddPassButton: UIButton, _SwiftUIDrawableView {
    open var addPassButtonStyle = PKAddPassButtonStyle.black
    public init(addPassButtonStyle style: PKAddPassButtonStyle) { addPassButtonStyle = style; super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public var _swiftUIRepresentation: AnyView { AnyView(WalletBadge(outline: addPassButtonStyle == .blackOutline)) }
    open override var intrinsicContentSize: CGSize { CGSize(width: 260, height: 48) }
}

public struct AddPassToWalletButton<Label: View>: View {
    let label: Label?
    public init(action: @escaping () -> Void) where Label == EmptyView { label = nil }
    public init(_ passes: [PKPass], onCompletion: @escaping (Bool) -> Void) where Label == EmptyView { label = nil }
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.label = label() }
    public var body: some View {
        if let label { Button(action: {}) { label } } else { WalletBadge(outline: false) }
    }
}
public struct AddPassToWalletButtonStyle: Hashable, Sendable {
    let outline: Bool
    public static let black = AddPassToWalletButtonStyle(outline: false)
    public static let blackOutline = AddPassToWalletButtonStyle(outline: true)
}
extension View {
    public func addPassToWalletButtonStyle(_ style: AddPassToWalletButtonStyle) -> some View { self }
}

// MARK: - Apple Pay

public enum PKPaymentButtonType: Int, Sendable { case plain, buy, setUp, inStore, donate, checkout, book, subscribe, reload, addMoney, topUp, order, rent, support, contribute, tip, `continue` }
public enum PKPaymentButtonStyle: Int, Sendable { case white, whiteOutline, black, automatic }

struct ApplePayBadge: View {
    var prefix: String
    var dark: Bool
    var body: some View {
        GeometryReader { proxy in
            let h = max(proxy.size.height, 30)
            HStack(spacing: h * 0.08) {
                if !prefix.isEmpty { Text(prefix).font(.system(size: h * 0.4, weight: .medium)) }
                _AppleLogo().fill(dark ? Color.white : Color.black).frame(width: h * 0.34, height: h * 0.42).offset(y: -h * 0.04)
                Text("Pay").font(.system(size: h * 0.48, weight: .medium))
            }
            .foregroundStyle(dark ? Color.white : Color.black)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(dark ? Color.black : Color.white))
        }
        .frame(minWidth: 100, minHeight: 30)
    }
}

open class PKPaymentButton: UIButton, _SwiftUIDrawableView {
    let type: PKPaymentButtonType
    let style: PKPaymentButtonStyle
    open var cornerRadius: CGFloat = 4
    public init(paymentButtonType type: PKPaymentButtonType, paymentButtonStyle style: PKPaymentButtonStyle) {
        self.type = type; self.style = style
        super.init(frame: .zero)
    }
    public required init?(coder: NSCoder) { type = .plain; style = .black; super.init(coder: coder) }
    public var _swiftUIRepresentation: AnyView { AnyView(ApplePayBadge(prefix: type == .buy ? "Buy with" : type == .plain ? "" : "Pay with", dark: style == .black)) }
}

public struct PayWithApplePayButton<Fallback: View>: View {
    public struct Label: Hashable, Sendable {
        let prefix: String
        public static var plain: Label { Label(prefix: "") }
        public static var buy: Label { Label(prefix: "Buy with") }
        public static var checkout: Label { Label(prefix: "Check out with") }
        public static var `continue`: Label { Label(prefix: "Continue with") }
        public static var donate: Label { Label(prefix: "Donate with") }
        public static var book: Label { Label(prefix: "Book with") }
        public static var subscribe: Label { Label(prefix: "Subscribe with") }
        public static var order: Label { Label(prefix: "Order with") }
        public static var setUp: Label { Label(prefix: "Set up") }
    }
    let label: Label
    public init(_ label: Label = .plain, action: @escaping () -> Void) where Fallback == EmptyView { self.label = label }
    public init(_ label: Label = .plain, action: @escaping () -> Void, @ViewBuilder fallback: () -> Fallback) { self.label = label }
    @Environment(\.colorScheme) private var colorScheme
    public var body: some View { ApplePayBadge(prefix: label.prefix, dark: colorScheme == .light) }
}
public struct PayWithApplePayButtonStyle: Hashable, Sendable {
    let raw: Int
    public static let automatic = PayWithApplePayButtonStyle(raw: 0)
    public static let black = PayWithApplePayButtonStyle(raw: 1)
    public static let white = PayWithApplePayButtonStyle(raw: 2)
    public static let whiteOutline = PayWithApplePayButtonStyle(raw: 3)
}
extension View {
    public func payWithApplePayButtonStyle(_ style: PayWithApplePayButtonStyle) -> some View { self }
}
open class PKPaymentAuthorizationController: NSObject, @unchecked Sendable {
    public class func canMakePayments() -> Bool { false }
    public class func canMakePayments(usingNetworks supportedNetworks: [String]) -> Bool { false }
}
