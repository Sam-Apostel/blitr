# Architecture

This project renders SwiftUI source to PNG on Linux. Real SwiftUI is closed-source, so
`Sources/SwiftUI` is a reimplementation: a module **named `SwiftUI`** that unmodified app
code compiles against. Source compatibility with Apple's API is the contract: public names,
parameter labels and defaults must match Apple's so user code compiles unchanged.

## Pipeline

```
user .swift ──preprocess──▶ swiftc (against our SwiftUI module) ──▶ runner executable
                                                                        │
View value ──resolve──▶ Node tree ──measure/place──▶ frames ──draw──▶ Skia ──▶ PNG
```

1. **Resolve** (`Core/Resolve.swift`). `resolveView(view, ctx, into: &nodes)` walks the view
   value. Composite views get their dynamic properties installed, then `body` is resolved.
   Primitive views (`PrimitiveView`) append `Node`s directly. A view may produce zero, one or
   many nodes (`Group`, `ForEach`, `TupleView` are transparent).
2. **Layout** (`Layout/Node.swift`). SwiftUI's protocol: the parent calls
   `child.sizeThatFits(proposal)` (cached; override `measure`), then
   `child.place(at:size:ctx)`, which calls the child's `layout(size:ctx)` to place its own
   children. Frames are in the parent's coordinate space, in points.
3. **Draw** (`Graphics/Painter.swift`). `node.draw(painter)` translates to the node's frame
   and calls `drawContent`. `Painter` is the only code that talks to Skia.

`Render/Renderer.swift` drives this. It repeats resolve+layout while `onAppear`/`task`
actions change state (capped), then draws once. Preferences are computed from the live tree, so
values written during layout (inside a `GeometryReader`) reach `onPreferenceChange` on the next pass.

### Tasks, time and network

A frame is taken of a screen that has just appeared, so its `.task` work runs first, on the main run
loop, for at most `--task-timeout` real seconds (default 0.5); the state reached by then is drawn, with a
warning if a task is still busy. Two things keep that from depending on the machine:

- **`Task.sleep` runs on a virtual clock** (`BlitrFoundation/RenderClock.swift`). Its overloads
  (`for:`, `nanoseconds:`, `until:clock:`, `for:tolerance:clock:`) shadow the standard library's in every
  module compiled against the SDK. When every running task is asleep, the clock jumps to the earliest
  wake-up, as long as that is within `--settle-time` (default 2 s); a sleep that ends later stays asleep
  past the frame, like a timer on a device when the screenshot is taken, and is not reported. So a
  "show the result after 1.5 s" delay is drawn done, a slideshow advancing every 5 s shows its first slide,
  and neither costs real time. An interaction `wait` step moves the settle time on. `ContinuousClock` and `SuspendingClock` sleeps are virtual too; one called
  on a clock directly with a `tolerance:` is real time. Outside a render (widget timelines) `Task.sleep` is real time.
- **Renders are offline** (`_RenderNetwork`). HTTP(S) requests fail at once with
  `URLError(.notConnectedToInternet)` (`URLSession.shared` through a registered `URLProtocol`; other
  sessions through a proxy that refuses connections on Linux, and on macOS through the same protocol, put
  into every `.default` and `.ephemeral` configuration), so a screen that loads from a server draws its
  offline or error state instead of waiting out the timeout. `--allow-network` turns this off. `--image-cache <dir>` (`_ImageCache`) keeps every image response a networked render receives and
  answers later offline renders from it, through a `URLProtocol` asked before the offline one (and put first in
  `.default` and `.ephemeral` configurations on macOS; on Linux, sessions with their own configuration bypass it). Remote
  With it, `AsyncImage` loads remote images while the frame settles; without it they stay in their loading phase. `file:` URLs always load.

## Source tree

| Path | Contents |
|---|---|
| `Sources/SwiftUI/Core` | `View`, `ViewBuilder`, modifiers, environment, state, traits and preferences, resolution |
| `Sources/SwiftUI/Layout` | `Node`, stacks, frames, padding, safe area, `GeometryReader` |
| `Sources/SwiftUI/Graphics` | `Painter` (Skia), colors, shape styles, paths, shapes |
| `Sources/SwiftUI/Text` | fonts, HarfBuzz shaping and line layout, `Text` |
| `Sources/SwiftUI/Views`, `Modifiers` | `Image`, `AsyncImage`, drawing effects, lifecycle |
| `Sources/SwiftUI/Controls` | buttons, toggles, pickers, text input, indicators |
| `Sources/SwiftUI/Containers` | `ScrollView`, lazy stacks, grids, `Layout` protocol, `Canvas` |
| `Sources/SwiftUI/Chrome` | navigation and tab bars, lists, sheets, alerts (hand-drawn system UI) |
| `Sources/SwiftUI/Symbols` | SF Symbol stand-ins (generated from Phosphor Icons by `scripts/generate-symbols.py`) |
| `Sources/SwiftUI/Compat` | `ObservableObject`-era wrappers, `App`/`Scene`, the representable placeholder |
| `Sources/SwiftUI/Glass` | iOS design language (`--ios 18/26/27`), `glassEffect` and glass painting |
| `Sources/SwiftUI/Accessibility` | accessibility tree, tap targets and issues (`--accessibility-*`) |
| `Sources/SwiftUI/Focus` | tvOS focus engine: focus records on nodes, movement, `@FocusState`, remote presses, focus map (docs/FOCUS.md); the tvOS focused look (`TVFocusLook.swift`) |
| `Sources/SwiftUI/Interaction` | scripted steps (`--steps`), element selectors, frame / filmstrip / animated outputs and their encoders (docs/INTERACTION.md) |
| `Sources/SwiftUI/Animation` | `Animation`, `Transaction`, transitions, springs and curves, and the tweener that interpolates two node trees during a capture |
| `Sources/SwiftUI/Controls/TV*`, `Chrome/TV` | tvOS control styles and chrome: buttons, toggles, pickers, fields, tab bar, sidebar, lists, navigation, alerts (docs/TVOS.md) |
| `Sources/SwiftUI/Widgets` | widget and Live Activity canvases, the engine side of WidgetKit (docs/WIDGETS.md) |
| `Sources/SwiftUI/Render` | `Renderer`, runner entry point, device profiles and chrome, image comparison for `compare` |
| `Sources/SwiftUI/Inert` | APIs with no effect on a static frame: gestures, animation; accessibility modifiers record into the tree |
| `Sources/UIKit`, `MapKit`, `CoreLocation`, `WidgetKit`, `ActivityKit`, `AppIntents` | shim framework modules (see "Shim modules"; docs/MAPS.md, docs/WIDGETS.md) |
| `Sources/Combine`, `BlitrFoundation` | Combine; Foundation API missing on Linux (localization, formatters, ...) |
| `Sources/CoreGraphics`, `ImageIO`, `CoreImage`, `CoreText`, `UniformTypeIdentifiers` and the other framework modules | Apple frameworks beyond SwiftUI (docs/FRAMEWORKS.md); CoreGraphics and UniformTypeIdentifiers sit below SwiftUI |
| `Sources/blitr` | the command-line tool and source preprocessor |
| `Tests/Corpus` | realistic screens rendered in CI as acceptance tests |

## Adding things

**A primitive view** conforms to `View` and `PrimitiveView`, with `typealias Body = Never`:

```swift
public struct Divider: View, PrimitiveView {
    public typealias Body = Never
    public init() {}
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        out.append(DividerNode(...))            // read styling from ctx.env here
    }
}
```

Prefer a **composite view** (a normal `body`) whenever the view can be expressed with
existing views. Most controls should be composites.

**A modifier** is a struct conforming to `ViewModifier` plus one internal protocol:

| It needs to…                         | Conform to / use                                   |
|--------------------------------------|----------------------------------------------------|
| only change the environment          | `self.env { $0.key = value }`                      |
| wrap the view in a layout/draw node  | `NodeModifier` (`makeNode(child:ctx)`)             |
| draw the child through an effect     | `self.effect { painter, size, draw in ... }`       |
| attach data for the parent container | `self.trait(Key.self, value)` (`TraitKey`)         |
| send data up the tree                | `preference(key:value:)` (`PreferenceKey`)         |
| anything else                        | `PrimitiveModifier` (`resolve(content:ctx:into:)`) |

A modifier applied to multi-view content applies to each view separately (as in SwiftUI);
`NodeModifier` does this for you.

**A layout node** subclasses `Node` (or `WrapperNode` for one child) and overrides
`measure`, `layout`, and optionally `drawContent`, `spacing`, `explicitAlignment`.
Resolve styles (`style._paint(in: env)`, fonts) at resolve time and store the result in the
node; nodes do not see the environment later.

## Shim modules

Apple frameworks that app code imports next to SwiftUI (`UIKit`, `MapKit`, `CoreLocation`, `WidgetKit`,
`ActivityKit`, `AppIntents`) are each a Swift module of their own under `Sources/<Framework>`, so their
names are only visible where they are imported, as on Apple platforms: an app may declare its own
`Activity` or `Map` in a file that imports only SwiftUI (`Examples/NameCollisions.swift`).

Their code is linked into the engine library, **libBlitrEngine** (`.so`; `.dylib` on macOS), not
into libraries of their own: the `BlitrEngine` product in `Package.swift` lists them
(`shimModules`). SwiftPM links a target's dependencies into every dynamic product, so a `.dynamic` product
per shim would carry a second copy of SwiftUI, and with two copies in a process conformance lookups fail at
run time ("Text does not conform to View"). One library means every compile links
`-lBlitrEngine` only (`Installation.linkFlags`) and a runner maps exactly one SwiftUI. The
library's file name cannot be mistaken for Apple's SwiftUI framework; the module is still `SwiftUI`. The
SwiftUI module and `BlitrFoundation` (which does not use SwiftUI, and whose code is in the
engine library too) autolink it (`-module-link-name`); the modules inside the library are built with
`-disable-autolink-library` for it, so the library never links against itself.

To add a shim for framework `Foo`:

1. Create `Sources/Foo/Foo.swift` with the module's re-exports (`@_exported import Foundation`, and the
   frameworks Apple's `Foo` re-exports), and put the API in further files there. Each file imports what it
   uses (`import SwiftUI`, `import UIKit`, ...); imports are per file.
2. Add `.target(name: "Foo", dependencies: ["SwiftUI", ...], swiftSettings: moduleSettings)` and add `"Foo"`
   to `shimModules` in `Package.swift`, and add `Foo` to the module list in `scripts/make-dist.sh`.
3. Keep in SwiftUI what Apple's SwiftUI declares, unless it needs the shim's types: SwiftUI cannot import
   the shim (the shim imports SwiftUI), so API like `Image(uiImage:)` lives in the shim, next to the
   type it takes. Where the engine has to draw for the shim, the shim builds on public views or on an
   underscored public hook in SwiftUI (`_WidgetCanvas`, `_RepresentablePlaceholder`).
4. Engine internals the shim needs are `package` (visible to the modules of this package, never to app
   code): mark the declaration `package`, or add an initializer to `Core/ShimSupport.swift` when a
   shim extends a SwiftUI struct (a resilient struct cannot be initialised from another module).
5. If Apple ships `Foo` only on some platforms, list them in `Preprocessor.frameworkPlatforms` so
   `#if canImport(Foo)` follows the rendered platform.

## macOS

The tool and engine build and run natively on macOS (issue #19). What differs from Linux:

- **Host differences live in one place.** In the tool, `HostPlatform` (`Sources/blitr/HostPlatform.swift`)
  has the library extension (`.so` / `.dylib`), how a compiled module library names itself (SONAME /
  `@rpath` install name), the deployment target and SDK passed to every compile on macOS, the host's `os(...)`
  spelling for the preprocessor (`Preprocessor.hostOS`), and how the tool finds its own executable. In
  `Package.swift`, `#if os(macOS)` picks `@loader_path` over `$ORIGIN` and leaves out `appleProvided`;
  `scripts/bootstrap.sh` and `scripts/make-dist.sh` branch on `uname -s`.
- **Apple's modules where Foundation forces them.** Apple's Foundation imports Combine, ObjectiveC and Security,
  and a module of ours with one of those names would be loaded in its place, so on macOS they are Apple's and
  our targets are left out (`appleProvided` in `Package.swift`). So are os and OSLog, whose C API Darwin already
  declares. The engine observes `ObservableObject`s per object there (`CompatStore.observe`), since Apple's
  Combine has no global change hook. Every other shim keeps its Apple name and shadows the SDK's framework,
  because `-I` paths are searched before the SDK.
- **CoreGraphics stays ours.** Foundation on this SDK does not import Apple's CoreGraphics; the geometry structs
  come from CoreFoundation's C headers, and `DarwinGeometry.swift` adds their Swift API. CF types are
  CoreFoundation's own, so code bridges through `NSArray` / `NSDictionary` and `_cfString`.
- **Localization.** `String.LocalizationValue` and `LocalizedStringResource` are Apple's (two nested types of the
  same name are ambiguous, not shadowed). `DarwinLocalizationOverloads.swift`, generated by
  `scripts/generate-darwin-localization.py`, declares `String(localized:)` and `AttributedString(localized:)` once
  per combination of optional arguments; overload resolution prefers those to Apple's defaulted ones, so strings
  resolve through the tool's table as on Linux. Apple's `LocalizationValue` gives its key and arguments
  through its `Codable` form.
- **A filtered SDK.** User code is compiled with `-sdk` pointing at a tree of links into the real SDK that keeps
  only the frameworks Foundation is built from, plus os, OSLog and Observation (`FilteredSDK`). Any other
  framework is "no such module" and fails `canImport`, as on Linux, and Apple's SwiftUI, UIKit or AppKit can
  never be imported or linked. Apple's prebuilt modules still apply, so compiles are as fast as with the full SDK.
- **Linux-only code is gated** with `#if !canImport(Darwin)`: the Foundation gap-fillers (`FoundationGaps.swift`,
  `MeasurementFormatter.swift`, `PresentationIntents.swift`, `FileWrapper`, `UndoManager`) and the Objective-C
  autorelease stubs (`Compat/ObjCRuntimeStubs.swift`).
- **Fonts.** Unless `--open-fonts` is given, the tool passes `/System/Library/Fonts` as the Apple font
  directory when no downloaded copy exists (`Installation.locate`); `FontLibrary` knows the system file names
  (`SFNS.ttf`, `SFNSRounded.ttf`, `SFNSMono.ttf`, `NewYork.ttf`, `Apple Color Emoji.ttc`).
- **At run time** libSkiaSharp links Cocoa, so AppKit and with it Apple's SwiftUICore are mapped into every
  runner, next to our SwiftUI module. Their types carry the same mangled `SwiftUI` names as ours. Nothing in a
  render looks SwiftUI types up by name (the `shake` step finds one UIKit type of ours, `_UIKitDeviceEvents`, by
  its mangled name), and the full regression set renders the same as on Linux, but code that calls
  `_typeByName` or `NSClassFromString` on a SwiftUI name could find Apple's.

## Conventions

- **Environment** flows down (`ResolveContext.env`). **Traits** are read by the direct
  container (`node.traits[Key.self]`). **Preferences** flow up (`node.preferences`) and are
  merged in document order when a node is created with children.
- **State** (`@State`, `@StateObject`) lives in `Runtime.stateStore`, keyed by structural
  identity (`ResolveContext.path`). When resolving children under distinct sub-identities use
  `ctx.child(key)`.
- **Safe area**: `PlaceContext.safeRect` is where content is laid out; `container` is how
  far content may bleed when it ignores the safe area. Bars (navigation, tab) shrink
  `safeRect` for their content and keep `container`.
- **Colors**: use `SystemColor` (light/dark pairs with iOS values); never hard-code a single
  appearance. Resolve with `env.colorScheme`.
- **Unsupported input** must not render silently wrong: call `Runtime.current?.warn(...)`
  (shown to the user once) or leave the API out so compilation fails clearly.
- **Inert APIs**: animation, gestures and similar have no visual effect in a static frame. They exist for
  source compatibility and return `self`. Accessibility modifiers never change the picture either, but they
  record into `AccessibilityInfo` for the accessibility outputs.
- **Design language**: system chrome branches on `env.platformVersion` / `DesignLanguage` (flat, glass 26, glass 27),
  and on `env.renderPlatform` for tvOS (`TVMetrics`, iOS code paths untouched).
- The module is built with library evolution so `CSkia`/`CHarfBuzz` stay private
  (`internal import`). Do not expose their types in public API.
- Text is LTR only. `View` is `@MainActor`; engine types are `@MainActor` too.

## Checking your work

```
scripts/bootstrap.sh            # once: fetches Skia + fonts into Vendor/
swift build
"$(swift build --show-bin-path)/blitr" render File.swift -o out/file.png [--layout fit] [--scheme dark] [--width 393]
```

Look at the PNG. Compare against what the same code produces on iOS: spacing, sizes, and
colors are the things most worth getting right.
