# API coverage of the SwiftUI module

Measured against real-world SwiftUI code: how much of the API that apps actually call does `Sources/SwiftUI` already declare? Reproduce with `scripts/api-coverage/` (see its README). Counts are call sites, not distinct APIs.

## Headline

- **100.0% of SwiftUI call sites in the public corpus are covered** (62,734 covered, 1 not covered; 9 repositories).
- "SwiftUI call sites" are modifier calls, view/type initialisers, static and implicit members (`.buttonStyle(.borderedProminent)`), property wrappers, macros, environment key paths and type/conformance uses that resolve to SwiftUI or to modules `import SwiftUI` re-exports (Observation, Combine). Sites that resolve to the app's own code, the standard library/Foundation, other Apple frameworks or third-party packages are excluded from both numerator and denominator and listed in the framework table.
- **Upper bound.** A call counts as covered when the name exists and its argument labels fit an overload (defaults taken from the emitted `SwiftUI.swiftinterface`); argument *types* are not checked, so real coverage is slightly lower. A spot-check of 74 hand-written realistic snippets compiled for 72 of them.
- The private corpus (an iOS/tvOS/watchOS app) was not part of this run; at the first measurement it was 99.4% covered (504 sites not covered), most of them in gaps closed since (below).

Coverage by platform of the file the call site is in (shared = no platform signal in the path):

| platform | covered | not covered | share |
|---|---:|---:|---:|
| ios | 4,715 | 0 | 100.0% |
| tvos | 1,505 | 0 | 100.0% |
| watchos | 288 | 1 | 99.7% |
| macos | 5,035 | 0 | 100.0% |
| shared | 51,191 | 0 | 100.0% |

## Closed since the first measurement

Rows of the first ranked list that now compile, each with an example under `Examples/ApiGaps/` (CI renders them):
~~`@Observable`, `@ObservationIgnored`~~ (Observation re-exported), ~~`.containerBackground(_:for:)`~~ (`.widget` in WidgetKit; `.tabView` drawn behind paging tab views),
~~`.onMoveCommand`, `.onExitCommand`, `.onPlayPauseCommand`~~, ~~`.popoverTip(_:)`~~ (TipKit), ~~`Text(timerInterval:countsDown:)`~~,
~~`ProgressView(timerInterval:countsDown:)`~~, ~~`tabViewStyle(.verticalPage)`~~, ~~Xcode preview modifiers~~ (and `PreviewProvider`),
~~`Table`/`TableColumn`/`TableRow`~~, ~~`.groupBoxStyle(_:)`~~, ~~`@Entry`~~, ~~`.labeledContentStyle(_:)`~~, ~~`.menuIndicator(_:)`~~,
~~`.menuOrder(_:)`~~, ~~`.move(fromOffsets:toOffset:)`~~, ~~`TabSection`~~, ~~`toggleStyle(.checkbox)`~~,
~~`CommandGroup(replacing: .appSettings)`~~, ~~`ContextMenu`~~, ~~`ImageRenderer`~~, ~~`Menu(_:content:primaryAction:)`~~,
~~`MenuBarExtra`~~, ~~`.itemProvider(_:)`~~, ~~`pickerStyle(.radioGroup)`~~, ~~`accessibilityLabel(_:isEnabled:)`~~,
~~`symbolEffect(.bounce)`~~ (indefinite), ~~`ScrollPosition(y:)`~~. The `os` framework (93 sites) is now a module of its own.
The measurement scripts were fixed for the shim modules: snippets import WidgetKit, ActivityKit and AppIntents, the
`@Entry`/`@Observable` snippets use the attributes where they apply, and a realistic manual snippet named after an API settles it.

## Confirmed gaps, ranked

Every row was confirmed by compiling a snippet with `swiftui-screenshot` (or is a label/signature mismatch found by the interface comparison and spot-checked). Classes: **a** visual (changes pixels in a static frame, needs a real implementation), **b** inert (no effect on a static frame; a no-op shim is enough), **c** platform-specific (tvOS/watchOS/macOS only; the class it would otherwise be is in brackets), **d** other framework (see the second table). Order: APIs used by the private corpus first, then by call sites.

| # | API | public repos | public sites | private corpus sites | class | what it does visually |
|---:|---|---:|---:|---:|:---:|---|
| 1 | `Xcode preview modifiers (.previewLayout/.previewDevice/.previewDisplayName/.previewContext)` | 1 | 1 | 0 | b | preview-only metadata; layout and device are covered by the tool's --layout/--device flags |

## Other frameworks

Uses that resolve to another framework (class d), per framework: call sites, files and public repos. This table says which shim would unblock the most files. UIKit and Combine have partial shims in this repository already; their rows count only what is missing from them.

| framework | call sites | files | public repos | most-used APIs |
|---|---:|---:|---:|---|
| UIKit | 415 | 163 | 5 | `UIDevice.feedback` 44, `UIDevice.impact` 20, `UIDevice.PlaybackCapabilities` 20 |
| AppKit | 267 | 106 | 6 | `NSWorkspace.shared` 30, `NSPasteboard.general` 21, `type NSImage` 12 |
| system C APIs | 170 | 12 | 4 | `GLenum(...)` 88, `GLint(...)` 22, `type GLint` 17 |
| SwiftData | 98 | 57 | 3 | `@Query` 33, `@Model` 23, `@Attribute` 9 |
| os | 93 | 11 | 4 | `Logger.appState` 33, `Logger.helperClient` 26, `Logger.authorization` 12 |
| CoreGraphics | 83 | 12 | 5 | `CGLPixelFormatAttribute(...)` 7, `CGColor(...)` 6, `CGLSetCurrentContext(...)` 5 |
| AVFoundation | 79 | 19 | 5 | `AVAudioSession.sharedInstance` 18, `AVAudioSession.interruptionNotification` 5, `type AVAudioSession` 4 |
| AppIntents | 76 | 17 | 4 | `@Parameter` 40, `type ParameterSummary` 12, `type ReturnsValue` 7 |
| WidgetKit | 66 | 23 | 4 | `StaticConfiguration(...)` 17, `Timeline(...)` 15, `conformance: Widget` 10 |
| CloudKit | 50 | 6 | 1 | `type CKRecord` 15, `type CKSyncEngine` 10, `CKSyncEngine.PendingRecordZoneChange.saveRecord` 8 |
| CoreLocation | 47 | 12 | 4 | `CLLocation(...)` 17, `CLLocationManager(...)` 5, `type CLLocationCoordinate2D` 5 |
| CoreMotion | 46 | 8 | 4 | `CMTime(...)` 8, `type CMVideoFormatDescription` 4, `type CMTime` 4 |
| Charts | 45 | 7 | 2 | `AxisMarks(...)` 7, `Chart(...)` 6, `AxisValueLabel(...)` 6 |
| UIKit/AppKit colors | 39 | 20 | 3 | `Color(_:) .windowBackgroundColor` 16, `Color(_:) .controlBackgroundColor` 9, `Color(_:) .textBackgroundColor` 5 |
| MediaPlayer | 34 | 11 | 2 | `MPRemoteCommandCenter.shared` 5, `MPNowPlayingInfoCenter.default` 5, `MPV_RENDER_UPDATE_FRAME.rawValue` 5 |
| CoreFoundation | 31 | 10 | 4 | `type CFTimeInterval` 4, `type CFString` 4, `CFRunLoopGetMain(...)` 3 |
| StoreKit | 27 | 15 | 3 | `type Product` 9, `.manageSubscriptionsSheet(isPresented:)` 2, `Product.SubscriptionInfo.status` 1 |
| Security | 27 | 9 | 3 | `SecItemDelete(...)` 6, `SecCSFlags(...)` 5, `SecRandomCopyBytes(...)` 2 |
| UniformTypeIdentifiers | 22 | 12 | 4 | `type UTType` 4, `UTType.propertyList` 3, `UTType.png` 3 |
| QuartzCore | 22 | 13 | 3 | `CAMediaTimingFunction(...)` 6, `type CALayer` 3, `type CADisplayLink` 3 |
| UserNotifications | 20 | 6 | 4 | `UNUserNotificationCenter.current` 14, `type UNMutableNotificationContent` 2, `UNNotificationSound(...)` 1 |
| MapKit | 16 | 7 | 4 | `type Marker` 3, `MKCoordinateSpan(...)` 2, `MKCoordinateRegion(...)` 2 |
| Photos | 15 | 2 | 1 | `type PHAsset` 5, `PHPhotoLibrary.authorizationStatus` 4, `PHPhotoLibrary.requestAuthorization` 2 |
| Network | 14 | 4 | 2 | `type NWConnection` 4, `type NWBrowser` 2, `type NWListener` 2 |
| CoreTransferable | 12 | 3 | 2 | `type TransferRepresentation` 5, `FileRepresentation(...)` 5, `DataRepresentation(...)` 1 |
| EventKit | 11 | 5 | 1 | `type EKEvent` 3, `EKCalendar(...)` 2, `EKEventStore(...)` 2 |
| Foundation | 10 | 5 | 4 | `type natural_t` 4, `LocalizedStringResource(...)` 3, `ListFormatter.localizedString` 1 |
| CryptoKit | 6 | 3 | 2 | `type SHA256` 2, `SHA256.hash` 2, `AES.GCM.SealedBox` 1 |
| PhotosUI | 6 | 5 | 2 | `type PhotosPickerItem` 3, `.photosPicker(isPresented:selection:maxSelectionCount:matching:photoLibrary:)` 2, `.photosPicker(isPresented:selection:matching:)` 1 |
| AuthenticationServices | 5 | 1 | 1 | `ASAuthorizationPlatformPublicKeyCredentialProvider(...)` 2, `type ASAuthorizationControllerPresentationContextProviding` 1, `type ASAuthorizationRequest` 1 |
| *third-party packages (28 modules, auto-attributed by imports)* | 982 | 401 | |  JellyfinAPI 423,  Defaults 108,  Models 51,  XcodesKit 49,  XcodesCleanupKit 45,  NukeUI 41 |

## Signature findings

Hand-written snippets that use real Apple signatures and fail to compile here (failures caused by my own snippets were removed; several rows duplicate gaps in the table above):

- `Chart`: cannot find 'Chart' in scope
- `Map`: cannot find 'Map' in scope

## Not measured

- Argument types, generic constraints and result-builder content are not compared; only names, labels and defaults.
- Behaviour: an API that compiles can still render wrongly or not at all; this is a declaration-level measurement.
- Implicit members are checked against the parameter types the interface lists; unusual cases fall back to "exists on some type".
- Names that resolve to neither our module, the standard library/Foundation, the app, nor a known framework (generic parameters, local packages, asset-catalog symbols) are left out: 2,416 sites.
- `#if os(...)` branches are evaluated per platform config and merged by maximum count per site, so a call duplicated across platform branches counts once.

## Corpus

| name | repository | commit | platforms | Swift files | lines |
|---|---|---|---|---:|---:|
| foodtruck | apple/sample-food-truck | `3954a769e9` | ios,macos | 81 | 8,545 |
| icecubes | Dimillian/IceCubesApp | `98098b9c4b` | ios,macos | 395 | 41,549 |
| swiftfin | jellyfin/Swiftfin | `e1f78c656c` | ios,tvos | 891 | 109,686 |
| yattee | yattee/yattee | `10ea2798ee` | ios,tvos,macos | 540 | 176,988 |
| clendar | vinhnx/Clendar | `883c2ddbf5` | ios,watchos | 129 | 9,353 |
| xcodesapp | XcodesOrg/XcodesApp | `9836fd8392` | macos | 115 | 12,532 |
| controlroom | twostraws/ControlRoom | `1764564f79` | macos | 81 | 8,555 |
| swiftuianim | amosgyamfi/open-swiftui-animations | `abc1d4ce7a` | ios | 75 | 7,613 |
| backyardbirds | apple/sample-backyard-birds | `1843d5655b` | ios,macos | 111 | 6,976 |

