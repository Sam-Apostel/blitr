// `import CryptoKit`: SHA-256/384/512, Insecure.SHA1/MD5 and HMAC computed for real; SymmetricKey;
// AES-GCM, ChaChaPoly and the curves are present for source compatibility and throw when used.
@_exported import Foundation

public protocol Digest: Hashable, Sequence, CustomStringConvertible, ContiguousBytes, Sendable where Element == UInt8 {
    static var byteCount: Int { get }
    var bytes: [UInt8] { get }
}
extension Digest {
    public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    public var description: String { "\(Self.self): " + bytes.map { String(format: "%02x", $0) }.joined() }
}

public protocol HashFunction {
    associatedtype Digest: CryptoKit.Digest
    static var blockByteCount: Int { get }
    init()
    mutating func update(bufferPointer: UnsafeRawBufferPointer)
    func finalize() -> Digest
}
extension HashFunction {
    public mutating func update<D: DataProtocol>(data: D) {
        let bytes = [UInt8](data)
        bytes.withUnsafeBytes { update(bufferPointer: $0) }
    }
    public static func hash<D: DataProtocol>(data: D) -> Digest {
        var h = Self()
        h.update(data: data)
        return h.finalize()
    }
}

/// Merkle-Damgard padding and block feeding shared by the SHA family and MD5.
struct BlockBuffer {
    var pending: [UInt8] = []
    var length: UInt64 = 0
    mutating func feed(_ data: UnsafeRawBufferPointer, blockSize: Int, _ compress: (ArraySlice<UInt8>) -> Void) {
        pending += data
        length += UInt64(data.count)
        var start = 0
        while pending.count - start >= blockSize { compress(pending[start..<(start + blockSize)]); start += blockSize }
        pending.removeFirst(start)
    }
    func padded(blockSize: Int, lengthBytes: Int, littleEndian: Bool) -> [UInt8] {
        var tail = pending + [0x80]
        while tail.count % blockSize != blockSize - lengthBytes { tail.append(0) }
        let bits = length &* 8
        var lengthField = [UInt8](repeating: 0, count: lengthBytes)
        for i in 0..<8 { lengthField[littleEndian ? i : lengthBytes - 1 - i] = UInt8((bits >> (8 * UInt64(i))) & 0xFF) }
        return tail + lengthField
    }
}

private func rotr32(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
private func rotl32(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
private func rotr64(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
private func be32(_ b: ArraySlice<UInt8>, _ i: Int) -> UInt32 {
    let s = b.startIndex + i * 4
    return UInt32(b[s]) << 24 | UInt32(b[s + 1]) << 16 | UInt32(b[s + 2]) << 8 | UInt32(b[s + 3])
}
private func be64(_ b: ArraySlice<UInt8>, _ i: Int) -> UInt64 {
    let s = b.startIndex + i * 8
    return (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(b[s + $1]) }
}

// MARK: - SHA-256

private let k256: [UInt32] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

public struct SHA256Digest: Digest {
    public static let byteCount = 32
    public let bytes: [UInt8]
}
public struct SHA256: HashFunction {
    public static let blockByteCount = 64
    public static let byteCount = 32
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var buffer = BlockBuffer()
    public init() {}
    static func compress(_ h: inout [UInt32], _ block: ArraySlice<UInt8>) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 { w[i] = be32(block, i) }
        for i in 16..<64 {
            let s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let t1 = hh &+ (rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k256[i] &+ w[i]
            let t2 = (rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        for (i, v) in [a, b, c, d, e, f, g, hh].enumerated() { h[i] = h[i] &+ v }
    }
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        var state = h
        buffer.feed(bufferPointer, blockSize: 64) { SHA256.compress(&state, $0) }
        h = state
    }
    public func finalize() -> SHA256Digest {
        var state = h
        let tail = buffer.padded(blockSize: 64, lengthBytes: 8, littleEndian: false)
        for start in stride(from: 0, to: tail.count, by: 64) { SHA256.compress(&state, tail[start..<(start + 64)]) }
        return SHA256Digest(bytes: state.flatMap { v in (0..<4).map { UInt8((v >> (24 - 8 * UInt32($0))) & 0xFF) } })
    }
}

// MARK: - SHA-512 / SHA-384

private let k512: [UInt64] = [
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b,
    0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1,
    0x9bdc06a725c71235, 0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65, 0x2de92c6f592b0275,
    0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
    0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b, 0xa2bfe8a14cf10364, 0xa81a664bbc423001,
    0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8,
    0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec, 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915,
    0xc67178f2e372532b, 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
    0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c, 0x4cc5d4becb3e42b6,
    0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
]
struct SHA512Core {
    var h: [UInt64]
    var buffer = BlockBuffer()
    static func compress(_ h: inout [UInt64], _ block: ArraySlice<UInt8>) {
        var w = [UInt64](repeating: 0, count: 80)
        for i in 0..<16 { w[i] = be64(block, i) }
        for i in 16..<80 {
            let s0 = rotr64(w[i - 15], 1) ^ rotr64(w[i - 15], 8) ^ (w[i - 15] >> 7)
            let s1 = rotr64(w[i - 2], 19) ^ rotr64(w[i - 2], 61) ^ (w[i - 2] >> 6)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<80 {
            let t1 = hh &+ (rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41)) &+ ((e & f) ^ (~e & g)) &+ k512[i] &+ w[i]
            let t2 = (rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39)) &+ ((a & b) ^ (a & c) ^ (b & c))
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        for (i, v) in [a, b, c, d, e, f, g, hh].enumerated() { h[i] = h[i] &+ v }
    }
    mutating func update(_ p: UnsafeRawBufferPointer) {
        var state = h
        buffer.feed(p, blockSize: 128) { SHA512Core.compress(&state, $0) }
        h = state
    }
    func finalize(_ count: Int) -> [UInt8] {
        var state = h
        let tail = buffer.padded(blockSize: 128, lengthBytes: 16, littleEndian: false)
        for start in stride(from: 0, to: tail.count, by: 128) { SHA512Core.compress(&state, tail[start..<(start + 128)]) }
        return Array(state.flatMap { v in (0..<8).map { UInt8((v >> (56 - 8 * UInt64($0))) & 0xFF) } }.prefix(count))
    }
}
public struct SHA512Digest: Digest { public static let byteCount = 64; public let bytes: [UInt8] }
public struct SHA384Digest: Digest { public static let byteCount = 48; public let bytes: [UInt8] }
public struct SHA512: HashFunction {
    public static let blockByteCount = 128
    public static let byteCount = 64
    var core = SHA512Core(h: [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                              0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179])
    public init() {}
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) { core.update(bufferPointer) }
    public func finalize() -> SHA512Digest { SHA512Digest(bytes: core.finalize(64)) }
}
public struct SHA384: HashFunction {
    public static let blockByteCount = 128
    public static let byteCount = 48
    var core = SHA512Core(h: [0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
                              0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4])
    public init() {}
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) { core.update(bufferPointer) }
    public func finalize() -> SHA384Digest { SHA384Digest(bytes: core.finalize(48)) }
}

// MARK: - Insecure

public enum Insecure {
    public struct SHA1Digest: Digest { public static let byteCount = 20; public let bytes: [UInt8] }
    public struct MD5Digest: Digest { public static let byteCount = 16; public let bytes: [UInt8] }

    public struct SHA1: HashFunction {
        public static let blockByteCount = 64
        public static let byteCount = 20
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        var buffer = BlockBuffer()
        public init() {}
        static func compress(_ h: inout [UInt32], _ block: ArraySlice<UInt8>) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 { w[i] = be32(block, i) }
            for i in 16..<80 { w[i] = rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32)
                switch i {
                case 0..<20: (f, k) = ((b & c) | (~b & d), 0x5A827999)
                case 20..<40: (f, k) = (b ^ c ^ d, 0x6ED9EBA1)
                case 40..<60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1BBCDC)
                default: (f, k) = (b ^ c ^ d, 0xCA62C1D6)
                }
                let t = rotl32(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = rotl32(b, 30); b = a; a = t
            }
            for (i, v) in [a, b, c, d, e].enumerated() { h[i] = h[i] &+ v }
        }
        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            var state = h
            buffer.feed(bufferPointer, blockSize: 64) { SHA1.compress(&state, $0) }
            h = state
        }
        public func finalize() -> SHA1Digest {
            var state = h
            let tail = buffer.padded(blockSize: 64, lengthBytes: 8, littleEndian: false)
            for start in stride(from: 0, to: tail.count, by: 64) { SHA1.compress(&state, tail[start..<(start + 64)]) }
            return SHA1Digest(bytes: state.flatMap { v in (0..<4).map { UInt8((v >> (24 - 8 * UInt32($0))) & 0xFF) } })
        }
    }

    public struct MD5: HashFunction {
        public static let blockByteCount = 64
        public static let byteCount = 16
        static let s: [UInt32] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                                  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]
        static let k: [UInt32] = (0..<64).map { UInt32(truncatingIfNeeded: Int64(abs(sin(Double($0 + 1))) * 4294967296.0)) }
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476]
        var buffer = BlockBuffer()
        public init() {}
        static func compress(_ h: inout [UInt32], _ block: ArraySlice<UInt8>) {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let s = block.startIndex + i * 4
                m[i] = UInt32(block[s]) | UInt32(block[s + 1]) << 8 | UInt32(block[s + 2]) << 16 | UInt32(block[s + 3]) << 24
            }
            var (a, b, c, d) = (h[0], h[1], h[2], h[3])
            for i in 0..<64 {
                var f: UInt32, g: Int
                switch i {
                case 0..<16: f = (b & c) | (~b & d); g = i
                case 16..<32: f = (d & b) | (~d & c); g = (5 * i + 1) % 16
                case 32..<48: f = b ^ c ^ d; g = (3 * i + 5) % 16
                default: f = c ^ (b | ~d); g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ m[g]
                a = d; d = c; c = b; b = b &+ rotl32(f, s[i])
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        }
        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            var state = h
            buffer.feed(bufferPointer, blockSize: 64) { MD5.compress(&state, $0) }
            h = state
        }
        public func finalize() -> MD5Digest {
            var state = h
            let tail = buffer.padded(blockSize: 64, lengthBytes: 8, littleEndian: true)
            for start in stride(from: 0, to: tail.count, by: 64) { MD5.compress(&state, tail[start..<(start + 64)]) }
            return MD5Digest(bytes: state.flatMap { v in (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } })
        }
    }
}

// MARK: - Keys and HMAC

public struct SymmetricKeySize: Sendable {
    public let bitCount: Int
    public init(bitCount: Int) { self.bitCount = bitCount }
    public static let bits128 = SymmetricKeySize(bitCount: 128)
    public static let bits192 = SymmetricKeySize(bitCount: 192)
    public static let bits256 = SymmetricKeySize(bitCount: 256)
}
public struct SymmetricKey: ContiguousBytes, Sendable {
    let bytes: [UInt8]
    public init<D: ContiguousBytes>(data: D) { bytes = data.withUnsafeBytes { Array($0) } }
    public init(size: SymmetricKeySize) {
        var g = SystemRandomNumberGenerator()
        bytes = (0..<(size.bitCount / 8)).map { _ in UInt8.random(in: 0...255, using: &g) }
    }
    public var bitCount: Int { bytes.count * 8 }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
}

public struct HashedAuthenticationCode<H: HashFunction>: Hashable, Sequence, CustomStringConvertible, ContiguousBytes, Sendable {
    let bytes: [UInt8]
    public static var byteCount: Int { H.Digest.byteCount }
    public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    public var description: String { "HMAC with \(H.self): " + bytes.map { String(format: "%02x", $0) }.joined() }
}

public struct HMAC<H: HashFunction> {
    public typealias MAC = HashedAuthenticationCode<H>
    var inner: H
    var outer: H
    public init(key: SymmetricKey) {
        var k = key.bytes
        if k.count > H.blockByteCount { k = H.hash(data: k).bytes }
        k += [UInt8](repeating: 0, count: H.blockByteCount - k.count)
        inner = H(); outer = H()
        inner.update(data: k.map { $0 ^ 0x36 })
        outer.update(data: k.map { $0 ^ 0x5c })
    }
    public mutating func update<D: DataProtocol>(data: D) { inner.update(data: data) }
    public func finalize() -> MAC {
        var o = outer
        o.update(data: inner.finalize().bytes)
        return MAC(bytes: o.finalize().bytes)
    }
    public static func authenticationCode<D: DataProtocol>(for data: D, using key: SymmetricKey) -> MAC {
        var h = HMAC(key: key)
        h.update(data: data)
        return h.finalize()
    }
    public static func isValidAuthenticationCode<D: DataProtocol>(_ mac: MAC, authenticating data: D, using key: SymmetricKey) -> Bool {
        authenticationCode(for: data, using: key) == mac
    }
    public static func isValidAuthenticationCode<C: ContiguousBytes, D: DataProtocol>(_ authenticationCode: C, authenticating data: D, using key: SymmetricKey) -> Bool {
        authenticationCode.withUnsafeBytes { Array($0) } == self.authenticationCode(for: data, using: key).bytes
    }
}

// MARK: - Ciphers and curves (not available)

public enum CryptoKitError: Error, Sendable {
    case incorrectKeySize, incorrectParameterSize, authenticationFailure, underlyingCoreCryptoError(error: Int32), wrapFailure, unwrapFailure, invalidParameter
}

public enum AES {
    public enum GCM {
        public struct Nonce: ContiguousBytes, Sendable {
            let bytes: [UInt8]
            public init() { bytes = (0..<12).map { _ in UInt8.random(in: 0...255) } }
            public init<D: DataProtocol>(data: D) throws { bytes = Array(data) }
            public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
        }
        public struct SealedBox: Sendable {
            public let nonce: Nonce
            public let ciphertext: Data
            public let tag: Data
            public var combined: Data? { nil }
            public init(combined: Data) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
            public init<C: DataProtocol, T: DataProtocol>(nonce: Nonce, ciphertext: C, tag: T) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
        }
        /// AES-GCM is not implemented here; it throws.
        public static func seal<P: DataProtocol>(_ message: P, using key: SymmetricKey, nonce: Nonce? = nil) throws -> SealedBox {
            throw CryptoKitError.underlyingCoreCryptoError(error: -1)
        }
        public static func open(_ sealedBox: SealedBox, using key: SymmetricKey) throws -> Data { throw CryptoKitError.authenticationFailure }
    }
}
public enum ChaChaPoly {
    public struct SealedBox: Sendable {
        public var combined: Data { Data() }
        public init(combined: Data) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
    }
    public static func seal<P: DataProtocol>(_ message: P, using key: SymmetricKey) throws -> SealedBox { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
    public static func open(_ sealedBox: SealedBox, using key: SymmetricKey) throws -> Data { throw CryptoKitError.authenticationFailure }
}
public enum Curve25519 {
    public enum Signing {
        public struct PrivateKey: Sendable {
            public init() {}
            public init<D: ContiguousBytes>(rawRepresentation: D) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
            public var publicKey: PublicKey { PublicKey() }
            public var rawRepresentation: Data { Data() }
            public func signature<D: DataProtocol>(for data: D) throws -> Data { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
        }
        public struct PublicKey: Sendable {
            init() {}
            public init<D: ContiguousBytes>(rawRepresentation: D) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
            public var rawRepresentation: Data { Data() }
            public func isValidSignature<S: DataProtocol, D: DataProtocol>(_ signature: S, for data: D) -> Bool { false }
        }
    }
    public enum KeyAgreement {
        public struct PrivateKey: Sendable {
            public init() {}
            public var publicKey: PublicKey { PublicKey() }
            public var rawRepresentation: Data { Data() }
        }
        public struct PublicKey: Sendable {
            init() {}
            public init<D: ContiguousBytes>(rawRepresentation: D) throws { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
            public var rawRepresentation: Data { Data() }
        }
    }
}
