# tvOS look

`--platform tvos` (implied by `--device apple-tv`) draws tvOS controls and system chrome. `--os 18` draws
the tvOS 18 look (opaque platters), `--os 26` / `--os 27` the Liquid Glass look (the same flag as `--ios`;
the version applies to the platform rendered). The code is in `Sources/SwiftUI/Focus/TVFocusLook.swift`
(metrics, colors, the lift), `Sources/SwiftUI/Controls/TV*.swift` and `Sources/SwiftUI/Chrome/TV/`.
`Examples/TVControls.swift` shows every area; `Tests/Corpus/13_TVHome.swift` and `14_TVSettings.swift` are
full screens.

## Research: what tvOS draws, and where the numbers come from

Every constant is in `TVMetrics` / `TVColors` and marked there as **measured** (the tvOS 26.5 simulator or a source below) or
**est.** (estimated from reference images or general knowledge; check against a simulator).

### Sources

- HIG, Focus and selection: tvOS uses a parallax/lift effect; "focusable items can have up to five
  different states" (unfocused, focused, highlighted, selected, unavailable), with reference images of a
  capsule button: translucent unfocused, white focused (much larger), dimmed unavailable.
  <https://developer.apple.com/design/human-interface-guidelines/focus-and-selection>
- HIG, Tab bars (tvOS): "By default, a tab bar is translucent, and only the selected tab is opaque. When
  people use the remote to focus on the tab bar, the selected tab includes a drop shadow ... The height of
  a tab bar is 68 points, and its top edge is 46 points from the top of the screen." **measured**
  <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- HIG, Layout (tvOS): inset content 60 pt top/bottom and 80 pt at the sides (already the device's safe area).
  <https://developer.apple.com/design/human-interface-guidelines/layout>
- HIG, Lists and tables (tvOS): "each row highlights and slightly increases in size when it becomes
  focused. A focused row's corners can also become rounded". (No sizes.)
- HIG, Typography: tvOS text styles (Title 1 76/96 ... Caption 2 23/30, Medium weight); already used by
  the font system.
- HIG, Materials (tvOS): "Liquid Glass appears throughout navigation elements ... Certain interface
  elements, like image views and buttons, adopt Liquid Glass when they gain focus." The tvOS 26 media
  player image there gives the button height: 44 px at 1280 px wide = **66 pt (measured)**; focused
  segment light (#D9DBE4), unfocused segments glass.
- HIG, Alerts: tvOS 26 alert image (light and dark): a 578 x 267 pt glass card (**measured** at 1.5x),
  leading-aligned bold title and message, two capsule buttons side by side, 72 pt high, 21 pt apart,
  28 pt from the card edges (**measured approx.**); the unfocused button is ~10% black over the light card
  and ~20% white over the dark card (**sampled**).
- HIG, Search fields (tvOS): a search screen is a keyboard screen (large prompt with magnifier, a row of
  letters, suggestion capsules) with results below. Only the field is drawn here.
- HIG, Segmented controls (tvOS): "Segments become selected when focus moves to them".
- SwiftUI documentation (developer.apple.com/documentation/swiftui, JSON pages):
  - `ToggleStyle.automatic`: "The default style for tvOS behaves like a button ... takes as much
    horizontal space as its parent offers, and displays both the toggle's label and a text field that
    indicates the toggle's state." `.switch` is also available on tvOS.
  - `PickerStyle.automatic`: "On tvOS, the default is a segmented control" (and it "may also take into
    account ... whether the picker appears in a container view").
  - `CardButtonStyle` (tvOS only): "doesn't pad the content, and applies a motion effect when a button
    has focus"; current docs: applies Liquid Glass when focused.
  - `HoverEffect.highlight`: "On tvOS, it applies a projection effect accompanied with a specular
    highlight on the view when contained within a focused view."
  - `SidebarAdaptableTabViewStyle`: "macOS and tvOS always show a sidebar."
  - `focusEffectDisabled(_:)`: turns off focus effects such as a hover effect.
  - Not available on tvOS (platform list without tvOS): `Slider`, `Stepper`, `DatePicker`,
    `MultiDatePicker`, `ColorPicker`, `TextEditor`, `Gauge`, `GroupBox`, `DisclosureGroup`,
    `OutlineGroup`, `ShareLink`, `PasteButton`, `EditButton`, `ToggleStyle.button`, `PickerStyle.wheel`,
    `PickerStyle.palette`, `TextFieldStyle.roundedBorder`, `swipeActions`,
    `navigationBarTitleDisplayMode`.
- WWDC20 "Build SwiftUI apps for tvOS" (10042): "A Card-Button creates a platter that raises and looks
  highlighted when it's focused"; a custom `ButtonStyle` "adds no existing effects for pressing and
  focused states"; `isFocused` is true when the nearest focusable ancestor is focused.
- WWDC24 "Migrate your TVML app to SwiftUI" (10207): tvOS buttons default to the bordered style (a platter
  that lifts and changes color on focus); `.borderless` shows a bare image and title, and on focus the
  image lifts with a specular highlight while the title moves out of the way; `.card` lifts more subtly;
  shelves use `scrollClipDisabled()` so focused items can grow; `.sidebarAdaptable` is a floating sidebar
  that shrinks to a compact indicator.
- Not reachable: Apple's tvOS Figma/Sketch kits (no metrics could be read without the design apps), and
  the HIG pages give no button, list row or navigation title sizes. Those are estimated.

### Measured against the tvOS 26.5 simulator

`Tests/Reference/tvos-26.5` (on the `data/references` branch) holds screenshots (3840 x 2160, 2 px/pt) and
element frames of every preview of `Examples/TVControls.swift`, `13_TVHome` and `14_TVSettings` on an Apple
TV 4K, plus four press variants. Compare with

```
scripts/calibrate.py --platform tvos --device apple-tv-4k --set tvos-26.5 [--scheme dark]
```

Constants marked **measured** in `TVMetrics` / `TVColors` come from that set (pixel sampling and the element
frames); **est.** marks what the set does not show (tvOS 18, dark-mode colors other than list rows, titles
and the backdrop, mini/extra-large controls, collapsed sidebar). The set's `dark/` captures are byte-identical
to `light/` (the simulator's appearance was not switched during capture), so dark mode is calibrated from the
two previews that set `.preferredColorScheme(.dark)` (`13_TVHome-1`, `14_TVSettings-1`).

Pixels that differ, light, `--os 26` (threshold 0.1), before and after calibration:

| Screen | before | after |
|---|---|---|
| Buttons (`TVControls-0`, `-0-right-right`) | 62.1%, 61.1% | 0.3%, 0.3% |
| Inputs (`-1`) | 54.8% | 4.2% |
| Inline Picker (`-2`) | 69.5% | 1.2% |
| Tab Bar (`-3`, `-3-down`) | 63.9%, 63.2% | 0.5%, 0.4% |
| Sidebar (`-4`) | 81.5% | 0.3% |
| Pages (`-5`) | 0.1% | 0.1% |
| Settings List (`-6`, `-6-down-down`) | 67.3%, 65.9% | 0.5%, 0.6% |
| Search (`-7`) | 73.6% | 0.8% |
| Alert (`-8`, `-8-down`) | 81.4% | 0.4% |
| Dialog (`-9`) | 79.9% | 0.2% |
| Sheet (`-10`) | 85.6% | 0.8% |
| Focus Visuals (`-11`) | 65.5% | 0.1% |
| `13_TVHome` light, dark | 25.2%, 33.2% | 1.2%, 1.3% |
| `14_TVSettings` light, dark | 67.2%, 85.7% | 1.6%, 1.0% |

### What is drawn, by area (tvOS 26 / 27 unless noted)

| Area | Drawn | Fidelity |
|---|---|---|
| Backdrop | Behind every screen, the system's soft blurred gradient (light blue top left, warm grey bottom), not a flat color: a 16 x 9 grid of the measured backdrop, drawn with cubic filtering. Dark is the light one at half brightness (`0.5 x - 61`, per channel). tvOS 18 keeps the flat window color. | measured (rmse 4/255 light, < 1/255 dark fit) |
| Focus lift | Buttons, toggles, pickers, text fields, list rows, tab items and alert actions do not scale: the platter grows by 4 pt on every side and turns white, with a shadow (gaussian sigma 10, 50% black, 12 pt down, 8 pt narrower than the platter). `.card` scales so its longer side grows by 40 pt. Labels do not move. Drawn only: frames and the focus engine use the unfocused layout. tvOS 18: scale 1.1 / 1.03 / 1.06 (est.). | measured |
| Bordered (default) button | Capsule, 66 pt, labels 30 pt in from the ends, body text; unfocused a flat film (the backdrop at 91%), focused white. Small 50 pt with caption text, large 85 pt with callout text. | measured (mini, extra large est.) |
| `.borderedProminent` | Same as bordered on tvOS 26 (grey film, primary label). tvOS 18: accent platter (est.). | measured |
| destructive / disabled | Destructive: a red platter (237, 40, 48) with a red label. Disabled: the same film, secondary label, not focusable. | measured |
| `.plain`, `.borderless` | No platter; the label lifts; its artwork gets the shadow and, for borderless, a specular highlight. | est. (unfocused look measured) |
| `.card` | Content clipped to a 12 pt rounded rect on a light film (white 28%); focused: scaled (longer side + 40 pt) with the focus shadow and a specular highlight. | measured (highlight est.) |
| Custom `ButtonStyle`, `.focusable()` | No system effect (read `isFocused`). | measured (matches) |
| Tab bar | A light capsule (white 80%; dark: black 13%), 68 pt high, 46 pt from the top; each tab is its icon and a semibold 29 pt title in the label color; contents 62 pt apart, 39 pt from the ends; the selected tab a black 10% pill (27 pt beyond its content, 14 pt inside the bar), the focused one a white pill grown 4 pt. Content starts 43 pt below the bar. tvOS 18: title-only tabs, HIG position (est.). | measured |
| `.sidebarAdaptable` | While a tab has focus: a glass panel at (35, 35), 340 pt wide, fitted to its 66 pt rows (10 apart, 19 pt in, 25 pt top, 21 pt bottom); the screen dimmed by 30% black; unselected titles secondary. The content keeps its place, 60 pt below the safe area's top. Collapsed sidebar est. | measured (collapsed est.) |
| `.page` | Content full screen; page dots twice the iOS size. | est. |
| NavigationStack | No bar background, no back button; the title (57 pt medium, dimmed: black 42% / white 30%) 4 pt below the safe area's top, content 91 pt below it; toolbar items beside it as buttons. | measured (toolbar item look est.) |
| List / Form / Section | Every row a capsule with a light film (white 15% light, 10% dark), 66 pt high on an 80 pt pitch, full width, labels 20 pt in; the focused row white and grown 4 pt; uppercase 29 pt headers in the dimmed title color, 6 pt above the first row; 29 pt secondary footers 20 pt below the last row; 26 pt between sections; values black 57% / white 55%. | measured |
| Toggle | Label and "On" / "Off" (also with `.switch`, which tvOS 26 draws the same way); outside a list a button-like capsule, labels 30 pt in. | measured |
| Picker | Automatic and `.segmented` outside lists: equal segments across the width offered, 84 pt high, on a light track (white 60%); the selected segment a black 18% pill, the focused one a white lifted pill; semibold labels. `.inline` outside a list: the same segmented control. `.menu` outside a list: a bordered button showing only the value. Automatic in a `List`: the segmented control, a focus element per option; in a `Form`, and `.navigationLink`: a value row. | measured |
| Menu, Link | Bordered buttons. | measured |
| TextField / SecureField | Capsule, 70 pt, white 55% film, text headline size (secure text as large dots), placeholder body size; focused white. The keyboard is not drawn. | measured approx. |
| searchable | The tvOS 26 search screen: a 52 pt magnifier and the prompt (57 pt bold, dimmed), the "Press ⏯ to change keyboards" hint, the keyboard row (123, SPACE, a-z, delete; the first key white while the keyboard has focus), a hairline, results 245.5 pt below the safe area's top. Typing and suggestions are not simulated (warning). | measured |
| ProgressView | 60 pt spinner / ring, 8 pt bar. | est. (tvOS 26: 40 pt spinner, label below, 10 pt white bar) |
| Alerts | The screen dimmed by 45% black; a glass card (radius 62): 586 pt wide for an alert with two actions, which sit side by side (250 pt, 24 apart) with cancel first and focused; centered bold title and message (46 pt top, 17.5 / 37.5 pt gaps); buttons 66 pt, 31 pt from the edges; unfocused actions black 10%, destructive ones red 20% with a red label; the focused one white, grown 4 pt. tvOS 18: full-screen, est. | measured |
| Confirmation dialogs | As alerts, 502 pt wide, 440 pt buttons stacked 16 apart, cancel added last, the first action focused; 83.5 pt from the title to the buttons. | measured |
| `sheet` | A glass card (radius 62) fitted to the content (5 pt above and below), centered, over the presenter dimmed by 20% black (no blur). tvOS 18: blurred full screen, est. | measured |
| `fullScreenCover` | Opaque system background, as on iOS. | as iOS |

### Not covered

- Parallax tilt, motion, and the "highlighted" (pressed) state: a still frame shows none.
- Typing on the tvOS keyboard, search suggestions, and picker option lists that open on select.
- Top Shelf, the TV app's `.tabViewStyle(.sidebarAdaptable)` sections (`TabSection`) are flattened.

## Checklist for a real tvOS simulator

Measured on tvOS 26.5 (Apple TV 4K): button sizes, padding and colors, the focus growth and shadow, card
scale, tab bar, expanded sidebar, navigation title, list rows, headers and footers, toggles (also `.switch`),
segmented / inline / menu pickers, text fields, the search screen, alerts, dialogs, sheets, the backdrop.
Still to measure:

1. Everything on tvOS 18 (all tvOS 18 values are estimates).
2. Dark appearance of controls outside lists, alerts, dialogs, sheets and the tab bar's selected pill
   (re-capture `dark/` with the simulator's appearance switched).
3. `.plain` and `.borderless` focused: scale, shadow, whether the borderless title moves down.
4. The collapsed `.sidebarAdaptable` sidebar (focus in the content).
5. Toolbar items next to the navigation title (tvOS 26 draws them 70 pt high, light film, white label).
6. ProgressView (spinner size, label below, bar colors) and `Label` icon spacing.
7. A disabled toggle (tvOS 26 keeps its label in the primary color).
8. What a `.focusable()` custom view shows on focus (here: nothing).
