// `import Security`: the keychain item functions over an in-memory store (what a fresh install has:
// nothing until the app adds it), SecRandomCopyBytes from the system generator, and the constants.
@_exported import CoreGraphics

public typealias OSStatus = Int32
public let errSecSuccess: OSStatus = 0
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecAllocate: OSStatus = -108
public let errSecUserCanceled: OSStatus = -128
public let errSecAuthFailed: OSStatus = -25293
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300
public let errSecInteractionNotAllowed: OSStatus = -25308
public let errSecDecode: OSStatus = -26275
public let errSecMissingEntitlement: OSStatus = -34018

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: CFString = "genp"
public let kSecClassInternetPassword: CFString = "inet"
public let kSecClassCertificate: CFString = "cert"
public let kSecClassKey: CFString = "keys"
public let kSecClassIdentity: CFString = "idnt"
public let kSecAttrService: CFString = "svce"
public let kSecAttrAccount: CFString = "acct"
public let kSecAttrServer: CFString = "srvr"
public let kSecAttrProtocol: CFString = "ptcl"
public let kSecAttrPort: CFString = "port"
public let kSecAttrPath: CFString = "path"
public let kSecAttrLabel: CFString = "labl"
public let kSecAttrDescription: CFString = "desc"
public let kSecAttrComment: CFString = "icmt"
public let kSecAttrGeneric: CFString = "gena"
public let kSecAttrAccessGroup: CFString = "agrp"
public let kSecAttrSynchronizable: CFString = "sync"
public let kSecAttrSynchronizableAny: CFString = "syna"
public let kSecAttrCreationDate: CFString = "cdat"
public let kSecAttrModificationDate: CFString = "mdat"
public let kSecAttrApplicationTag: CFString = "atag"
public let kSecAttrKeyType: CFString = "type"
public let kSecAttrKeySizeInBits: CFString = "bsiz"
public let kSecAttrIsPermanent: CFString = "perm"
public let kSecAttrTokenID: CFString = "tkid"
public let kSecAttrAccessible: CFString = "pdmn"
public let kSecAttrAccessibleWhenUnlocked: CFString = "ak"
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck"
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu"
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku"
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku"
public let kSecAttrAccessControl: CFString = "accc"
public let kSecValueData: CFString = "v_Data"
public let kSecValueRef: CFString = "v_Ref"
public let kSecValuePersistentRef: CFString = "v_PersistentRef"
public let kSecReturnData: CFString = "r_Data"
public let kSecReturnAttributes: CFString = "r_Attributes"
public let kSecReturnRef: CFString = "r_Ref"
public let kSecReturnPersistentRef: CFString = "r_PersistentRef"
public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: CFString = "m_LimitOne"
public let kSecMatchLimitAll: CFString = "m_LimitAll"
public let kSecUseDataProtectionKeychain: CFString = "nleg"
public let kSecUseAuthenticationContext: CFString = "u_AuthCtx"
public let kSecUseAuthenticationUI: CFString = "u_AuthUI"
public let kSecUseOperationPrompt: CFString = "u_OpPrompt"

/// The attributes that identify an item (class, service, account, server, access group, label).
private let identity: [String] = ["class", "svce", "acct", "srvr", "agrp", "atag", "labl"]

private final class Keychain: @unchecked Sendable {
    static let shared = Keychain()
    let lock = NSLock()
    var items: [[String: Any]] = []

    func key(_ attributes: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for k in identity { if let v = attributes[k] { result[k] = "\(v)" } }
        return result
    }
    /// Items whose identifying attributes include all of the query's.
    func matches(_ query: [String: Any]) -> [Int] {
        let wanted = key(query)
        return items.indices.filter { i in
            let have = key(items[i])
            return wanted.allSatisfy { have[$0.key] == $0.value }
        }
    }
}

private func attributes(_ dictionary: CFDictionary) -> [String: Any] {
    var result: [String: Any] = [:]
    for (k, v) in dictionary { result["\(k)"] = v }
    return result
}

public func SecItemAdd(_ attributesToAdd: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    let item = attributes(attributesToAdd)
    guard item["class"] != nil else { return errSecParam }
    let chain = Keychain.shared
    chain.lock.lock(); defer { chain.lock.unlock() }
    let identity = chain.key(item)
    if chain.items.contains(where: { chain.key($0) == identity }) { return errSecDuplicateItem }
    chain.items.append(item)
    return errSecSuccess
}

public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    let q = attributes(query)
    let chain = Keychain.shared
    chain.lock.lock(); defer { chain.lock.unlock() }
    let found = chain.matches(q).map { chain.items[$0] }
    guard !found.isEmpty else { return errSecItemNotFound }
    let all = "\(q["m_Limit"] ?? "")" == "m_LimitAll"
    let wantsData = (q["r_Data"] as? Bool) == true || (q["r_Data"] as? NSNumber)?.boolValue == true
    let wantsAttributes = (q["r_Attributes"] as? Bool) == true || (q["r_Attributes"] as? NSNumber)?.boolValue == true
    func value(_ item: [String: Any]) -> AnyObject {
        if wantsAttributes {
            var copy = item
            if !wantsData { copy["v_Data"] = nil }
            return copy as NSDictionary
        }
        return ((item["v_Data"] as? Data) ?? Data()) as NSData
    }
    if let result { result.pointee = all ? (found.map(value) as NSArray) : value(found[0]) }
    return errSecSuccess
}

public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    let q = attributes(query), changes = attributes(attributesToUpdate)
    let chain = Keychain.shared
    chain.lock.lock(); defer { chain.lock.unlock() }
    let indices = chain.matches(q)
    guard !indices.isEmpty else { return errSecItemNotFound }
    for i in indices { for (k, v) in changes { chain.items[i][k] = v } }
    return errSecSuccess
}

public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    let q = attributes(query)
    let chain = Keychain.shared
    chain.lock.lock(); defer { chain.lock.unlock() }
    let indices = Set(chain.matches(q))
    guard !indices.isEmpty else { return errSecItemNotFound }
    chain.items = chain.items.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
    return errSecSuccess
}

public func SecCopyErrorMessageString(_ status: OSStatus, _ reserved: UnsafeMutableRawPointer?) -> CFString? {
    switch status {
    case errSecSuccess: return "No error."
    case errSecItemNotFound: return "The specified item could not be found in the keychain."
    case errSecDuplicateItem: return "The specified item already exists in the keychain."
    case errSecParam: return "One or more parameters passed to a function were not valid."
    default: return "OSStatus \(status)" as NSString
    }
}

// MARK: - Random

public final class SecRandom: @unchecked Sendable {}
public typealias SecRandomRef = SecRandom
public let kSecRandomDefault: SecRandomRef? = nil

public func SecRandomCopyBytes(_ rnd: SecRandomRef?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    var generator = SystemRandomNumberGenerator()
    let out = bytes.assumingMemoryBound(to: UInt8.self)
    for i in 0..<count { out[i] = UInt8.random(in: 0...255, using: &generator) }
    return errSecSuccess
}

// MARK: - Access control and keys (records only)

public final class SecAccessControl: @unchecked Sendable {}
public struct SecAccessControlCreateFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let userPresence = SecAccessControlCreateFlags(rawValue: 1 << 0)
    public static let biometryAny = SecAccessControlCreateFlags(rawValue: 1 << 1)
    public static let biometryCurrentSet = SecAccessControlCreateFlags(rawValue: 1 << 3)
    public static let devicePasscode = SecAccessControlCreateFlags(rawValue: 1 << 4)
    public static let privateKeyUsage = SecAccessControlCreateFlags(rawValue: 1 << 30)
}
public func SecAccessControlCreateWithFlags(_ allocator: AnyObject?, _ protection: CFTypeRef, _ flags: SecAccessControlCreateFlags,
                                            _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> SecAccessControl? { SecAccessControl() }
