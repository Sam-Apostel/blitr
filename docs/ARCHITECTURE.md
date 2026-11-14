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
| `Sources/SwiftUI/Compat` | `ObservableObject`-era wrappers, `App`/`Scene`, UIKit types |
| `Sources/SwiftUI/Glass` | iOS design language (`--ios 18/26/27`), `glassEffect` and glass painting |
| `Sources/SwiftUI/Accessibility` | accessibility tree, tap targets and issues (`--accessibility-*`) |
| `Sources/SwiftUI/Focus` | tvOS focus engine: focus records on nodes, movement, `@FocusState`, remote presses, focus map (docs/FOCUS.md) |
| `Sources/SwiftUI/Render` | `Renderer`, runner entry point, device profiles and chrome, image comparison for `compare` |
| `Sources/SwiftUI/Inert` | APIs with no effect on a static frame: gestures, animation; accessibility modifiers record into the tree |
| `Sources/Combine`, `Sources/UIKit` | shim modules so those imports resolve |
| `Sources/swiftui-screenshot` | the command-line tool and source preprocessor |
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
- **Design language**: system chrome branches on `env.platformVersion` / `DesignLanguage` (flat, glass 26, glass 27).
- The module is built with library evolution so `CSkia`/`CHarfBuzz` stay private
  (`internal import`). Do not expose their types in public API.
- Text is LTR only. `View` is `@MainActor`; engine types are `@MainActor` too.

## Checking your work

```
scripts/bootstrap.sh            # once: fetches Skia + fonts into Vendor/
swift build
"$(swift build --show-bin-path)/swiftui-screenshot" render File.swift -o out/file.png [--layout fit] [--scheme dark] [--width 393]
```

Look at the PNG. Compare against what the same code produces on iOS: spacing, sizes, and
colors are the things most worth getting right.
