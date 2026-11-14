# tvOS look

`--platform tvos` (implied by `--device apple-tv`) draws tvOS controls and system chrome. `--os 18` draws
the tvOS 18 look (opaque platters), `--os 26` / `--os 27` the Liquid Glass look (the same flag as `--ios`;
the version applies to the platform rendered). The code is in `Sources/SwiftUI/Focus/TVFocusLook.swift`
(metrics, colors, the lift), `Sources/SwiftUI/Controls/TV*.swift` and `Sources/SwiftUI/Chrome/TV/`.
`Examples/TVControls.swift` shows every area; `Tests/Corpus/13_TVHome.swift` and `14_TVSettings.swift` are
full screens.

## Research: what tvOS draws, and where the numbers come from

Every constant is in `TVMetrics` / `TVColors` and marked there as **measured** (from a source below) or
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

### What is drawn, by area

| Area | Drawn | Fidelity |
|---|---|---|
| Focus lift | Focused control scaled 1.1 about its centre with a drop shadow; list rows 1.03; tab items and segments 1.06. Drawn only: frames (and the focus engine) use the unscaled layout. | scale est. (1.05–1.1 in community measurements); shadow est. |
| Bordered (default) button | tvOS 18: rounded-rect platter (12 pt radius est.), grey translucent; focused: white, dark label, lifted. tvOS 26/27: glass capsule; focused: white capsule with a glassy rim. Height 66 pt. | height measured; colors sampled; padding, radius est. |
| `.borderedProminent` | Accent platter, white label; focused: lifted, slightly brighter. | est. |
| `.plain`, `.borderless` | No platter; the label lifts; its artwork (largest image or shape) gets the shadow and, for borderless, a specular highlight. The title is lifted with it (tvOS moves it down instead). | est. |
| `.card` | Content clipped to a 12 pt rounded rect on a faint platter; focused: lifted with shadow and specular highlight (glass platter on 26/27). | est. |
| destructive / disabled / `controlSize` / `buttonBorderShape` | Red label; 50% opacity and not focusable; heights 44/54/66/80/92; capsule, circle, rounded rect. | est. |
| Custom `ButtonStyle`, `.focusable()` | No system effect (read `isFocused`). `isPressed` is false. | per WWDC20 |
| `hoverEffect(.highlight / .lift)` | Inside a focused view: `.highlight` = small lift + specular, `.lift` = scale + shadow. `focusEffectDisabled` / `hoverEffectDisabled` turn them off. | est. |
| Tab bar | tvOS 18: titles centred at the top (top 46, height 68) on a translucent capsule; selected tab on an opaque pill; focused tab white, lifted, dark title. tvOS 26/27: same in a glass capsule. Content's safe area starts below the bar. | position measured; rest est. |
| `.sidebarAdaptable` | Floating sidebar at the leading edge: compact column of icons while focus is in the content, expanded panel (icons and titles, content dimmed) while a tab has focus. | est. |
| `.page` | Content full screen; page dots twice the iOS size. | est. |
| NavigationStack | No bar background and no back button; title centred at the top of the safe area (48 pt medium, est.); toolbar items beside it as tvOS buttons. Bottom-bar items are not drawn (warning). | est. |
| List / Form / Section | No cards, no separators, no background; rows 70 pt min with 30 pt insets; focused row a white, lifted, rounded platter with dark content; secondary sentence-case headers and footers; chevrons on navigation rows; `LabeledContent` value trailing. Lists take the width they are given (tvOS Settings' half-width layout is an app layout, not a List default). | est. |
| Toggle | Full-width row: label + "On"/"Off" (docs); `.switch` draws a switch. In a List the row draws the platter. | layout per docs; sizes est. |
| Picker | automatic: segmented outside lists (docs), value row inside lists (est.); `.menu` / `.navigationLink`: value row; `.inline`: a focusable row per option with a checkmark; `.segmented`: segments on a track, the focused one white and lifted, the selected one marked. | est. |
| Menu, Link | Bordered buttons. | est. |
| TextField / SecureField | Rounded platter (capsule on 26/27) with text or placeholder; focused: white, lifted. The full-screen keyboard is not drawn. | est. |
| searchable | A wide field below the title with a large magnifier and prompt (keyboard not drawn; warning). | est. from HIG image |
| ProgressView | 60 pt spinner / ring, 8 pt bar. | est. |
| Alerts, confirmation dialogs | tvOS 18: full-screen blurred, dimmed backdrop; centred title and message; stacked 560 x 66 platters, cancel last. tvOS 26/27: the glass card of the HIG image. The focused action is white and lifted. | 26 card measured; 18 est. |
| `sheet` | Content over a blurred, dimmed copy of the presenter, full screen. | est. |
| `fullScreenCover` | Opaque system background, as on iOS. | as iOS |
| Materials, colors, separators | Unchanged (iOS values); list separators are not drawn on tvOS. Light stays the default appearance. | iOS values |

### Not covered

- Parallax tilt, motion, and the "highlighted" (pressed) state: a still frame shows none.
- The tvOS keyboard, search suggestions, and picker option lists that open on select.
- Top Shelf, the TV app's `.tabViewStyle(.sidebarAdaptable)` sections (`TabSection`) are flattened.
- tvOS system colors and the default window background are the iOS ones (white / black); a tvOS
  simulator's light background may be a light grey.

## Checklist for a real tvOS simulator

Things estimated here that should be measured against tvOS 18 and tvOS 26 simulators:

1. Bordered button (tvOS 18): corner radius, horizontal padding, unfocused platter color in light and dark, focused scale and shadow.
2. `.card` and `.borderless`: focused scale, shadow, whether the borderless title moves down by the image growth.
3. `.plain` on tvOS: does a focused plain button scale its label?
4. Tab bar (18): is there a full-width translucent background or a capsule? Title font size, pill insets, selected-tab color when the bar is not focused.
5. Tab bar (26/27): glass capsule size and position.
6. `.sidebarAdaptable` on tvOS: compact and expanded sizes, whether content is dimmed.
7. Navigation title font and position; where toolbar items go.
8. List rows: height, insets, spacing, focused-row scale; header and footer fonts; chevrons on navigation rows (shown here).
9. Picker in a Form with the automatic style: value row or segmented?
10. Toggle `.switch` look on tvOS.
11. Alerts (18): layout, button width; confirmation dialogs (18 and 26).
12. `sheet` presentation on 18 and 26.
13. What a `.focusable()` custom view shows on focus (here: nothing).
14. Light-mode window background color.
