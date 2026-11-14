import CoreGraphics
import CryptoKit
import Network
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import WatchConnectivity

// Known-answer checks for the framework shims that compute something. Rendered as a list of
// PASS/FAIL rows; Tests/Frameworks/run.sh fails if any row says FAIL.

func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }

@MainActor func checks() -> [(String, Bool)] {
    var result: [(String, Bool)] = []
    func check(_ name: String, _ ok: Bool) { result.append((name, ok)) }
    let abc = Data("abc".utf8)
    let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
    check("SHA256 abc", hex(SHA256.hash(data: abc)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    check("SHA256 empty", hex(SHA256.hash(data: Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("SHA256 million a", hex(SHA256.hash(data: million)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    check("SHA384 abc", hex(SHA384.hash(data: abc)) == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
    check("SHA512 abc", hex(SHA512.hash(data: abc)) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    check("SHA1 abc", hex(Insecure.SHA1.hash(data: abc)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
    check("MD5 abc", hex(Insecure.MD5.hash(data: abc)) == "900150983cd24fb0d6963f7d28e17f72")
    check("MD5 empty", hex(Insecure.MD5.hash(data: Data())) == "d41d8cd98f00b204e9800998ecf8427e")
    var incremental = SHA256()
    incremental.update(data: Data("ab".utf8)); incremental.update(data: Data("c".utf8))
    check("SHA256 incremental", hex(incremental.finalize()) == hex(SHA256.hash(data: abc)))
    let key = SymmetricKey(data: Data("key".utf8))
    check("HMAC-SHA256", hex(HMAC<SHA256>.authenticationCode(for: Data("The quick brown fox jumps over the lazy dog".utf8), using: key))
        == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    check("HMAC-SHA1", hex(HMAC<Insecure.SHA1>.authenticationCode(for: Data("The quick brown fox jumps over the lazy dog".utf8), using: key))
        == "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9")

    check("UTType png conforms to image", UTType.png.conforms(to: .image))
    check("UTType png conforms to data", UTType.png.conforms(to: .data))
    check("UTType png not text", !UTType.png.conforms(to: .text))
    check("UTType json is text", UTType.json.conforms(to: .text))
    check("UTType from extension", UTType(filenameExtension: "JPG") == .jpeg)
    check("UTType from MIME", UTType(mimeType: "application/pdf") == .pdf)
    check("UTType extension", UTType.mpeg4Movie.preferredFilenameExtension == "mp4")
    check("UTType by identifier", UTType("public.heic")?.conforms(to: .image) == true)
    check("UTType unknown identifier", UTType("com.example.nothing") == nil)
    check("UTType exported", UTType(exportedAs: "com.example.doc", conformingTo: .json).conforms(to: .text))

    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "svc", kSecAttrAccount: "me"]
    check("Keychain empty", SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound)
    var add = query
    add[kSecValueData] = Data("secret".utf8)
    check("Keychain add", SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
    check("Keychain duplicate", SecItemAdd(add as CFDictionary, nil) == errSecDuplicateItem)
    var read = query
    read[kSecReturnData] = true
    read[kSecMatchLimit] = kSecMatchLimitOne
    var out: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &out)
    check("Keychain read", status == errSecSuccess && (out as? Data) == Data("secret".utf8))
    check("Keychain delete", SecItemDelete(query as CFDictionary) == errSecSuccess && SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound)
    var random = [UInt8](repeating: 0, count: 32)
    check("SecRandomCopyBytes", SecRandomCopyBytes(kSecRandomDefault, 32, &random) == errSecSuccess && random.contains { $0 != 0 })

    let teal = UIColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    teal.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    check("UIColor HSB", abs(h - 0.41667) < 0.001 && abs(s - 0.66667) < 0.001 && abs(b - 0.6) < 0.001)
    let round = UIColor(hue: h, saturation: s, brightness: b, alpha: 1)
    var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
    round.getRed(&r, green: &g, blue: &bl, alpha: nil)
    check("UIColor HSB round trip", abs(r - 0.2) < 0.001 && abs(g - 0.6) < 0.001 && abs(bl - 0.4) < 0.001)
    let cg = teal.cgColor
    check("CGColor components", cg.components?.count == 4 && abs((cg.components?[1] ?? 0) - 0.6) < 0.0001)
    let gray = cg.converted(to: CGColorSpaceCreateDeviceGray(), intent: .defaultIntent, options: nil)
    check("CGColor to gray", gray?.numberOfComponents == 2 && abs((gray?.components?[0] ?? 0) - 0.5005) < 0.001)
    check("Color(cgColor:) resolves", Color(cgColor: cg).resolve(in: EnvironmentValues()).green == 0.6)
    let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
    var w: CGFloat = 0
    dynamic.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getWhite(&w, alpha: nil)
    check("UIColor dynamic provider", w == 1)

    check("NWPathMonitor satisfied", NWPathMonitor().currentPath.status == .satisfied)
    check("WCSession not paired", !WCSession.default.isPaired && !WCSession.default.isReachable)
    check("Relative date", RelativeDateTimeFormatter().localizedString(fromTimeInterval: -3 * 3600) == "3 hours ago")
    let named = RelativeDateTimeFormatter()
    named.dateTimeStyle = .named
    check("Relative date named", named.localizedString(fromTimeInterval: 86_400) == "tomorrow")
    let markdown = (try? AttributedString(markdown: "**Bold** and [link](https://example.com) `code`",
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) }
    check("Markdown markers removed", markdown == "Bold and link code")
    return result
}

struct UnitChecks: View {
    var body: some View {
        let rows = checks()
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                Text("\(rows[i].1 ? "PASS" : "FAIL") \(rows[i].0)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(rows[i].1 ? Color.green : Color.red)
            }
        }
        .padding()
        .onAppear {
            // The runner's output is not shown by the tool; run.sh reads the results from this file.
            let text = rows.map { "\($0.1 ? "PASS" : "FAIL") \($0.0)" }.joined(separator: "\n") + "\n"
            let path = ProcessInfo.processInfo.environment["FRAMEWORK_CHECKS_OUT"] ?? NSTemporaryDirectory() + "/framework-checks.txt"
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

#Preview { UnitChecks() }
