#!/usr/bin/env swift
// Generates sf-symbols-map.json: SF Symbol names to SF Pro private-use code points.
//
//   scripts/mac/generate-symbol-map.sh [--font Vendor/apple-fonts/SF-Pro.ttf] [--out <dir>]   (compiled; minutes faster)
//
// Apple ships the symbol name table only in obfuscated form, so the names are recovered by drawing:
// every name the system knows (CoreGlyphs.bundle) is rendered with NSImage(systemSymbolName:), every
// private-use code point of SF Pro is rendered with CoreText at the same size and weight, and the two
// sets are matched by their normalized bitmaps. The output holds names and code points only.
//
// The SF Pro font comes from scripts/fetch-apple-fonts.sh. --out defaults to the font's directory,
// which is where the renderer looks for the map.

import AppKit
import CoreText
import Foundation

// MARK: Options

var fontPath = "Vendor/apple-fonts/SF-Pro.ttf"
var outDir: String?
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--font": fontPath = args.popFirst() ?? fontPath
    case "--out": outDir = args.popFirst()
    default:
        FileHandle.standardError.write(Data("usage: generate-symbol-map.swift [--font SF-Pro.ttf] [--out dir]\n".utf8))
        exit(2)
    }
}
guard FileManager.default.fileExists(atPath: fontPath) else {
    FileHandle.standardError.write(Data("\(fontPath) not found. Run scripts/fetch-apple-fonts.sh --accept-apple-font-license first.\n".utf8))
    exit(1)
}
let outputPath = (outDir ?? (fontPath as NSString).deletingLastPathComponent) + "/sf-symbols-map.json"

// MARK: Normalized bitmaps

let pointSize: CGFloat = 64
let canvas = 160          // drawing surface, large enough for any symbol at 64pt
let grid = 24             // normalized size

/// A symbol's ink, cropped to its bounding box and resampled to grid x grid, plus its aspect ratio.
struct Signature {
    var pixels: [Float]
    var aspect: Float
    var key: String {
        // Coarse exact-match key: 12x12 binarized plus quantized aspect.
        var bits = ""
        for y in stride(from: 0, to: grid, by: 2) {
            for x in stride(from: 0, to: grid, by: 2) { bits += pixels[y * grid + x] > 0.5 ? "1" : "0" }
        }
        return bits + "|" + String(Int((aspect * 20).rounded()))
    }
    func distance(_ other: Signature) -> Float {
        var sum: Float = 0
        for i in 0..<pixels.count { let d = pixels[i] - other.pixels[i]; sum += d * d }
        return sum + abs(aspect - other.aspect) * 40
    }
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas,
              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
}

func signature(of context: CGContext) -> Signature? {
    guard let data = context.data else { return nil }
    let buffer = data.bindMemory(to: UInt8.self, capacity: canvas * canvas)
    var minX = canvas, minY = canvas, maxX = -1, maxY = -1
    for y in 0..<canvas {
        for x in 0..<canvas where 255 - Int(buffer[y * canvas + x]) > 40 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let w = maxX - minX + 1, h = maxY - minY + 1
    var pixels = [Float](repeating: 0, count: grid * grid)
    for gy in 0..<grid {
        for gx in 0..<grid {
            // Box-filter the source cell.
            let x0 = minX + gx * w / grid, x1 = max(x0 + 1, minX + (gx + 1) * w / grid)
            let y0 = minY + gy * h / grid, y1 = max(y0 + 1, minY + (gy + 1) * h / grid)
            var sum = 0, count = 0
            for y in y0..<min(y1, canvas) { for x in x0..<min(x1, canvas) { sum += 255 - Int(buffer[y * canvas + x]); count += 1 } }
            pixels[gy * grid + gx] = count > 0 ? Float(sum) / Float(count * 255) : 0
        }
    }
    return Signature(pixels: pixels, aspect: Float(w) / Float(h))
}

// MARK: Symbols by name

let resources = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources"
var names: [String] = []
if let order = NSArray(contentsOfFile: resources + "/symbol_order.plist") as? [String] { names = order }
if let availability = NSDictionary(contentsOfFile: resources + "/name_availability.plist")?["symbols"] as? [String: Any] {
    let known = Set(names)
    names += availability.keys.filter { !known.contains($0) }.sorted()
}
FileHandle.standardError.write(Data("\(names.count) symbol names\n".utf8))

let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
var byName: [(String, Signature)] = []
for name in names {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { continue }
    // Ink is black on white on both sides; signature(of:) inverts it.
    let context = makeContext()
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    var proposed = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { continue }
    context.draw(cg, in: CGRect(x: (CGFloat(canvas) - image.size.width) / 2, y: (CGFloat(canvas) - image.size.height) / 2,
                                width: image.size.width, height: image.size.height))
    if let sig = signature(of: context) { byName.append((name, sig)) }
}
FileHandle.standardError.write(Data("\(byName.count) names rendered\n".utf8))

// MARK: Glyphs by code point

guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: fontPath) as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first else {
    FileHandle.standardError.write(Data("could not load \(fontPath)\n".utf8)); exit(1)
}
// Regular weight, matching the NSImage configuration.
let weighted = CTFontDescriptorCreateCopyWithVariation(descriptor, 0x7767_6874 as CFNumber /* 'wght' */, 400)
let font = CTFontCreateWithFontDescriptor(weighted, pointSize, nil)

var byCodePoint: [(UInt32, Signature)] = []
for cp in UInt32(0x100000)...UInt32(0x10FFFD) {
    guard let scalar = UnicodeScalar(cp) else { continue }
    var units = Array(String(scalar).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0,
          let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { continue }
    let box = path.boundingBoxOfPath
    guard box.width > 0, box.height > 0 else { continue }
    let context = makeContext()
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.translateBy(x: (CGFloat(canvas) - box.width) / 2 - box.minX, y: (CGFloat(canvas) - box.height) / 2 - box.minY)
    context.addPath(path)
    context.setFillColor(gray: 0, alpha: 1)
    context.fillPath()
    if let sig = signature(of: context) { byCodePoint.append((cp, sig)) }
}
FileHandle.standardError.write(Data("\(byCodePoint.count) private-use glyphs in the font\n".utf8))

// MARK: Match

var exact: [String: [Int]] = [:]
for (i, item) in byCodePoint.enumerated() { exact[item.1.key, default: []].append(i) }

// Squared distance over 576 cells. Below `threshold` a match is taken; up to 15 it is taken when no
// different-looking glyph is within twice the distance. Anything else is left out of the map.
let threshold: Float = 6
var map: [String: String] = [:]
var unmatched: [String] = []
var report: [(String, Float, Float)] = []
for (name, sig) in byName {
    // The exact-key bucket is tried first; if nothing in it is close, search every glyph of a similar shape.
    // Returns the closest glyph, its distance, and the distance of the closest glyph that looks different
    // from it (fonts carry duplicate glyphs under several code points, which must not count as rivals).
    func best(in candidates: [Int]) -> (Int, Float, Float)? {
        guard let top = candidates.min(by: { sig.distance(byCodePoint[$0].1) < sig.distance(byCodePoint[$1].1) }) else { return nil }
        let topSig = byCodePoint[top].1
        var rival: Float = .infinity
        for i in candidates where topSig.distance(byCodePoint[i].1) > 0.5 { rival = min(rival, sig.distance(byCodePoint[i].1)) }
        return (top, sig.distance(topSig), rival)
    }
    func accept(_ f: (Int, Float, Float)) -> Bool { f.1 < threshold || (f.1 < 15 && f.1 < 0.5 * f.2) }
    var found = best(in: exact[sig.key] ?? [])
    if found == nil || !accept(found!) {
        found = best(in: byCodePoint.indices.filter { abs(byCodePoint[$0].1.aspect - sig.aspect) < 0.15 })
    }
    if let found { report.append((name, found.1, found.2)) }
    if let found, accept(found) {
        map[name] = String(format: "%06X", byCodePoint[found.0].0)
    } else {
        unmatched.append(name)
    }
}
if let path = ProcessInfo.processInfo.environment["SYMBOL_MAP_DISTANCES"] {
    let lines = report.map { "\($0.0)\t\($0.1)\t\($0.2)" }.joined(separator: "\n")
    try? lines.write(toFile: path, atomically: true, encoding: .utf8)
}

// Sanity checks confirmed earlier with the renderer.
for (name, expected) in [("chevron.right", "10018A"), ("heart.fill", "1002B5")] where map[name] != nil && map[name] != expected {
    FileHandle.standardError.write(Data("warning: \(name) matched \(map[name]!), expected \(expected)\n".utf8))
}

let sorted = map.sorted { $0.key < $1.key }
var json = "{\n  \"generated\": \"\(ISO8601DateFormatter().string(from: Date()))\",\n"
json += "  \"macOS\": \"\(ProcessInfo.processInfo.operatingSystemVersionString)\",\n  \"symbols\": {\n"
json += sorted.map { "    \"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",\n")
json += "\n  }\n}\n"
try json.write(toFile: outputPath, atomically: true, encoding: .utf8)
print("\(map.count) of \(byName.count) names mapped (\(unmatched.count) unmatched) -> \(outputPath)")
