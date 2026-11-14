// `import WatchConnectivity`: an iPhone with no paired watch. The session activates; it is not paired,
// the watch app is not installed, nothing is reachable, and transfers wait forever as outstanding.
@_exported import Foundation

public enum WCSessionActivationState: Int, Sendable { case notActivated, inactive, activated }
public struct WCError: Error, Sendable {
    public enum Code: Int, Sendable {
        case genericError = 7001, sessionNotSupported, sessionMissingDelegate, sessionNotActivated, deviceNotPaired, watchAppNotInstalled,
             notReachable, invalidParameter, payloadTooLarge, payloadUnsupportedTypes, messageReplyFailed, messageReplyTimedOut,
             fileAccessDenied, deliveryFailed, insufficientSpace, sessionInactive, transferTimedOut, companionAppNotInstalled, watchOnlyApp
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
}

/// The app's delegate methods; activation completion is the one called here.
public protocol WCSessionDelegate: AnyObject {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?)
}

open class WCSessionFile: NSObject, @unchecked Sendable {
    public let fileURL: URL
    public let metadata: [String: Any]?
    init(fileURL: URL, metadata: [String: Any]?) { self.fileURL = fileURL; self.metadata = metadata; super.init() }
}
open class WCSessionFileTransfer: NSObject, @unchecked Sendable {
    public let file: WCSessionFile
    open var isTransferring: Bool { true }
    open var progress: Progress { Progress(totalUnitCount: 1) }
    init(file: WCSessionFile) { self.file = file; super.init() }
    open func cancel() { WCSession.default.cancel(self) }
}
open class WCSessionUserInfoTransfer: NSObject, @unchecked Sendable {
    public let userInfo: [String: Any]
    public let isCurrentComplicationInfo = false
    open var isTransferring: Bool { true }
    init(userInfo: [String: Any]) { self.userInfo = userInfo; super.init() }
    open func cancel() {}
}

open class WCSession: NSObject, @unchecked Sendable {
    public static let `default` = WCSession()
    open class func isSupported() -> Bool { true }
    open weak var delegate: WCSessionDelegate?
    open private(set) var activationState = WCSessionActivationState.notActivated
    open var isPaired: Bool { false }
    open var isWatchAppInstalled: Bool { false }
    open var isComplicationEnabled: Bool { false }
    open var isReachable: Bool { false }
    open var iOSDeviceNeedsUnlockAfterRebootForReachability: Bool { false }
    open var isCompanionAppInstalled: Bool { false }
    open var watchDirectoryURL: URL? { nil }
    open var remainingComplicationUserInfoTransfers: Int { 0 }
    open var hasContentPending: Bool { false }
    open private(set) var applicationContext: [String: Any] = [:]
    open var receivedApplicationContext: [String: Any] { [:] }
    open private(set) var outstandingFileTransfers: [WCSessionFileTransfer] = []
    open private(set) var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] = []

    /// Activates and tells the delegate, as on an iPhone with no watch.
    open func activate() {
        activationState = .activated
        delegate?.session(self, activationDidCompleteWith: .activated, error: nil)
    }
    open func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)? = nil) {
        errorHandler?(WCError(.notReachable))
    }
    open func sendMessageData(_ data: Data, replyHandler: ((Data) -> Void)?, errorHandler: ((Error) -> Void)? = nil) {
        errorHandler?(WCError(.notReachable))
    }
    open func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        guard activationState == .activated else { throw WCError(.sessionNotActivated) }
        throw WCError(.deviceNotPaired)
    }
    @discardableResult open func transferUserInfo(_ userInfo: [String: Any] = [:]) -> WCSessionUserInfoTransfer {
        let transfer = WCSessionUserInfoTransfer(userInfo: userInfo)
        outstandingUserInfoTransfers.append(transfer)
        return transfer
    }
    @discardableResult open func transferCurrentComplicationUserInfo(_ userInfo: [String: Any] = [:]) -> WCSessionUserInfoTransfer { transferUserInfo(userInfo) }
    @discardableResult open func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer {
        let transfer = WCSessionFileTransfer(file: WCSessionFile(fileURL: file, metadata: metadata))
        outstandingFileTransfers.append(transfer)
        return transfer
    }
    func cancel(_ transfer: WCSessionFileTransfer) { outstandingFileTransfers.removeAll { $0 === transfer } }
}
