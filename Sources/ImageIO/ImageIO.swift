internal import CSkia
@_exported import CoreGraphics

// `import ImageIO`: decoding and encoding through Skia's codecs (PNG, JPEG, WebP, GIF, BMP in; PNG, JPEG, WebP
// out). HEIC and AVIF are recognised but cannot be decoded or encoded. Properties come from the
// codec (size, orientation) and, for JPEG, from the EXIF block (TIFF, Exif and GPS dictionaries).

/// EXIF orientation values, as ImageIO and `Image.Orientation`'s cases order them.
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left
}

public enum CGImageSourceStatus: Int32, Sendable {
    case statusUnexpectedEOF = -5, statusInvalidData = -4, statusUnknownType = -3, statusReadingHeader = -2, statusIncomplete = -1, statusComplete = 0
}

public final class CGImageSource: @unchecked Sendable {
    let data: Data
    let type: String?
    let pixelSize: (width: Int, height: Int)?
    /// EXIF orientation of the stored pixels (1 = upright).
    let orientation: Int
    let frameCount: Int

    init(data: Data) {
        self.data = data
        type = _encodedFormatName(data)
        var size: (Int, Int)?
        var origin = 1, frames = 0
        data.withUnsafeBytes { buffer in
            guard let skData = sk_data_new_with_copy(buffer.baseAddress, buffer.count) else { return }
            defer { sk_data_unref(skData) }
            guard let codec = sk_codec_new_from_data(skData) else { return }
            defer { sk_codec_destroy(codec) }
            var info = sk_imageinfo_t()
            sk_codec_get_info(codec, &info)
            size = (Int(info.width), Int(info.height))
            origin = Int(sk_codec_get_origin(codec).rawValue)
            frames = max(1, Int(sk_codec_get_frame_count(codec)))
        }
        pixelSize = size
        orientation = (1...8).contains(origin) ? origin : 1
        frameCount = frames
        if size == nil, let type, type == "public.heic" || type == "public.avif" {
            ShimDiagnostics.warn("ImageIO: \(type) data cannot be decoded here (PNG, JPEG, WebP, GIF and BMP can); the image source is empty")
        }
    }

    /// The stored pixels, not turned by the EXIF orientation (as ImageIO returns them).
    func storedImage() -> CGImage? {
        guard let upright = SkImageBox.decode(data) else { return nil }
        let image = CGImage(box: upright)
        image.sourceType = type
        // Skia's image decoder applies the orientation; undo it so `kCGImagePropertyOrientation` still describes the pixels.
        guard orientation != 1, let (w, h) = pixelSize, upright.width != w || upright.height != h || orientation <= 4 else { return image }
        let inverse: [Int: PixelOrientation] = [2: .upMirrored, 3: .down, 4: .downMirrored, 5: .leftMirrored, 6: .left, 7: .rightMirrored, 8: .right]
        let stored = image.oriented(inverse[orientation] ?? .up)
        stored.sourceType = type
        return stored
    }
    func uprightImage() -> CGImage? {
        SkImageBox.decode(data).map { box in
            let image = CGImage(box: box)
            image.sourceType = type
            return image
        }
    }
}

public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { CGImageSource(data: data as Data) }
public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    (try? Data(contentsOf: url as URL)).map(CGImageSource.init(data:))
}
public func CGImageSourceCreateWithDataProvider(_ provider: CGDataProvider, _ options: CFDictionary?) -> CGImageSource? {
    CGImageSource(data: provider.bytes)
}
public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { isrc.frameCount }
public func CGImageSourceGetPrimaryImageIndex(_ isrc: CGImageSource) -> Int { 0 }
public func CGImageSourceGetType(_ isrc: CGImageSource) -> CFString? { isrc.type.map { $0 as NSString } }
public func CGImageSourceGetStatus(_ isrc: CGImageSource) -> CGImageSourceStatus {
    isrc.pixelSize != nil ? .statusComplete : isrc.type != nil ? .statusInvalidData : .statusUnknownType
}
public func CGImageSourceCopyTypeIdentifiers() -> CFArray {
    ["public.png", "public.jpeg", "org.webmproject.webp", "com.compuserve.gif", "com.microsoft.bmp", "com.microsoft.ico"] as NSArray
}

/// Only the first frame of an animated image is decoded.
public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard index == 0 else { return nil }
    return isrc.storedImage()
}

public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard index == 0 else { return nil }
    func flag(_ key: CFString) -> Bool { (_cfNumber(options?.object(forKey: key)) ?? 0) != 0 }
    // There are no embedded thumbnails to return: without a "create" flag ImageIO gives nil.
    guard flag(kCGImageSourceCreateThumbnailFromImageAlways) || flag(kCGImageSourceCreateThumbnailFromImageIfAbsent) else { return nil }
    guard let image = flag(kCGImageSourceCreateThumbnailWithTransform) ? isrc.uprightImage() : isrc.storedImage() else { return nil }
    guard let limit = _cfNumber(options?.object(forKey: kCGImageSourceThumbnailMaxPixelSize)), limit >= 1 else { return image }
    let longest = Double(max(image.width, image.height))
    guard longest > limit else { return image }
    let factor = limit / longest
    let (w, h) = (max(1, Int((Double(image.width) * factor).rounded())), max(1, Int((Double(image.height) * factor).rounded())))
    return image.box.scaled(width: w, height: h).map { CGImage(box: $0) }
}

public func CGImageSourceCopyProperties(_ isrc: CGImageSource, _ options: CFDictionary?) -> CFDictionary? {
    guard isrc.pixelSize != nil else { return nil }
    return [:] as NSDictionary
}

public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? {
    guard index == 0, let size = isrc.pixelSize else { return nil }
    var properties: [CFString: Any] = [
        kCGImagePropertyPixelWidth: NSNumber(value: size.width),
        kCGImagePropertyPixelHeight: NSNumber(value: size.height),
        kCGImagePropertyOrientation: NSNumber(value: isrc.orientation),
        kCGImagePropertyDepth: NSNumber(value: 8),
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
    ]
    if isrc.type == "public.png" || isrc.type == "org.webmproject.webp" || isrc.type == "com.compuserve.gif" {
        properties[kCGImagePropertyHasAlpha] = NSNumber(value: true)
    }
    if isrc.type == "public.jpeg" {
        let exif = ExifReader(jpeg: isrc.data)
        if !exif.tiff.isEmpty { properties[kCGImagePropertyTIFFDictionary] = exif.tiff }
        if !exif.exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif.exif }
        if !exif.gps.isEmpty { properties[kCGImagePropertyGPSDictionary] = exif.gps }
    }
    return properties as NSDictionary
}

// MARK: - Destination

public final class CGImageDestination: @unchecked Sendable {
    let format: EncodedFormat
    let data: NSMutableData?
    let url: URL?
    var images: [(image: CGImage, quality: Double)] = []
    var quality = 1.0

    init?(type: String, data: NSMutableData?, url: URL?) {
        switch type {
        case "public.png": format = .png
        case "public.jpeg", "public.jpg": format = .jpeg
        case "org.webmproject.webp", "public.webp": format = .webp
        default:
            ShimDiagnostics.warn("ImageIO: cannot encode \(type) here (PNG, JPEG and WebP can); CGImageDestinationCreate returns nil")
            return nil
        }
        self.data = data
        self.url = url
    }
}

public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    CGImageDestination(type: type as String, data: data, url: nil)
}
public func CGImageDestinationCreateWithURL(_ url: CFURL, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    CGImageDestination(type: type as String, data: nil, url: url as URL)
}
public func CGImageDestinationCopyTypeIdentifiers() -> CFArray { ["public.png", "public.jpeg", "org.webmproject.webp"] as NSArray }
public func CGImageDestinationSetProperties(_ idst: CGImageDestination, _ properties: CFDictionary?) {
    if let q = _cfNumber(properties?.object(forKey: kCGImageDestinationLossyCompressionQuality)) { idst.quality = q }
}
/// The compression quality is honoured; metadata dictionaries are not written.
public func CGImageDestinationAddImage(_ idst: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) {
    let quality = _cfNumber(properties?.object(forKey: kCGImageDestinationLossyCompressionQuality)) ?? idst.quality
    idst.images.append((image, quality))
}
public func CGImageDestinationAddImageFromSource(_ idst: CGImageDestination, _ isrc: CGImageSource, _ index: Int, _ properties: CFDictionary?) {
    guard let image = CGImageSourceCreateImageAtIndex(isrc, index, nil) else { return }
    CGImageDestinationAddImage(idst, image, properties)
}
/// Writes the first image (the formats that can be encoded hold one).
public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool {
    guard let first = idst.images.first, let encoded = first.image.box.encoded(idst.format, quality: first.quality) else { return false }
    if let data = idst.data { data.append(encoded) }
    if let url = idst.url { do { try encoded.write(to: url) } catch { return false } }
    return true
}

// MARK: - Keys

public let kCGImageSourceTypeIdentifierHint: CFString = "kCGImageSourceTypeIdentifierHint"
public let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceShouldAllowFloat: CFString = "kCGImageSourceShouldAllowFloat"
public let kCGImageSourceCreateThumbnailFromImageIfAbsent: CFString = "kCGImageSourceCreateThumbnailFromImageIfAbsent"
public let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceSubsampleFactor: CFString = "kCGImageSourceSubsampleFactor"

public let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"
public let kCGImageDestinationBackgroundColor: CFString = "kCGImageDestinationBackgroundColor"
public let kCGImageDestinationImageMaxPixelSize: CFString = "kCGImageDestinationImageMaxPixelSize"
public let kCGImageDestinationEmbedThumbnail: CFString = "kCGImageDestinationEmbedThumbnail"
public let kCGImageDestinationOptimizeColorForSharing: CFString = "kCGImageDestinationOptimizeColorForSharing"
public let kCGImageDestinationOrientation: CFString = "kCGImageDestinationOrientation"
public let kCGImageDestinationMetadata: CFString = "kCGImageDestinationMetadata"

public let kCGImagePropertyPixelWidth: CFString = "PixelWidth"
public let kCGImagePropertyPixelHeight: CFString = "PixelHeight"
public let kCGImagePropertyOrientation: CFString = "Orientation"
public let kCGImagePropertyDepth: CFString = "Depth"
public let kCGImagePropertyDPIWidth: CFString = "DPIWidth"
public let kCGImagePropertyDPIHeight: CFString = "DPIHeight"
public let kCGImagePropertyHasAlpha: CFString = "HasAlpha"
public let kCGImagePropertyColorModel: CFString = "ColorModel"
public let kCGImagePropertyColorModelRGB: CFString = "RGB"
public let kCGImagePropertyColorModelGray: CFString = "Gray"
public let kCGImagePropertyProfileName: CFString = "ProfileName"
public let kCGImagePropertyFileSize: CFString = "FileSize"
public let kCGImagePropertyTIFFDictionary: CFString = "{TIFF}"
public let kCGImagePropertyExifDictionary: CFString = "{Exif}"
public let kCGImagePropertyGPSDictionary: CFString = "{GPS}"
public let kCGImagePropertyIPTCDictionary: CFString = "{IPTC}"
public let kCGImagePropertyPNGDictionary: CFString = "{PNG}"
public let kCGImagePropertyJFIFDictionary: CFString = "{JFIF}"
public let kCGImagePropertyGIFDictionary: CFString = "{GIF}"
public let kCGImagePropertyHEICSDictionary: CFString = "{HEICS}"
public let kCGImagePropertyMakerAppleDictionary: CFString = "{MakerApple}"
public let kCGImagePropertyTIFFMake: CFString = "Make"
public let kCGImagePropertyTIFFModel: CFString = "Model"
public let kCGImagePropertyTIFFOrientation: CFString = "Orientation"
public let kCGImagePropertyTIFFDateTime: CFString = "DateTime"
public let kCGImagePropertyTIFFSoftware: CFString = "Software"
public let kCGImagePropertyTIFFXResolution: CFString = "XResolution"
public let kCGImagePropertyTIFFYResolution: CFString = "YResolution"
public let kCGImagePropertyExifDateTimeOriginal: CFString = "DateTimeOriginal"
public let kCGImagePropertyExifDateTimeDigitized: CFString = "DateTimeDigitized"
public let kCGImagePropertyExifOffsetTime: CFString = "OffsetTime"
public let kCGImagePropertyExifOffsetTimeOriginal: CFString = "OffsetTimeOriginal"
public let kCGImagePropertyExifSubsecTimeOriginal: CFString = "SubsecTimeOriginal"
public let kCGImagePropertyExifPixelXDimension: CFString = "PixelXDimension"
public let kCGImagePropertyExifPixelYDimension: CFString = "PixelYDimension"
public let kCGImagePropertyExifExposureTime: CFString = "ExposureTime"
public let kCGImagePropertyExifFNumber: CFString = "FNumber"
public let kCGImagePropertyExifISOSpeedRatings: CFString = "ISOSpeedRatings"
public let kCGImagePropertyExifFocalLength: CFString = "FocalLength"
public let kCGImagePropertyExifLensModel: CFString = "LensModel"
public let kCGImagePropertyExifUserComment: CFString = "UserComment"
public let kCGImagePropertyGPSLatitude: CFString = "Latitude"
public let kCGImagePropertyGPSLatitudeRef: CFString = "LatitudeRef"
public let kCGImagePropertyGPSLongitude: CFString = "Longitude"
public let kCGImagePropertyGPSLongitudeRef: CFString = "LongitudeRef"
public let kCGImagePropertyGPSAltitude: CFString = "Altitude"
public let kCGImagePropertyGPSAltitudeRef: CFString = "AltitudeRef"
public let kCGImagePropertyGPSTimeStamp: CFString = "TimeStamp"
public let kCGImagePropertyGPSDateStamp: CFString = "DateStamp"
public let kCGImagePropertyGPSImgDirection: CFString = "ImgDirection"
public let kCGImagePropertyGPSSpeed: CFString = "Speed"
public let kCGImagePropertyGIFLoopCount: CFString = "LoopCount"
public let kCGImagePropertyGIFDelayTime: CFString = "DelayTime"
public let kCGImagePropertyGIFUnclampedDelayTime: CFString = "UnclampedDelayTime"

// MARK: - EXIF

/// Reads the TIFF, Exif and GPS directories of a JPEG's EXIF block into ImageIO's dictionaries.
struct ExifReader {
    var tiff: [CFString: Any] = [:]
    var exif: [CFString: Any] = [:]
    var gps: [CFString: Any] = [:]

    private var bytes: [UInt8] = []
    private var base = 0
    private var little = true

    init(jpeg data: Data) {
        let all = [UInt8](data)
        guard all.count > 4, all[0] == 0xFF, all[1] == 0xD8 else { return }
        var i = 2
        while i + 4 <= all.count, all[i] == 0xFF {
            let marker = all[i + 1]
            let length = Int(all[i + 2]) << 8 | Int(all[i + 3])
            if marker == 0xDA || length < 2 { break }
            if marker == 0xE1, i + 10 <= all.count, Array(all[(i + 4)..<(i + 10)]) == [0x45, 0x78, 0x69, 0x66, 0, 0] {
                bytes = Array(all[(i + 10)..<min(all.count, i + 2 + length)])
                parse()
                return
            }
            i += 2 + length
        }
    }

    private func u16(_ o: Int) -> Int {
        guard o >= 0, o + 2 <= bytes.count else { return 0 }
        return little ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : Int(bytes[o]) << 8 | Int(bytes[o + 1])
    }
    private func u32(_ o: Int) -> Int {
        guard o >= 0, o + 4 <= bytes.count else { return 0 }
        let b = (0..<4).map { Int(bytes[o + $0]) }
        return little ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24 : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
    }

    private enum Value { case text(String), numbers([Double]) }

    private func entries(at offset: Int) -> [Int: Value] {
        var result: [Int: Value] = [:]
        guard offset > 0, offset + 2 <= bytes.count else { return result }
        let count = u16(offset)
        for n in 0..<min(count, 512) {
            let e = offset + 2 + n * 12
            guard e + 12 <= bytes.count else { break }
            let tag = u16(e), type = u16(e + 2), items = u32(e + 4)
            let unit = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8][type] ?? 0
            guard unit > 0, items > 0, items < 65536 else { continue }
            let at = unit * items <= 4 ? e + 8 : u32(e + 8)
            guard at >= 0, at + unit * items <= bytes.count else { continue }
            switch type {
            case 2:
                let raw = bytes[at..<(at + items)].prefix { $0 != 0 }
                result[tag] = .text(String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces))
            case 5, 10:
                result[tag] = .numbers((0..<items).map { k in
                    let (num, den) = (u32(at + k * 8), u32(at + k * 8 + 4))
                    return den == 0 ? 0 : Double(type == 10 ? Int(Int32(truncatingIfNeeded: num)) : num) / Double(type == 10 ? Int(Int32(truncatingIfNeeded: den)) : den)
                })
            case 3: result[tag] = .numbers((0..<items).map { Double(u16(at + $0 * 2)) })
            case 4, 9: result[tag] = .numbers((0..<items).map { Double(u32(at + $0 * 4)) })
            default: result[tag] = .numbers((0..<items).map { Double(bytes[at + $0]) })
            }
        }
        return result
    }

    private mutating func parse() {
        guard bytes.count >= 8 else { return }
        little = bytes[0] == 0x49
        let ifd0 = entries(at: u32(4))
        func text(_ v: Value?) -> String? { if case .text(let s)? = v { return s } else { return nil } }
        func number(_ v: Value?) -> NSNumber? { if case .numbers(let n)? = v, let first = n.first { return NSNumber(value: first) } else { return nil } }
        func integer(_ v: Value?) -> NSNumber? { if case .numbers(let n)? = v, let first = n.first { return NSNumber(value: Int(first)) } else { return nil } }

        tiff[kCGImagePropertyTIFFMake] = text(ifd0[0x010F])
        tiff[kCGImagePropertyTIFFModel] = text(ifd0[0x0110])
        tiff[kCGImagePropertyTIFFOrientation] = integer(ifd0[0x0112])
        tiff[kCGImagePropertyTIFFSoftware] = text(ifd0[0x0131])
        tiff[kCGImagePropertyTIFFDateTime] = text(ifd0[0x0132])
        tiff[kCGImagePropertyTIFFXResolution] = number(ifd0[0x011A])
        tiff[kCGImagePropertyTIFFYResolution] = number(ifd0[0x011B])

        if case .numbers(let pointer)? = ifd0[0x8769], let offset = pointer.first {
            let sub = entries(at: Int(offset))
            exif[kCGImagePropertyExifDateTimeOriginal] = text(sub[0x9003])
            exif[kCGImagePropertyExifDateTimeDigitized] = text(sub[0x9004])
            exif[kCGImagePropertyExifOffsetTime] = text(sub[0x9010])
            exif[kCGImagePropertyExifOffsetTimeOriginal] = text(sub[0x9011])
            exif[kCGImagePropertyExifSubsecTimeOriginal] = text(sub[0x9291])
            exif[kCGImagePropertyExifExposureTime] = number(sub[0x829A])
            exif[kCGImagePropertyExifFNumber] = number(sub[0x829D])
            exif[kCGImagePropertyExifFocalLength] = number(sub[0x920A])
            exif[kCGImagePropertyExifPixelXDimension] = integer(sub[0xA002])
            exif[kCGImagePropertyExifPixelYDimension] = integer(sub[0xA003])
            exif[kCGImagePropertyExifLensModel] = text(sub[0xA434])
            if case .numbers(let iso)? = sub[0x8827] { exif[kCGImagePropertyExifISOSpeedRatings] = iso.map { NSNumber(value: Int($0)) } }
        }
        if case .numbers(let pointer)? = ifd0[0x8825], let offset = pointer.first {
            let sub = entries(at: Int(offset))
            func degrees(_ v: Value?) -> NSNumber? {
                guard case .numbers(let n)? = v, !n.isEmpty else { return nil }
                return NSNumber(value: n[0] + (n.count > 1 ? n[1] / 60 : 0) + (n.count > 2 ? n[2] / 3600 : 0))
            }
            gps[kCGImagePropertyGPSLatitudeRef] = text(sub[1])
            gps[kCGImagePropertyGPSLatitude] = degrees(sub[2])
            gps[kCGImagePropertyGPSLongitudeRef] = text(sub[3])
            gps[kCGImagePropertyGPSLongitude] = degrees(sub[4])
            gps[kCGImagePropertyGPSAltitudeRef] = integer(sub[5])
            gps[kCGImagePropertyGPSAltitude] = number(sub[6])
            gps[kCGImagePropertyGPSSpeed] = number(sub[13])
            gps[kCGImagePropertyGPSImgDirection] = number(sub[17])
            gps[kCGImagePropertyGPSDateStamp] = text(sub[29])
        }
    }
}
