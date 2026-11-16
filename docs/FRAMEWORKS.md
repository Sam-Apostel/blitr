# Apple frameworks beyond SwiftUI

App code imports more than SwiftUI. Each framework below is a module of its own under `Sources/<Name>`
(see "Shim modules" in ARCHITECTURE.md), linked into libSwiftUIScreenshotEngine. Source compatibility with Apple's public
signatures is the contract; behaviour is what a screenshot needs: what affects pixels is real, the rest
answers like a fresh install with no permissions granted (not determined, empty, nil) and never blocks.
Anything that would be visible but cannot be drawn shows a placeholder and one warning naming it.

## Layering

```
CoreGraphics ── ImageIO ── CoreImage          (no SwiftUI; Skia inside)
     │    └──── CoreText
UniformTypeIdentifiers, ObjectiveC, Security, CryptoKit, Network, ...   (Foundation only)
     │
SwiftUI  (depends on CoreGraphics and UniformTypeIdentifiers and re-exports them, as Apple's does)
     │
UIKit (re-exports QuartzCore, ObjectiveC, Security), AppKit, PhotosUI, PassKit, AuthenticationServices, ...
```

**CoreGraphics sits below SwiftUI.** Apple's SwiftUI makes CGImage, CGContext and the CF names visible, and
takes them (`Image(decorative:scale:)`, `ImageRenderer.cgImage`, `Color(cgColor:)`, `Path(_: CGPath)`), so
SwiftUI depends on CoreGraphics and re-exports it. CGVector, CGAffineTransform and CGLineCap/Join moved there
from SwiftUI. CoreGraphics reaches the engine only through `package` hooks: `ShimDiagnostics` (warnings,
installed by SwiftUI's runtime) and `FontRegistry` (font files registered through CoreText, read by
SwiftUI's font library). On Linux, CF types are the Foundation classes they are toll-free bridged to on Apple
platforms (`CFData` = `NSData`, `CFString` = `NSString`, `CFDictionary` = `NSDictionary`, ...), so the
usual `as CFData` / `as? [CFString: Any]` casts work; on macOS they are CoreFoundation's own.

**On macOS** Combine, ObjectiveC, Security, os and OSLog are Apple's frameworks, not these modules: Apple's
Foundation imports the first three, and Darwin already declares what our `os` provides. CGPoint, CGSize, CGRect,
CGVector and CGAffineTransform are CoreFoundation's C structs there, and our CoreGraphics adds the Swift API
Apple's Core Graphics overlay would (`DarwinGeometry.swift`).

**`#if canImport`** follows the rendered platform (`Preprocessor.frameworkPlatforms`): every module exists in
the SDK, and `canImport` of one Apple does not ship for the rendered platform is rewritten to `false`
(UIKit off on macOS, AppKit only on macOS, WatchConnectivity on iOS and watchOS, ...). Submodule imports
(`import CoreImage.CIFilterBuiltins`) are rewritten to the module, and `@objc`, `@IBAction` and friends are
dropped and `#selector(x)` becomes `Selector("x")` (there is no Objective-C runtime on Linux). For the same reason an `override`
declared in an extension (`extension UIWindow { override func motionEnded(...) }`, legal on Apple platforms only for
`@objc dynamic` members) is left out, with a warning naming it: such hooks never show in a still frame. DateFormatter's symbol
properties (`monthSymbols`, `amSymbol`, ...) are `[String]!` / `String!` on Apple and non-optional on Linux, so `?.`, `?[`
and `!` right after them are removed.

## What each framework does

| Framework | Real | Inert (fresh install) | Drawn |
|---|---|---|---|
| CoreGraphics | CGImage from data providers (8/16/32-bit, gray/RGB/CMYK, any alpha and byte order), crop; CGContext bitmap contexts (fill/stroke paths, rects, ellipses, arcs, dashes, linear/radial gradients, transforms, clipping, shadows, blend modes, alpha, images, transparency layers, `makeImage`); CGPath/CGMutablePath (bridged to `Path`); CGColor, CGColorSpace conversions; CGGradient | text drawing (use `NSString.draw`), mask clipping (clips to the rect, warns) | everything above |
| ImageIO | CGImageSource decode (PNG, JPEG, WebP, GIF, BMP), thumbnails with max size and transform, properties with EXIF/TIFF/GPS from JPEG; CGImageDestination encode PNG/JPEG/WebP with quality | HEIC/AVIF decode and encode (nil, warns), metadata writing | |
| CoreImage | CIImage (pixels/color, transform, crop, orient, composite), CIContext.createCGImage/render/PNG/JPEG; filters: QR Code (byte mode, L/M/Q/H, v1-40, masks), Code 128 (sets A/B/C), constant color, Gaussian/box/disc blur, color controls, sepia, invert, monochrome, photo effects, exposure, hue, false color, color matrix, affine, Lanczos scale, crop, source-over, area average | Aztec and PDF417 give nil (warn); other filter names pass the input through (warn); HEIF output | the images |
| CoreText | font registration by URL/URLs/CGFont (then `Font.custom`, `UIFont(name:)` find the font by PostScript, family or file name); CTFont metrics from the file | | |
| UIKit | UIImage (data/file decode, `cgImage`, size/scale/orientation, PNG/JPEG encode, thumbnails, tint, symbols to bitmaps, `draw(in:)`); UIGraphicsImageRenderer and UIGraphicsBeginImageContext; UIColor (dynamic provider, HSB, `cgColor`, every system color); UIFont/UIFontDescriptor/UIFontMetrics with real metrics; NSString/NSAttributedString measuring and drawing; the `AttributeScopes.UIKitAttributes` scope (its lookup is disfavored, so `a.foregroundColor = .red` picks SwiftUI's attribute); UIBezierPath; UITraitCollection from the render; UIScreen/UIDevice; pasteboard (in memory); UITextView text storage | UIApplication (one scene, opens nothing), haptics, accessibility settings at defaults, Auto Layout (recorded, not solved), gestures, view controllers and presentations (recorded), appearance proxies (accepted, one warning), UIGraphicsPDFRenderer (blank pages) | representables: UIImageView, UILabel, UIActivityIndicatorView, UIVisualEffectView, plain UIViews (background, corner radius, border, alpha), UIHostingController; containers (UIView, UIScrollView or an app subclass that does not draw) show the SwiftUI they host through a hosting controller's view, and draw nothing when empty (window probes, gesture helpers); views that draw themselves (`draw(_:)` with a bitmap CGContext current; CALayer, CAShapeLayer and axial/radial CAGradientLayer sublayers) and trees of UIView, UIStackView, UILabel, UIImageView and UIButton are laid out at their SwiftUI size (frames from `layoutSubviews`, autoresizing masks, simple Auto Layout: equalities and edge-bounding inequalities between siblings, the superview and its guides; not a full solver) and drawn; sized by `sizeThatFits(_:uiView:context:)`, else intrinsicContentSize with hugging and compression priorities; any other UIKit view (controls, tables, maps), a mask, a conic gradient or Auto Layout it cannot solve is a placeholder naming it. UIButton metrics (default title font, legacy button insets) are not calibrated |
| AppKit (macOS) | NSColor with appearance-dependent colors, NSImage (decode), NSFont, NSAppearance | NSPasteboard (in memory), NSWorkspace, NSApplication | NSViewRepresentable: placeholder |
| QuartzCore | CACurrentMediaTime, CATransform3D math | CALayer family stores properties; CADisplayLink never fires (one frame) | via the owning view |
| ObjectiveC | associated objects (side table), Selector values | swizzling functions do nothing; nothing responds to selectors | |
| UniformTypeIdentifiers | UTType with ~95 system types, extensions, MIME types, conformance, exported/imported types | | |
| CryptoKit | SHA-256/384/512, SHA-1, MD5, HMAC, SymmetricKey | AES-GCM, ChaChaPoly, Curve25519 throw | |
| Security | keychain items in memory (add/copy/update/delete with status codes), SecRandomCopyBytes | access control objects | |
| PhotosUI | | items load nil; picker sheets not shown (warn) | PhotosPicker as its label in a button |
| AuthenticationServices | | requests never complete; credential state not found | SignInWithAppleButton: black, white, white outline; sign in/continue/sign up |
| PassKit | | passes don't parse, empty library, Apple Pay unavailable | Add to Apple Wallet badge (SwiftUI and PKAddPassButton), Apple Pay buttons |
| PDFKit | page count and page sizes from the file | page content (blank, warns) | PDFView: placeholder |
| Vision / VisionKit | | requests finish with no results; masks throw; data scanner unsupported | |
| UserNotifications, EventKit(UI), Contacts(UI) | pending notification requests are kept | authorization not determined, requests answered no, no calendars/contacts, writes throw | controllers: placeholders |
| WatchConnectivity | | activates; not paired, not reachable; transfers stay outstanding | |
| Network | | path satisfied (Wi-Fi) | |
| CoreSpotlight | | indexing succeeds, stores nothing | |
| Translation, QuickLook | | not presented (warn when presented) | |
| StoreKit | | no products, review requests ignored | store views: neutral placeholder |
| TipKit | rules, events (donations), parameters (`@Parameter` is a property wrapper, `#Rule` is rewritten to `Tips.Rule`), invalidation, testing overrides; state lasts one render | tips do not display unless `Tips.showAllTipsForTesting()`/`showTipsForTesting(_:)` ran or the render has `--show-tips` | `TipView` and `popoverTip` draw the tip card (popover tips next to the view, kept on screen) |
| os, OSLog | `Logger`, `OSLogMessage` interpolation (privacy, integer/float/bool formats, alignment) formats lazily; `OSSignposter` ids; `os_unfair_lock` and `OSAllocatedUnfairLock` are real locks | log messages and signposts are dropped; `OSLogStore` is empty | |
| WatchKit (watchOS) | `WKInterfaceDevice` (screen is the canvas), `WKApplication`/`WKExtension` (active) | haptics, remote notifications, background refresh | |
| AVFoundation / AVKit | CMTime | players never play; capture not determined | VideoPlayer: black surface, play glyph, playback bar |
| SafariServices, MessageUI, CoreMotion, CoreHaptics | | no account / no hardware | controllers: placeholders |

Foundation gaps used by app code live in `SwiftUIScreenshotFoundation`: `URLCache(memoryCapacity:diskCapacity:directory:)`,
`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` (a temporary directory per group),
`RelativeDateTimeFormatter` and `ListFormatter` (English), `AttributedString(markdown:options:baseURL:)` (Linux Foundation
has no Markdown parser: inline markers become `inlinePresentationIntent` runs, links `link`, and with `.full` lines get a
`presentationIntent`; `InlinePresentationIntent` and `PresentationIntent` are declared here too, as Linux Foundation lacks them),
`URLSession.bytes(from:)`, `ProcessInfo.thermalState`, `NSUbiquitousKeyValueStore` (in memory).

## Checks

`Tests/Frameworks/run.sh` renders known-answer checks (hash vectors, HMAC, UTType conformance, keychain,
color conversions, formatters) and, with `pip install zxing-cpp pillow`, decodes the QR codes and Code 128
barcodes of `Examples/Frameworks/Barcodes.swift`. `Examples/Frameworks/` shows the drawn parts.

## Adding a framework

Add `Sources/Foo/Foo.swift` (re-export what Apple's Foo re-exports), then add the module to `Package.swift`
(a target and an entry in `shimModules`; `scripts/make-dist.sh` reads that list) and, if Apple ships it only on
some platforms, to `Preprocessor.frameworkPlatforms`.
