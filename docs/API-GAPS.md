# API coverage of the SwiftUI module

Measured against real-world SwiftUI code: how much of the API that apps actually call does `Sources/SwiftUI` already declare? Reproduce with `scripts/api-coverage/` (see its README). Counts are call sites, not distinct APIs.

## Headline

- **99.4% of SwiftUI call sites in the public corpus are covered** (62,760 covered, 408 not covered; 9 repositories).
- Including one private corpus (an iOS/tvOS/watchOS app, aggregated, not itemised): **99.4%** (84,817 covered, 504 not covered).
- "SwiftUI call sites" are modifier calls, view/type initialisers, static and implicit members (`.buttonStyle(.borderedProminent)`), property wrappers, macros, environment key paths and type/conformance uses that resolve to SwiftUI or to modules `import SwiftUI` re-exports (Observation, Combine). Sites that resolve to the app's own code, the standard library/Foundation, other Apple frameworks or third-party packages are excluded from both numerator and denominator and listed in the framework table.
- **Upper bound.** A call counts as covered when the name exists and its argument labels fit an overload (defaults taken from the emitted `SwiftUI.swiftinterface`); argument *types* are not checked, so real coverage is slightly lower. A spot-check of 71 hand-written realistic snippets compiled for 54 of them.

Coverage by platform of the file the call site is in (shared = no platform signal in the path):

| platform | covered | not covered | share |
|---|---:|---:|---:|
| ios | 21,500 | 36 | 99.8% |
| tvos | 3,970 | 13 | 99.7% |
| watchos | 657 | 22 | 96.8% |
| macos | 5,051 | 48 | 99.1% |
| shared | 53,639 | 385 | 99.3% |

## Confirmed gaps, ranked

Every row was confirmed by compiling a snippet with `swiftui-screenshot` (or is a label/signature mismatch found by the interface comparison and spot-checked). Classes: **a** visual (changes pixels in a static frame, needs a real implementation), **b** inert (no effect on a static frame; a no-op shim is enough), **c** platform-specific (tvOS/watchOS/macOS only; the class it would otherwise be is in brackets), **d** other framework (see the second table). Order: APIs used by the private corpus first, then by call sites.

| # | API | public repos | public sites | private corpus sites | class | what it does visually |
|---:|---|---:|---:|---:|:---:|---|
| 1 | `@Observable` [Observation] | 3 | 106 | 24 | b | macro: observation plumbing, no pixels; unknown attribute here, so every @Observable model fails to compile |
| 2 | `@ObservationIgnored` [Observation] | 3 | 116 | 13 | b | companion macro of @Observable |
| 3 | `.containerBackground(_:for:)` | 3 | 20 | 47 | a | paints the widget / tab-view / navigation container background; widgets and watchOS apps cannot render without it |
| 4 | `.onMoveCommand(_:)` | 2 | 6 | 2 | c (b, tvOS/macOS) | directional-pad / arrow-key move handler |
| 5 | `.onExitCommand(_:)` | 2 | 5 | 2 | c (b, tvOS/macOS) | Menu-button / Esc handler |
| 6 | `.popoverTip(_:)` [TipKit] | 0 | 0 | 3 | d | tip popover |
| 7 | `Text(timerInterval:countsDown:)` | 1 | 2 | 1 | a | live countdown/up timer text; a static frame shows the formatted interval |
| 8 | `.onPlayPauseCommand(_:)` | 1 | 1 | 1 | c (b, tvOS) | Play/Pause remote button handler |
| 9 | `DynamicIsland(...)` [ActivityKit] | 1 | 1 | 1 | d | Live Activity island layout |
| 10 | `ProgressView(timerInterval:countsDown:_:currentValueLabel:)` | 0 | 0 | 1 | a | timer-driven progress bar |
| 11 | `tabViewStyle(_:) .verticalPage` | 0 | 0 | 1 | c (a, watchOS) | full-screen vertical paging TabView on watch |
| 12 | `Xcode preview modifiers (.previewLayout/.previewDevice/.previewDisplayName/.previewContext)` | 4 | 52 | 0 | b | preview-only metadata; layout and device are covered by the tool's --layout/--device flags |
| 13 | `Table / TableColumn / TableRow` | 2 | 19 | 0 | a | multi-column table (macOS, iPadOS, iOS 17 collapses to first column); columns, headers, rows |
| 14 | `.groupBoxStyle(_:)` | 2 | 16 | 0 | a | changes the look of GroupBox (card, plain, custom GroupBoxStyle) |
| 15 | `@Entry` | 1 | 13 | 0 | b | macro that declares a custom EnvironmentValues key (values still reach the view) |
| 16 | `.labeledContentStyle(_:)` | 1 | 10 | 0 | a | custom LabeledContentStyle: layout of LabeledContent rows |
| 17 | `.menuIndicator(_:)` | 4 | 9 | 0 | a | shows/hides the chevron on Menu and Picker(.menu) labels |
| 18 | `.menuOrder(_:)` | 1 | 7 | 0 | b | order of items inside an opened menu |
| 19 | `.move(fromOffsets:toOffset:)` | 2 | 5 | 0 | b | collection helper used by onMove; no pixels |
| 20 | `TabSection(_:_:)` | 2 | 4 | 0 | a | groups tabs in the iPad/macOS sidebar-adaptable tab bar (iOS 18) |
| 21 | `toggleStyle(_:) .checkbox` | 2 | 3 | 0 | c (a, macOS) | checkbox-style Toggle |
| 22 | `CommandGroup(replacing:) .appSettings` | 2 | 2 | 0 | c (b, macOS) | menu-bar commands |
| 23 | `ContextMenu(...)` | 2 | 2 | 0 | b | legacy contextMenu(_:) payload; only visible when the menu is open |
| 24 | `ImageRenderer(...)` | 1 | 2 | 0 | a | renders a SwiftUI view to an image (share cards, exports); output is the view's own pixels |
| 25 | `Menu(_:_:primaryAction:)` | 1 | 2 | 0 | b | Menu with a primary tap action; only visible when opened |
| 26 | `MenuBarExtra(...)` | 2 | 2 | 0 | c (b, macOS) | menu bar scene; not part of a window frame |
| 27 | `.dynamicIsland(verticalPlacement:)` [ActivityKit] | 1 | 1 | 0 | d | Live Activity island layout |
| 28 | `.itemProvider(_:)` | 1 | 1 | 0 | b | drag source payload |
| 29 | `pickerStyle(_:) .radioGroup` | 1 | 1 | 0 | c (a, macOS) | radio-button Picker |

## Other frameworks

Uses that resolve to another framework (class d), per framework: call sites, files and public repos. This table says which shim would unblock the most files. UIKit and Combine have partial shims in this repository already; their rows count only what is missing from them.

| framework | call sites | files | public repos | most-used APIs |
|---|---:|---:|---:|---|
| AppKit | 294 | 120 | 6 | `NSWorkspace.shared` 30, `NSLayoutConstraint.activate` 25, `NSPasteboard.general` 21 |
| WidgetKit | 224 | 43 | 4 | `.widgetAccentable()` 45, `type WidgetConfiguration` 31, `Timeline(...)` 19 |
| UIKit | 210 | 74 | 4 | `type UIKit` 14, `UIView.animate(...)` 13, `UIKit.UIImage` 11 |
| AppIntents | 181 | 23 | 4 | `@Parameter` 49, `type IntentResult` 22, `DisplayRepresentation(...)` 17 |
| system C APIs | 170 | 12 | 4 | `GLenum(...)` 88, `GLint(...)` 22, `type GLint` 17 |
| MapKit | 155 | 26 | 4 | `MKCoordinateRegion(...)` 20, `type MKPolyline` 18, `MKCoordinateSpan(...)` 17 |
| CoreLocation | 111 | 34 | 4 | `type CLLocationCoordinate2D` 30, `CLLocation(...)` 23, `CLLocationCoordinate2D(...)` 20 |
| CoreGraphics | 109 | 15 | 5 | `type CGImage` 13, `CGLPixelFormatAttribute(...)` 7, `CGColor(...)` 6 |
| SwiftData | 98 | 57 | 3 | `@Query` 33, `@Model` 23, `@Attribute` 9 |
| os | 93 | 11 | 4 | `Logger.appState` 33, `Logger.helperClient` 26, `Logger.authorization` 12 |
| AVFoundation | 79 | 19 | 5 | `AVAudioSession.sharedInstance` 18, `AVAudioSession.interruptionNotification` 5, `type AVAudioSession` 4 |
| CloudKit | 50 | 6 | 1 | `type CKRecord` 15, `type CKSyncEngine` 10, `CKSyncEngine.PendingRecordZoneChange.saveRecord` 8 |
| Foundation | 49 | 21 | 5 | `type LocalizedStringResource` 39, `type natural_t` 4, `LocalizedStringResource(...)` 3 |
| QuartzCore | 48 | 13 | 3 | `CATransaction.begin` 9, `CATransaction.commit` 9, `CATransaction.setDisableActions` 8 |
| CoreMotion | 46 | 8 | 4 | `CMTime(...)` 8, `type CMVideoFormatDescription` 4, `type CMTime` 4 |
| Charts | 45 | 7 | 2 | `AxisMarks(...)` 7, `Chart(...)` 6, `AxisValueLabel(...)` 6 |
| UIKit/AppKit colors | 39 | 20 | 3 | `Color(_:) .windowBackgroundColor` 16, `Color(_:) .controlBackgroundColor` 9, `Color(_:) .textBackgroundColor` 5 |
| MediaPlayer | 34 | 11 | 2 | `MPRemoteCommandCenter.shared` 5, `MPNowPlayingInfoCenter.default` 5, `MPV_RENDER_UPDATE_FRAME.rawValue` 5 |
| CoreFoundation | 34 | 13 | 4 | `type CFTimeInterval` 5, `type CFString` 5, `CFRunLoopGetMain(...)` 3 |
| UserNotifications | 31 | 9 | 4 | `UNUserNotificationCenter.current` 21, `type UNMutableNotificationContent` 2, `type UNAuthorizationStatus` 2 |
| Security | 31 | 10 | 3 | `SecItemDelete(...)` 8, `SecCSFlags(...)` 5, `SecItemCopyMatching(...)` 3 |
| StoreKit | 27 | 15 | 3 | `type Product` 9, `.manageSubscriptionsSheet(isPresented:)` 2, `Product.SubscriptionInfo.status` 1 |
| EventKit | 20 | 7 | 1 | `type EKCalendar` 6, `type EKEvent` 5, `EKEvent(...)` 2 |
| UIKit/AppKit | 17 | 11 | 2 | `Color(uiColor:) .systemBackground` 5, `Color(uiColor:) .systemGroupedBackground` 3, `Color(uiColor:) .quaternarySystemFill` 2 |
| PhotosUI | 16 | 8 | 2 | `type PhotosPickerItem` 8, `.photosPicker(isPresented:selection:matching:)` 4, `.photosPicker(isPresented:selection:maxSelectionCount:matching:photoLibrary:)` 2 |
| Photos | 15 | 2 | 1 | `type PHAsset` 5, `PHPhotoLibrary.authorizationStatus` 4, `PHPhotoLibrary.requestAuthorization` 2 |
| Network | 14 | 4 | 2 | `type NWConnection` 4, `type NWBrowser` 2, `type NWListener` 2 |
| CoreTransferable | 12 | 3 | 2 | `type TransferRepresentation` 5, `FileRepresentation(...)` 5, `DataRepresentation(...)` 1 |
| CoreImage | 10 | 5 | 2 | `CIFilter.qrCodeGenerator` 2, `type CIColor` 1, `CIColor(...)` 1 |
| AuthenticationServices | 8 | 3 | 1 | `ASAuthorizationPlatformPublicKeyCredentialProvider(...)` 2, `type ASAuthorizationControllerPresentationContextProviding` 1, `type ASAuthorizationRequest` 1 |
| *third-party packages (28 modules, auto-attributed by imports)* | 993 | 410 | |  JellyfinAPI 432,  Defaults 108,  XcodesKit 76,  Models 51,  XcodesCleanupKit 45,  NukeUI 41 |

## Signature findings

Hand-written snippets that use real Apple signatures and fail to compile here (failures caused by my own snippets were removed; several rows duplicate gaps in the table above):

- `ProgressView(timerInterval:countsDown:)`: extra argument 'countsDown' in call
- `accessibilityLabel(_:isEnabled:)`: extra argument 'isEnabled' in call
- `containerBackground(for: .widget)`: value of type 'Text' has no member 'containerBackground'
- `symbolEffect(.bounce)`: no exact matches in call to instance method 'symbolEffect'
- `@Observable`: unknown attribute 'Observable'
- `Chart`: cannot find 'Chart' in scope
- `Map`: cannot find 'Map' in scope
- `onMoveCommand`: value of type 'Text' has no member 'onMoveCommand'
- `digitalCrownRotation`: value of type 'Text' has no member 'digitalCrownRotation'
- `buttonStyle(.card)`: reference to member 'card' cannot be resolved without a contextual type
- `tabViewStyle(.verticalPage)`: type 'TabViewStyle' has no member 'verticalPage'
- `Text(timerInterval:countsDown:) [countdown label]`: extra argument 'countsDown' in call
- `Menu(_:content:primaryAction:)`: extra argument 'primaryAction' in call
- `ImageRenderer`: cannot find 'ImageRenderer' in scope
- `Array.move(fromOffsets:toOffset:)`: value of type '[Int]' has no member 'move'
- `TabSection`: generic parameter 'Content' could not be inferred
- `ScrollPosition(y:)`: missing argument for parameter 'x' in call

## Not measured

- Argument types, generic constraints and result-builder content are not compared; only names, labels and defaults.
- Behaviour: an API that compiles can still render wrongly or not at all; this is a declaration-level measurement.
- Implicit members are checked against the parameter types the interface lists; unusual cases fall back to "exists on some type".
- Names that resolve to neither our module, the standard library/Foundation, the app, nor a known framework (generic parameters, local packages, asset-catalog symbols) are left out: 2,440 sites.
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

