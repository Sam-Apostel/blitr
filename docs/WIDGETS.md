# Widgets and Live Activities

A WidgetKit extension's source compiles unchanged (`import WidgetKit`, `ActivityKit`,
`AppIntents`) and its widgets render to PNG: Home Screen and Lock Screen widgets at the family's
size, and Live Activities as the Lock Screen banner and the three Dynamic Island presentations.

```
swiftui-screenshot list   Examples/Widgets/WeatherWidget.swift
swiftui-screenshot render Examples/Widgets/WeatherWidget.swift --all --out-dir out
swiftui-screenshot render Examples/Widgets/HabitWidget.swift --widget-rendering-mode accented
swiftui-screenshot render Examples/Widgets/LockScreenWidgets.swift --all --out-dir out   # no #Preview: one image per family
```

## What is rendered

| Source | Images |
|---|---|
| `#Preview("name", as: .systemSmall) { W() } timeline: { e1; e2 }` | one per timeline entry (`name entry 1`, `name entry 2`) |
| `#Preview(as: .systemMedium) { W() } timelineProvider: { Provider() }` | one per entry of the provider's timeline |
| `#Preview("name", as: .content \| .dynamicIsland(.compact \| .expanded \| .minimal), using: attributes) { W() } contentStates: { s1; s2 }` | one per content state |
| no preview, a `WidgetBundle` (else every `Widget`) | one per widget and supported family, from the provider's snapshot (`getSnapshot` / `snapshot(for:in:)`, context `isPreview == true`), else its `placeholder(in:)` |

Each image is one entry of `list`; as for other previews, `render` draws the first, `--preview <n|name>`
picks one and `--all` draws every one. A preview without a name is listed as `<Widget> <family>`.
Live Activities and controls in a bundle without previews are skipped (controls are never drawn).

While an entry is drawn, "now" is the entry's date: `Text(_:style:)`, `Text(timerInterval:)` and
`ProgressView(timerInterval:)` show the values the widget would show at that moment.

## Options

| Option | Effect |
|---|---|
| `--widget-family <family>` | Renders this family: overrides a preview's `as:` family, and selects it from the supported families of widgets without previews. Accepts `systemSmall`, `small`, `system-small`, ... |
| `--widget-rendering-mode fullColor\|accented\|vibrant` | Default: `fullColor`, and `vibrant` for accessory families. |
| `--device`, `--scale`, `--scheme`, `--ios`, `--dynamic-type` | As for app previews. The device picks the widget size; `--scheme` the appearance (Live Activity island content is always dark). |

## Canvas

- **Home Screen families**: the widget alone at its size, clipped to a 22pt continuous rounded
  rectangle, transparent outside it. The container background (`containerBackground(_:for: .widget)`)
  fills the shape; content gets the default 16pt margins unless the configuration says
  `contentMarginsDisabled()`. Without a container background a warning is printed (iOS 17 and later
  show "Please adopt containerBackground API") and the system background is drawn.
- **Accessory families** and the **vibrant** mode: drawn on a neutral backdrop (10pt around the
  widget) in the dark appearance; color is turned into white at the content's luminance.
- **Accented**: drawn twice: content outside `widgetAccentable()` in white (slightly tinted), the
  accentable groups in the accent tint, on a dark tinted backing (a removable container background is
  replaced; `containerBackgroundRemovable(false)` keeps it, desaturated and tinted).
- **Lock Screen Live Activity**: the banner (screen width minus 22pt, 84-160pt tall, 24pt corners)
  on a neutral backdrop the width of the screen. `activityBackgroundTint` fills it; otherwise a light
  or dark translucent fill.
- **Dynamic Island**: the black island at its position under the top of the screen, on a neutral
  backdrop. Expanded: leading and trailing regions beside the camera, center below it, bottom across;
  84-160pt tall. Compact: the pill with the leading and trailing regions. Minimal: the detached
  bubble to the right of the pill. `keylineTint` is drawn in the dark appearance.

### Sizes

From Apple's Human Interface Guidelines: [Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets)
(the table for iPhone screen sizes; the iPad "canvas" sizes) and
[Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
(compact, minimal, expanded and Lock Screen sizes for the 393 and 430pt iPhones). The tables are
in `Sources/SwiftUI/Widgets/WidgetHost.swift` and `LiveActivityHost.swift`.

Screens newer than the published table (402x874, 440x956, 420x912) use the nearest row; iPad
accessory sizes are not published (the 393pt iPhone values are used); `systemExtraLarge` exists on
iPad only.

### Estimates (verify on a device)

- Widget corner radius 22pt; rectangular accessory background radius 11pt.
- `ContainerRelativeShape` inside the content: widget radius minus the content margin.
- Accented tint (a light blue), the base-group whitening and the tinted backing.
- Vibrant: luminance to opacity with a 1.35 boost; `AccessoryWidgetBackground` as white at 22%.
- Neutral backdrop colors.
- Lock Screen banner: 24pt corners, default fills, no system margins.
- Island: expanded corner radius (display radius minus the island's top offset), expanded margins
  (14 top, 20 sides, 16 bottom), region placement, compact side width interpolated between the
  published 393 and 430pt values, 10pt compact margins, 6pt minimal margins.

## Implementation

- The API lives in the SwiftUI module (`Sources/SwiftUI/Widgets/Kits`): WidgetKit, ActivityKit and
  AppIntents are thin modules that re-export SwiftUI, like the UIKit shim. A separately linked
  library would carry its own copy of SwiftUI and its protocol conformances, and would not find
  `Text: View` at run time. Runners do not link the shim libraries (they contain no API of their
  own); only their `.swiftmodule` is needed for `import`.
- The engine side is in `Sources/SwiftUI/Widgets`: `_WidgetCanvas`, `_LiveActivityCanvas`, metrics,
  and the accented / vibrant color filters. `widgetAccentable` relies on `Painter.suppressesDrawing`.
- The preprocessor rewrites `#Preview(..., as: ...)` to `SwiftUI._WidgetPreview(...)` with the same
  arguments and trailing closures; main.swift then flattens preview groups into entries.

## Not implemented

- `accessoryCorner` (watchOS), `systemExtraLargePortrait` (visionOS), StandBy, CarPlay, watch Smart Stack.
- `widgetAccentedRenderingMode(_:)` (warns in the accented mode), `widgetLabel` (iOS does not show it).
- Controls (`ControlWidget`, `StaticControlConfiguration`, `ControlWidgetButton`, `ControlWidgetToggle`)
  compile but are not drawn.
- `IntentTimelineProvider` (SiriKit intents), `AppShortcutsProvider`, `ParameterSummary`, `DynamicOptionsProvider`.
- `Activity.request` throws, `Activity.activities` is empty; `pushType`, alert configurations are inert.
- Home Screen context (the widget on a wallpaper in the icon grid).
