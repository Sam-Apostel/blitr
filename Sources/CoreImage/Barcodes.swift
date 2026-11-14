// Barcode symbol encoders behind CoreImage's generator filters: QR Code (byte mode, error correction
// levels L/M/Q/H, versions 1-40, all eight masks with the standard penalty) and Code 128 (code sets
// A, B and C). Each returns a module matrix, `true` for dark.

enum QRCode {
    enum ECC: Int { case low = 0, medium, quartile, high
        var formatBits: Int { [1, 0, 3, 2][rawValue] }
        init(letter: String) {
            switch letter.uppercased() {
            case "L": self = .low
            case "Q": self = .quartile
            case "H": self = .high
            default: self = .medium
            }
        }
    }

    static let eccCodewordsPerBlock: [[Int]] = [
        [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
        [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    ]
    static let errorCorrectionBlocks: [[Int]] = [
        [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
        [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
        [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
        [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
    ]

    static func rawDataModules(_ version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let align = version / 7 + 2
            result -= (25 * align - 10) * align - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }
    static func dataCodewords(_ version: Int, _ ecc: ECC) -> Int {
        rawDataModules(version) / 8 - eccCodewordsPerBlock[ecc.rawValue][version] * errorCorrectionBlocks[ecc.rawValue][version]
    }

    /// The symbol for `data` in byte mode at the smallest version that holds it; nil when it is too long.
    static func encode(_ data: [UInt8], ecc: ECC) -> [[Bool]]? {
        var version = 1
        while version <= 40 {
            let countBits = version <= 9 ? 8 : 16
            if 4 + countBits + data.count * 8 <= dataCodewords(version, ecc) * 8 { break }
            version += 1
        }
        guard version <= 40 else { return nil }
        // Bit stream: mode, count, data, terminator, padding.
        var bits: [Bool] = []
        func append(_ value: Int, _ count: Int) { for i in stride(from: count - 1, through: 0, by: -1) { bits.append((value >> i) & 1 == 1) } }
        append(0b0100, 4)
        append(data.count, version <= 9 ? 8 : 16)
        for byte in data { append(Int(byte), 8) }
        let capacity = dataCodewords(version, ecc) * 8
        append(0, min(4, capacity - bits.count))
        append(0, (8 - bits.count % 8) % 8)
        var pad = 0xEC
        while bits.count < capacity { append(pad, 8); pad ^= 0xEC ^ 0x11 }
        var codewords = [UInt8](repeating: 0, count: bits.count / 8)
        for (i, bit) in bits.enumerated() where bit { codewords[i >> 3] |= 1 << (7 - UInt8(i & 7)) }

        var symbol = Symbol(version: version)
        symbol.drawFunctionPatterns()
        symbol.drawCodewords(interleave(codewords, version: version, ecc: ecc))
        // Pick the mask with the lowest penalty.
        var best = 0, bestPenalty = Int.max
        for mask in 0..<8 {
            symbol.applyMask(mask)
            symbol.drawFormatBits(ecc: ecc, mask: mask)
            let penalty = symbol.penalty()
            if penalty < bestPenalty { best = mask; bestPenalty = penalty }
            symbol.applyMask(mask)
        }
        symbol.applyMask(best)
        symbol.drawFormatBits(ecc: ecc, mask: best)
        return symbol.modules
    }

    static func interleave(_ data: [UInt8], version: Int, ecc: ECC) -> [UInt8] {
        let blocks = errorCorrectionBlocks[ecc.rawValue][version], eccLength = eccCodewordsPerBlock[ecc.rawValue][version]
        let raw = rawDataModules(version) / 8
        let shortBlocks = blocks - raw % blocks, shortLength = raw / blocks
        let divisor = reedSolomonDivisor(eccLength)
        var list: [[UInt8]] = []
        var k = 0
        for i in 0..<blocks {
            let length = shortLength - eccLength + (i < shortBlocks ? 0 : 1)
            var block = Array(data[k..<(k + length)])
            k += length
            let ecc = reedSolomonRemainder(block, divisor)
            if i < shortBlocks { block.append(0) }
            list.append(block + ecc)
        }
        var result: [UInt8] = []
        for i in 0..<list[0].count {
            for (j, block) in list.enumerated() where i != shortLength - eccLength || j >= shortBlocks { result.append(block[i]) }
        }
        return result
    }

    static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((Int(y) >> i) & 1) * Int(x)
        }
        return UInt8(z & 0xFF)
    }
    static func reedSolomonDivisor(_ degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = multiply(result[j], root)
                if j + 1 < degree { result[j] ^= result[j + 1] }
            }
            root = multiply(root, 0x02)
        }
        return result
    }
    static func reedSolomonRemainder(_ data: [UInt8], _ divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for i in 0..<result.count { result[i] ^= multiply(divisor[i], factor) }
        }
        return result
    }

    struct Symbol {
        let version: Int
        let size: Int
        var modules: [[Bool]]
        var isFunction: [[Bool]]

        init(version: Int) {
            self.version = version
            size = version * 4 + 17
            modules = Array(repeating: Array(repeating: false, count: size), count: size)
            isFunction = modules
        }

        mutating func set(_ x: Int, _ y: Int, _ dark: Bool) {
            modules[y][x] = dark
            isFunction[y][x] = true
        }

        var alignmentPositions: [Int] {
            guard version > 1 else { return [] }
            let count = version / 7 + 2
            let step = version == 32 ? 26 : (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2
            var result = [Int](repeating: 0, count: count)
            result[0] = 6
            var position = size - 7
            for i in stride(from: count - 1, through: 1, by: -1) { result[i] = position; position -= step }
            return result
        }

        mutating func drawFunctionPatterns() {
            for i in 0..<size { set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0) }
            for (cx, cy) in [(3, 3), (size - 4, 3), (3, size - 4)] {
                for dy in -4...4 {
                    for dx in -4...4 {
                        let (x, y) = (cx + dx, cy + dy)
                        guard x >= 0, x < size, y >= 0, y < size else { continue }
                        let distance = max(abs(dx), abs(dy))
                        set(x, y, distance != 2 && distance != 4)
                    }
                }
            }
            let positions = alignmentPositions
            let last = positions.count - 1
            for i in positions.indices {
                for j in positions.indices where !((i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)) {
                    for dy in -2...2 { for dx in -2...2 { set(positions[i] + dx, positions[j] + dy, max(abs(dx), abs(dy)) != 1) } }
                }
            }
            drawFormatBits(ecc: .low, mask: 0)
            if version >= 7 {
                var remainder = version
                for _ in 0..<12 { remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25) }
                let bits = version << 12 | remainder
                for i in 0..<18 {
                    let bit = (bits >> i) & 1 == 1
                    let a = size - 11 + i % 3, b = i / 3
                    set(a, b, bit)
                    set(b, a, bit)
                }
            }
        }

        mutating func drawFormatBits(ecc: ECC, mask: Int) {
            let data = ecc.formatBits << 3 | mask
            var remainder = data
            for _ in 0..<10 { remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537) }
            let bits = (data << 10 | remainder) ^ 0x5412
            func bit(_ i: Int) -> Bool { (bits >> i) & 1 == 1 }
            for i in 0...5 { set(8, i, bit(i)) }
            set(8, 7, bit(6))
            set(8, 8, bit(7))
            set(7, 8, bit(8))
            for i in 9..<15 { set(14 - i, 8, bit(i)) }
            for i in 0..<8 { set(size - 1 - i, 8, bit(i)) }
            for i in 8..<15 { set(8, size - 15 + i, bit(i)) }
            set(8, size - 8, true)
        }

        mutating func drawCodewords(_ data: [UInt8]) {
            var i = 0
            var right = size - 1
            while right >= 1 {
                if right == 6 { right = 5 }
                for vertical in 0..<size {
                    for j in 0..<2 {
                        let x = right - j
                        let upward = (right + 1) & 2 == 0
                        let y = upward ? size - 1 - vertical : vertical
                        if !isFunction[y][x] && i < data.count * 8 {
                            modules[y][x] = (data[i >> 3] >> (7 - UInt8(i & 7))) & 1 == 1
                            i += 1
                        }
                    }
                }
                right -= 2
            }
        }

        mutating func applyMask(_ mask: Int) {
            for y in 0..<size {
                for x in 0..<size where !isFunction[y][x] {
                    let invert: Bool
                    switch mask {
                    case 0: invert = (x + y) % 2 == 0
                    case 1: invert = y % 2 == 0
                    case 2: invert = x % 3 == 0
                    case 3: invert = (x + y) % 3 == 0
                    case 4: invert = (x / 3 + y / 2) % 2 == 0
                    case 5: invert = x * y % 2 + x * y % 3 == 0
                    case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                    default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                    }
                    if invert { modules[y][x].toggle() }
                }
            }
        }

        /// The standard penalty: runs, 2x2 blocks, finder-like patterns, dark/light balance.
        func penalty() -> Int {
            var result = 0
            func lineScore(_ line: [Bool]) -> Int {
                var score = 0, run = 1
                for i in 1..<line.count {
                    if line[i] == line[i - 1] { run += 1 } else { if run >= 5 { score += 3 + run - 5 }; run = 1 }
                }
                if run >= 5 { score += 3 + run - 5 }
                // 1:1:3:1:1 finder-like patterns with four light modules on one side.
                let pattern: [Bool] = [true, false, true, true, true, false, true]
                if line.count >= 11 {
                    for i in 0...(line.count - 7) where Array(line[i..<(i + 7)]) == pattern {
                        let before = i >= 4 && line[(i - 4)..<i].allSatisfy { !$0 }
                        let after = i + 11 <= line.count && line[(i + 7)..<(i + 11)].allSatisfy { !$0 }
                        if before || after { score += 40 }
                    }
                }
                return score
            }
            for y in 0..<size { result += lineScore(modules[y]) }
            for x in 0..<size { result += lineScore((0..<size).map { modules[$0][x] }) }
            for y in 0..<(size - 1) {
                for x in 0..<(size - 1) {
                    let c = modules[y][x]
                    if c == modules[y][x + 1] && c == modules[y + 1][x] && c == modules[y + 1][x + 1] { result += 3 }
                }
            }
            let dark = modules.reduce(0) { $0 + $1.filter { $0 }.count }
            let total = size * size
            let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
            result += max(0, k) * 10
            return result
        }
    }
}

enum Code128 {
    /// Bar/space widths of the 107 symbols (103-105 are the start codes, 106 the stop pattern).
    static let patterns: [String] = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
        "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
        "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
        "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
        "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
        "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
        "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
        "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
        "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
        "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
    ]

    /// Symbol values for the bytes (ASCII 0-127), switching between code sets A, B and C.
    static func symbols(_ bytes: [UInt8]) -> [Int] {
        enum Set { case a, b, c }
        func digitRun(_ i: Int) -> Int {
            var j = i
            while j < bytes.count, bytes[j] >= 0x30, bytes[j] <= 0x39 { j += 1 }
            return j - i
        }
        var result: [Int] = []
        var current: Set
        var i = 0
        let leading = digitRun(0)
        if leading >= 2 && leading % 2 == 0 && (leading >= 4 || leading == bytes.count) {
            current = .c; result.append(105)
        } else if let first = bytes.first, first < 32 {
            current = .a; result.append(103)
        } else {
            current = .b; result.append(104)
        }
        while i < bytes.count {
            let run = digitRun(i)
            if current == .c {
                if run >= 2 {
                    result.append(Int(bytes[i] - 0x30) * 10 + Int(bytes[i + 1] - 0x30))
                    i += 2
                    continue
                }
                let next: Set = bytes[i] < 32 ? .a : .b
                result.append(next == .a ? 101 : 100)
                current = next
                continue
            }
            // Switch to C for runs of digits worth it: four or more at the end, six or more in the middle.
            if run >= 4 && (i + run == bytes.count || run >= 6) {
                if run % 2 == 1 { result.append(value(bytes[i], in: current == .a)); i += 1 }
                result.append(99)
                current = .c
                continue
            }
            let byte = bytes[i]
            if byte < 32 && current == .b { result.append(101); current = .a }
            else if byte >= 96 && current == .a { result.append(100); current = .b }
            result.append(value(byte, in: current == .a))
            i += 1
        }
        var checksum = result[0]
        for (index, symbol) in result.enumerated().dropFirst() { checksum += symbol * index }
        result.append(checksum % 103)
        result.append(106)
        return result
    }

    static func value(_ byte: UInt8, in setA: Bool) -> Int {
        if setA { return byte < 32 ? Int(byte) + 64 : Int(byte) - 32 }
        return Int(byte) - 32
    }

    /// Modules (dark = bar) for the bytes, without quiet zones.
    static func modules(_ bytes: [UInt8]) -> [Bool] {
        var result: [Bool] = []
        for symbol in symbols(bytes) {
            var dark = true
            for width in patterns[symbol] {
                result += Array(repeating: dark, count: Int(String(width))!)
                dark.toggle()
            }
        }
        return result
    }
}
