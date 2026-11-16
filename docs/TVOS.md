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
element frames of every preview of `Examples/TVControls.swift`, `Examples/TVControlsMore.swift`, `13_TVHome`
and `14_TVSettings` on an Apple TV 4K, plus fourteen press variants. Compare with

```
scripts/calibrate.py --platform tvos --device apple-tv-4k --set tvos-26.5 [--scheme dark]
```

Constants marked **measured** in `TVMetrics` / `TVColors` come from that set (pixel sampling and the element
frames); **est.** marks what the set does not show (tvOS 18, mini/extra-large controls). The set's `dark/`
captures were re-captured with the simulator's appearance switched, so dark mode is measured from them as well.
`TVControlsMore` (focused `.plain` and `.borderless` buttons, Labels in buttons, the collapsed sidebar, a focused
toolbar item, segmented pickers, a segmented picker in a `List`) was added to the set later, captured the same way.

Pixels that differ, `--os 26` (threshold 0.1): light before the first calibration, then light and dark before
and after measuring the re-captured dark set (`metrics.diffShare` of calibrate's `report.json`):

| Screen | light, first | light before, after | dark before, after |
|---|---|---|---|
| Buttons (`TVControls-0`, `-0-right-right`) | 62.1%, 61.1% | 0.27%, 0.27% -> 0.25%, 0.25% | 1.12%, 1.19% -> 0.23%, 0.23% |
| Inputs (`-1`) | 54.8% | 4.21% -> 0.75% | 14.16% -> 0.66% |
| Inline Picker (`-2`) | 69.5% | 1.17% -> 1.04% | 2.45% -> 1.32% |
| Tab Bar (`-3`, `-3-down`) | 63.9%, 63.2% | 0.48%, 0.41% -> 0.42%, 0.35% | 0.41%, 0.38% -> 0.39%, 0.38% |
| Sidebar (`-4`) | 81.5% | 0.33% -> 0.31% | 0.27% -> 0.22% |
| Pages (`-5`) | 0.1% | 0.14% -> 0.14% | 0.04% -> 0.04% |
| Settings List (`-6`, `-6-down-down`) | 67.3%, 65.9% | 0.49%, 0.55% -> 0.39%, 0.39% | 0.55%, 0.61% -> 0.45%, 0.45% |
| Search (`-7`) | 73.6% | 0.77% -> 0.77% | 0.73% -> 0.73% |
| Alert (`-8`, `-8-down`) | 81.4% | 0.37%, 0.37% -> 0.36%, 0.36% | 0.24%, 0.24% -> 0.20%, 0.20% |
| Dialog (`-9`) | 79.9% | 0.17% -> 0.13% | 0.12% -> 0.09% |
| Sheet (`-10`) | 85.6% | 0.82% -> 0.81% | 7.78% -> 0.54% |
| Focus Visuals (`-11`) | 65.5% | 0.05% -> 0.05% | 0.05% -> 0.05% |
| `13_TVHome-0`, `-1` (dark preview) | 25.2%, 33.2% | 1.19%, 1.17% -> 1.13%, 1.15% | 1.17%, 1.17% -> 1.15%, 1.15% |
| `14_TVSettings-0`, `-1` (dark preview) | 67.2%, 85.7% | 1.60%, 1.12% -> 1.50%, 1.01% | 1.12%, 1.12% -> 1.01%, 1.01% |

The `TVControlsMore` pass (focused `.plain` / `.borderless`, Labels in buttons, the collapsed sidebar, toolbar items,
the bold navigation title, tab bar titles, plain `List` rows, segmented pickers in lists and in dark), same
measure; "before" for the new screens is the renderer before that pass:

| Image | light before, after | dark before, after |
|---|---|---|
| `13_TVHome-0` | 1.17% -> 1.01% | 1.21% -> 1.07% |
| `13_TVHome-1` | 1.21% -> 1.07% | 1.21% -> 1.07% |
| `14_TVSettings-0` | 1.42% -> 1.26% | 0.89% -> 0.73% |
| `14_TVSettings-1` | 0.89% -> 0.73% | 0.89% -> 0.73% |
| `TVControls-0` | 0.28% -> 0.23% | 0.26% -> 0.22% |
| `TVControls-0-right-right` | 0.28% -> 0.23% | 0.26% -> 0.22% |
| `TVControls-1` | 0.81% -> 0.80% | 0.72% -> 0.71% |
| `TVControls-2` | 1.04% -> 1.04% | 1.32% -> 1.32% |
| `TVControls-3` | 0.39% -> 0.23% | 0.36% -> 0.25% |
| `TVControls-3-down` | 0.31% -> 0.13% | 0.34% -> 0.18% |
| `TVControls-4` | 0.29% -> 0.29% | 0.19% -> 0.19% |
| `TVControls-5` | 0.14% -> 0.14% | 0.04% -> 0.04% |
| `TVControls-6` | 0.39% -> 0.22% | 0.45% -> 0.28% |
| `TVControls-6-down-down` | 0.39% -> 0.22% | 0.45% -> 0.28% |
| `TVControls-7` | 0.80% -> 0.80% | 0.76% -> 0.76% |
| `TVControls-8` | 0.36% -> 0.36% | 0.20% -> 0.20% |
| `TVControls-8-down` | 0.36% -> 0.36% | 0.20% -> 0.20% |
| `TVControls-9` | 0.13% -> 0.13% | 0.09% -> 0.09% |
| `TVControls-10` | 0.81% -> 0.81% | 0.54% -> 0.54% |
| `TVControls-11` | 0.05% -> 0.05% | 0.05% -> 0.05% |
| `TVControlsMore-0` | 1.61% -> 0.07% | 0.90% -> 0.08% |
| `TVControlsMore-0-right` | 2.65% -> 0.17% | 2.20% -> 0.16% |
| `TVControlsMore-0-right-right` | 0.52% -> 0.09% | 0.60% -> 0.09% |
| `TVControlsMore-0-right-right-right` | 0.15% -> 0.07% | 0.29% -> 0.08% |
| `TVControlsMore-0-right-right-right-right` | 0.76% -> 0.43% | 0.40% -> 0.17% |
| `TVControlsMore-1` | 0.48% -> 0.23% | 0.44% -> 0.25% |
| `TVControlsMore-1-right` | 0.41% -> 0.24% | 0.39% -> 0.25% |
| `TVControlsMore-2` | 0.41% -> 0.41% | 0.23% -> 0.23% |
| `TVControlsMore-2-right` | 85.48% -> 0.32% | 11.21% -> 0.26% |
| `TVControlsMore-3` | 1.37% -> 0.04% | 1.14% -> 0.04% |
| `TVControlsMore-3-up` | 0.41% -> 0.12% | 0.38% -> 0.06% |
| `TVControlsMore-4` | 0.28% -> 0.26% | 0.22% -> 0.20% |
| `TVControlsMore-4-right` | 1.07% -> 1.04% | 1.75% -> 0.99% |
| `TVControlsMore-5` | 1.10% -> 0.10% | 4.59% -> 0.07% |
| `TVControlsMore-5-down` | 0.99% -> 0.40% | 4.94% -> 0.25% |
| `TVControlsMore-5-down-down` | 6.08% -> 0.09% | 7.76% -> 0.09% |

### What is drawn, by area (tvOS 26 / 27 unless noted)

| Area | Drawn | Fidelity |
|---|---|---|
| Backdrop | Behind every screen, the system's soft blurred gradient (light blue top left, warm grey bottom), not a flat color: a 16 x 9 grid of the measured backdrop, drawn with cubic filtering. Dark is the light one at half brightness (`0.5 x - 61`, per channel). tvOS 18 keeps the flat window color. | measured (rmse 4/255 light, < 1/255 dark fit) |
| Focus lift | Buttons, toggles, pickers, text fields, list rows, tab items and alert actions do not scale: the platter grows by 4 pt on every side and turns white, with a shadow (gaussian sigma 10, 50% black, 12 pt down, 8 pt narrower than the platter). In dark mode a focused button, toggle or text field is a light grey (207, 212, 217), a focused tab (234, 235, 235) and a focused segment (234, 234, 234); list rows, sidebar rows and alert actions stay white. Labels on a focused platter are black. `.card` scales so its longer side grows by 40 pt. Labels do not move, except in list rows (below). Drawn only: frames and the focus engine use the unfocused layout. tvOS 18: scale 1.1 / 1.03 / 1.06 (est.). | measured |
| Bordered (default) button | Capsule, 66 pt, labels 30 pt in from the ends, body text; unfocused a flat film (the backdrop at 91%; dark: white 10%), focused white (dark: light grey). Small 50 pt with caption text, large 85 pt with callout text. | measured (mini, extra large est.) |
| `.borderedProminent` | Same as bordered on tvOS 26 (grey film, primary label). tvOS 18: accent platter (est.). | measured |
| destructive / disabled | Destructive: a red platter (237, 40, 48) with a red label; dark (255, 92, 96) with a (255, 112, 117) label. Disabled: the same film, secondary label, not focusable. | measured |
| `.plain` | The bare label; focused, a light platter (white 82%, dark 88%) reaching 30 pt beyond the label at the sides and 15 pt above and below, grown 4 pt, 36.5 pt corners (a capsule around one line), a 1.5 pt white rim, the focus shadow; the label black, not moved or scaled. | measured |
| `.borderless` | No focus effect on text or shapes. An `Image` in the label lifts so its longer side grows by 40 pt, clipped to a 25 pt rounded platter (white 43%, dark 17%) with a white rim and the focus shadow; the title stays put. The faint platter an unfocused image has is not drawn. | measured |
| `.card` | Content clipped to a 12 pt rounded rect on a light film (white 28%; dark: white 11%); focused: scaled (longer side + 40 pt) with the focus shadow and a specular highlight. | measured (highlight est.) |
| Custom `ButtonStyle`, `.focusable()` | No system effect (read `isFocused`). | measured (matches) |
| Tab bar | A light capsule (white 80%; dark: black 13%), 68 pt high, 46 pt from the top; each tab is its 29 pt semibold icon and a bold 25 pt title in the label color; contents 72 pt apart, 43 pt from the ends; the selected tab a black 10% pill (dark: white 14%; 27 pt beyond its content, 14 pt inside the bar), the focused one a white pill grown 4 pt (dark: (234, 235, 235)); titles black in light. Content starts 43 pt below the bar. tvOS 18: title-only tabs, HIG position (est.). | measured |
| `.sidebarAdaptable` | While a tab has focus: a glass panel at (35, 35), 340 pt wide, fitted to its 66 pt rows (10 apart, 19 pt in, 25 pt top, 21 pt bottom); the screen dimmed by 30% black; unselected titles black 54% / white 85%; the focused row white in both appearances. The content keeps its place, 60 pt below the safe area's top. Right from a tab goes to the content element nearest it. Collapsed (focus in the content): only the selected tab, its icon and bold 28 pt title on a capsule at (50, 50), 60 pt high (white 80%; dark: black 17%), 12.5 / 13 / 23.5 pt around the icon and title, a backward chevron at x 37 beside it; the content stays where it was. | measured |
| `.page` | Content full screen; page dots twice the iOS size. | est. |
| NavigationStack | No bar background, no back button; the title (57 pt bold, dimmed: black 42% / white 30%) 4 pt above the safe area's top, content 91 pt below it (a `List` without a first header: 85). Toolbar items beside it: 70 pt capsules 2 pt below the safe area's top, headline labels 36 pt in, white in both appearances, on black 7.5% / white 10.5%; focused white and grown 4 pt, the label black. | measured |
| List / Form / Section | Every row of a `Form` a capsule with a light film (white 15% light, 10% dark; a plain `List`'s rows have none until focused), 66 pt high on an 80 pt pitch, full width, labels 20 pt in; a toggle row of a plain `List` (not a `Form`) 79 pt high; the focused row white and grown 4 pt, its label 4 pt further out and its value and chevron 4 pt further in the trailing direction; a row that opens something: the chevron's tip 3 pt inside the text inset, the value ending 81 pt before it; uppercase 29 pt headers in the dimmed title color, 6 pt above the first row; 29 pt secondary footers 20 pt below the last row; 26 pt between sections; values black 57% / white 55%. | measured |
| Toggle | Label and "On" / "Off" (also with `.switch`, which tvOS 26 draws the same way); outside a list a button-like capsule, labels 30 pt in, the value black 76% / white 70%. Disabled: the label stays primary. | measured |
| Picker | Automatic and `.segmented` outside lists: equal segments across the width offered, 84 pt high, on a light track (white 60%; dark: none); the selected segment a pill 9.5 pt inside its segment (black 18%; dark: white 20%), the focused one a white lifted pill; semibold labels. `.inline` outside a list: the same segmented control. `.menu` outside a list: a bordered button showing only the value. The focused segment white (dark: (234, 234, 234)). Automatic in a `List`: the segmented control, a focus element per option, 5.5 pt inside its 95 pt row; in a `Form`, and `.navigationLink`: a value row; `.navigationLink` outside a list has no chevron, a dimmed label (black 54% / white 40%) and a strong value (black 83% / white 66%). | measured |
| Menu, Link | Bordered buttons. | measured |
| TextField / SecureField | Capsule, 70 pt, white 55% film (dark: black 32%), text headline size (secure text as large dots), placeholder body size; focused white. The keyboard is not drawn. | measured approx. |
| searchable | The tvOS 26 search screen: a 52 pt magnifier and the prompt (57 pt bold, dimmed), the "Press ⏯ to change keyboards" hint, the keyboard row (123, SPACE, a-z, delete; the first key white while the keyboard has focus), a hairline, results 245.5 pt below the safe area's top. Typing and suggestions are not simulated (warning). | measured |
| ProgressView | A 10 pt bar with square ends and a soft shadow: fill (242, 243, 243) over no track in light, (205, 205, 205) over (17, 18, 17) in dark; a 40 pt spinner, its label 10.5 pt below in the secondary color. tvOS 18: 60 pt spinner, 8 pt bar (est.). | measured |
| `Label` | The title 19.5 pt after the icon; in a bordered button 15.5 pt, the icon 3.5 pt further in than the padding (small buttons: 11 and 2.5). | measured |
| Alerts | The screen dimmed by 45% black; a glass card (radius 62): 586 pt wide for an alert with two actions, which sit side by side (250 pt, 24 apart) with cancel first and focused; centered bold title and message (46 pt top, 17.5 / 37.5 pt gaps); buttons 66 pt, 31 pt from the edges; unfocused actions black 10% (dark: white 10%), destructive ones red 20% with a red label; the focused one white, grown 4 pt. Dark: the card barely lifts the dimmed screen (23 -> 25), the message white 56%. tvOS 18: full-screen, est. | measured |
| Confirmation dialogs | As alerts, 502 pt wide, 440 pt buttons stacked 16 apart, cancel added last, the first action focused; 83.5 pt from the title to the buttons. | measured |
| `sheet` | A glass card (radius 62) fitted to the content (5 pt above and below), centered, over the presenter dimmed by 20% black (dark: 48%; no blur); in dark its unfocused button labels are (214, 214, 214). tvOS 18: blurred full screen, est. | measured |
| `fullScreenCover` | Opaque system background, as on iOS. | as iOS |

### Not covered

- Parallax tilt, motion, and the "highlighted" (pressed) state: a still frame shows none.
- Typing on the tvOS keyboard, search suggestions, and picker option lists that open on select.
- Top Shelf, the TV app's `.tabViewStyle(.sidebarAdaptable)` sections (`TabSection`) are flattened.

## Checklist for a real tvOS simulator

Measured on tvOS 26.5 (Apple TV 4K): button sizes, padding and colors, the focus growth and shadow, card
scale, `.plain` and `.borderless` focus, tab bar, expanded and collapsed sidebar, navigation title and toolbar
items (also focused), list rows, headers and footers, toggles (also `.switch`, disabled), segmented / inline /
menu pickers (also in a `List`, and focused in dark), text fields, ProgressView, `Label` (also in buttons), the
search screen, alerts, dialogs, sheets, the backdrop, all in light and dark. Still to measure or draw:

1. Everything on tvOS 18 (all tvOS 18 values are estimates).
2. What a `.focusable()` custom view shows on focus (here: nothing).
3. Where a `List` under a tab bar and a navigation title starts (the focus recording has its first row 54 pt
   lower than here).
4. Seen but not drawn: a segment that gains focus becomes the selected one (the old selection's pill goes);
   a focused segmented control's track darkens in dark mode (black about 15%) with a light rim; an unfocused
   `.borderless` image sits on a faint platter; a `NavigationLink` outside a `NavigationStack` is disabled
   (grey label and chevron, not focusable).
