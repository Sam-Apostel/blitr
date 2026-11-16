# tvOS focus

`swiftui-screenshot` models the tvOS focus engine: which element has focus, where each Siri Remote
press moves it, and how to reach every element. Nothing needs a simulator; everything is computed from
the laid-out frame.

```
swiftui-screenshot render Home.swift --device apple-tv -o out/home.png \
    --focus-map out/home-focus.json --focus-overlay out/home-focus.png

swiftui-screenshot render Home.swift --device apple-tv -o out/after.png --press down,down,right,select
swiftui-screenshot render Home.swift --device apple-tv -o out/x.png --focus "Top Movies" --press right
```

`Examples/TVFocus.swift` shows the common layouts (poster grid, shelves, a layout that needs
`.focusSection()`, a TabView with settings, `@FocusState` + `defaultFocus`).

## Flags

| Flag | |
|---|---|
| `--focus-map <file.json>` | The focus map of the final state (after any presses). A summary is printed on stderr. |
| `--focus-overlay <file.png>` | The frame, dimmed, with every focusable element outlined and numbered and an arrow for every move. |
| `--press <list>` | Comma-separated presses applied in order once the first frame has settled: `up`, `down`, `left`, `right`, `select`, `menu`, `playpause`. Repeatable. The PNG shows the state after the last press. |
| `--focus <selector>` | Start with focus on an element: its `id`, `#index`, or its label (exact match first, then case-insensitive substring). An ambiguous or unknown selector is an error that lists the candidates. |

With `--all` / `--scheme both`, the map and overlay names get the same suffix as the PNGs.

## What is focusable

`Button` (and `Menu`), `NavigationLink`, `Toggle`, `Picker` (one element; each option for segmented and
inline pickers), `Link`, `TextField` / `SecureField`, the search field, tab bar items, alert and
confirmation-dialog buttons, and views with `.focusable()`.

Not focusable: disabled controls, anything inside `.focusable(false)`, zero-size views, and everything
under a presented sheet, full-screen cover, alert or dialog (the topmost presentation owns focus).
Elements scrolled out of view are focusable (`"visible": false`).

`.focusable()` on a view that already contains a focusable control does nothing (the control stays the
element); with several controls inside it warns.

## Focus state

- `@Environment(\.isFocused)` is true inside the focused element (a control's label, a custom
  `ButtonStyle`, the content of a `.focusable()` view).
- `@FocusState` with `.focused(_:)` / `.focused(_:equals:)` works both ways: focus moving writes the
  state; setting the state (in `onAppear`, an action, or as the initial value) moves focus to the first
  element in the bound region. Setting it to `false` / `nil` while focused keeps focus where it is and
  warns (tvOS would move focus elsewhere).
- Initial focus, tvOS only (other platforms render exactly as before): a `@FocusState` set in
  `onAppear`, else `defaultFocus`, else `prefersDefaultFocus(in:)` inside a matching `focusScope`, else
  the selected tab of a tab bar, else the visible element nearest the top-leading corner of the screen
  (tvOS 26.5 starts on the first poster below a centred bar of buttons, on the first list row rather than
  a toolbar button beside the title, and on an alert's cancel button, which it puts first).
- Focus on a tab item selects that tab, as on tvOS: the content switches as focus moves along the tab
  bar (down from a tab whose content has nothing focusable goes nowhere).
- When the focused element goes away (a sheet is dismissed, a screen popped), focus returns to the most
  recently focused element that is still on screen; otherwise the initial-focus rule picks one.
- `.onMoveCommand`, `.onExitCommand`, `.onPlayPauseCommand` on the focused element or an ancestor
  (the innermost one) are called by the matching press. A move still moves focus.
- `.focusEffectDisabled()` turns off the default focus effect.
- On tvOS renders `onChange(of:)` fires when a value differs from the previous pass, so UI that follows
  focus (`onChange(of: focusState)`, a top bar that switches pages as focus moves) updates after each
  move. Other platforms keep the one-shot `initial:` behaviour.
- `ScrollViewReader`'s `scrollTo(_:anchor:)`, called from an action (typically `onChange` of a
  `@FocusState` that names a section), scrolls the scroll views around the view with that id: with an anchor
  that point of the view goes to the same point of the scroll view, without one by the least amount. While the
  element focused at that moment keeps focus, the engine does not scroll it back into its margins (tvOS 26.5
  leaves a section scrolled to the top where code put it). Not animated.
- Not modelled: `scrollPosition` changed while focus moves, `hoverEffect`, long presses on select.

## Movement rules

From the focused element's frame, a press in a direction considers elements that lie beyond the
frame's edge in that direction (1pt tolerance) and overlap the beam the frame sweeps in that direction.
The nearest one along the axis wins; ties go to the larger overlap with the beam, then to the leading
(or top) edge nearest the origin's (down from a full-width row onto equal segments lands on the first),
then to the nearest centre. An element outside the beam cannot be reached by that press.

A run of presses on one axis keeps to a line (measured: tvOS 26.5). When focus moves onto an element
narrower than the one it left (down from a 520 pt poster onto a 250 pt one), the centre of the wider one is
remembered while the elements focus goes on to span it, and a tie on distance goes to the candidate across
that line before overlap: down, down from "Movie 1" (centre 400) through "Movie 21" (160 to 410) lands on
"Movie 42" (400 to 600), while "Movie 21" reached sideways goes down to "Movie 41" (160 to 360) under it. A
move onto an element as wide or wider (from a tab onto a full-width row, row to row) or on the other axis
keeps no line, so down from a full-width row still lands on the first of three equal segments. Only
`--press` paths carry the line; the static map's moves of the element focus ended on use it too.

Focus sections are targets in their own right. If the beam reaches a section's frame before (strictly
nearer than) any element, focus enters the section at its element nearest to the origin element. The
static map uses this history-free rule for presses too. Sections:

- `.focusSection()`: the frame of the modified view.
- The tab bar, spanning the full screen width at the top of the screen, where tvOS draws it (and where
  the renderer draws it on tvOS, so "up" from the content reaches it). Entering it lands on the selected
  tab, and it also wins a tie with its own items. A `.sidebarAdaptable` sidebar is a section of its own
  frame at the leading edge.
- Every `List` / `Form`.

Lazy stacks, grids, their rows and scroll views are not sections: plain geometry decides.

When focus lands on an element outside the visible part of a `ScrollView` or `List`, the enclosing
scroll views scroll (innermost first) by the least amount that shows it with tvOS's margins, measured
on tvOS 26.5: 178 pt below an element scrolled to from above (a row cut off by 37 pt scrolls 215 pt), 82 pt
above one scrolled to from below, 76 pt beside a shelf item. The margins are from the screen's edges: a
scroll view within the safe-area inset of an edge counts as reaching it, as tvOS scroll views do. When
less than 100 pt (or the margin) of content would be left, the scroll view goes to its end (the last shelf
item ends where the content ends). Offsets are clamped to the content and kept per scroll view across
passes. Other platforms keep the minimal 40 pt margin. The map is computed for the current offsets.
When focus reaches the topmost focusable element of a vertical scroll view, it scrolls back to the start, so
what is above the element (a photo, a title) shows again, even if the element was in view (measured: up from a
paragraph to the button under a post's photo scrolls 276 pt back to the top).

### History

Moves depend on history only through state: scroll offsets left by earlier presses, a tab selected by
focus, a page an `onChange` switched. The static map computes every element's moves on the current
layout, without re-rendering per element; `--press <path>` replays a path, and the map written after it
has the moves of the element focus ended on, with that history, and the line a run of moves keeps to
(above). Focus memory (a section returning to
the element it last had focus on) is not modelled: once scrolling uses the measured margins, every
recorded move of the tvOS 26.5 reference set that looked like memory (Shelves: right x3, down, right x3,
up lands on Movie 4) is plain geometry, and a memory model made 21 recorded moves disagree (down from a
centred bar item would return to the poster focused before instead of the poster below it; left from
"Play Trailer" would return to "Library" instead of the nearest button).

### Comparison with the real focus engine

`scripts/compare-focus.py` renders each preview of `Examples/TVFocus.swift` with `--focus-map` and diffs it
against the moves the tvOS 26.5 simulator recorded (`<references>/tvos-26.5/focus/`, captured on
the Mac; docs/REFERENCE.md), matching elements by label. Where our press path to an element differs from
the recorded one, or a move disagrees, it replays the recorded path with `--press` so both sides start
from the same history; it also replays the probes (longer press sequences). Mismatches (of initial focus,
moves and probe steps):

| Recording | first | margins | remembered line |
|---|---|---|---|
| Poster Grid | 0 / 81 | 0 / 81 | 0 / 81 |
| Top Bar | 117 / 133 | 9 / 133 | 1 / 133 |
| Viewer | 0 / 5 | 0 / 5 | 0 / 5 |
| Shelves | 18 / 121 | 9 / 121 | 0 / 121 |
| Unreachable | 0 / 13 | 0 / 13 | 0 / 13 |
| Focus Section | 0 / 17 | 0 / 17 | 0 / 17 |
| Settings Tabs | 16 / 41 | 0 / 41 | 0 / 41 |
| Default Focus | 0 / 13 | 0 / 13 | 0 / 13 |
| Focus On Appear | 0 / 17 | 0 / 17 | 0 / 17 |
| probe Shelves right x3, down, right x3, up | 4 / 9 | 0 / 9 | 0 / 9 |
| probe Shelves right, down, left x2, down | | 1 / 6 | 0 / 6 |
| probe Settings Tabs down x4, select, menu | 2 / 7 | 0 / 7 | 0 / 7 |
| probe Settings Tabs down x4, select, up, select | 1 / 8 | 0 / 8 | 0 / 8 |
| total | 158 / 465 | 18 / 465 (19 / 471) | 1 / 471 |

What still differs: up from "Movie 42" (reached down, down from "Movie 1") goes to "Movie 21" in the Shelves
recording, as the remembered line (400) says, but to "Movie 22" (450 to 700, the larger overlap) in the Top Bar
recording, whose posters sit at the same places 140 pt lower. Both cannot hold; reversing direction keeps the
line here. The line itself was found from "Movie 21": down from it lands on "Movie 42" when focus came from
"Movie 1" and on "Movie 41" when it came sideways from "Movie 22" (the probe right, down, left x2, down).

An app's own paths are compared with `scripts/compare-app-paths.py` against press sequences recorded by
`scripts/mac/tvos/record-app.sh` (screenshots, focused element and frames after every press): a tvOS app with
a hand-built top bar of `focusSection`s, `@FocusState` sections scrolled with `ScrollViewReader`, full-screen
covers closed with Menu, and leg pickers in horizontal scroll views matched all 172 recorded steps of 19
sequences after the changes above (none could be rendered before `--env`; with it, the first comparison had
3 of 114 steps wrong, then 1 of 58 more in new sequences).

## Presses

| Press | Effect |
|---|---|
| `up` `down` `left` `right` | `onMoveCommand`, then focus moves when there is a target. |
| `select` | Activates the focused element: runs a `Button`'s action, flips a `Toggle`, selects a tab or a segmented/inline picker option, runs an alert button's action and dismisses the alert, pushes a `NavigationLink`'s destination (closure or `value:` through `navigationDestination(for:)`). Menu pickers, text fields and `Link`s warn: opening a picker, typing and opening URLs are not simulated. A `.focusable()` view runs its tap gesture. |
| `menu` | `onExitCommand` if there is one (an `@Environment(\.dismiss)` it calls dismisses the topmost presentation, or pops); else dismisses the topmost sheet / cover / alert / dialog; else, with focus on the tab bar, nothing (tvOS leaves the app; the log's `to` is null, warning); else pops a screen pushed by `select`; else, with nothing to go back from, tvOS leaves the app (`to` is null, warning). Screens on a `NavigationStack(path:)` binding are not popped (warning). Selecting the selected tab does not pop either. When a presentation goes away focus returns to the element that opened it (measured: tvOS 26.5, a full-screen cover closed with Menu). |
| `playpause` | `onPlayPauseCommand`, or a warning. |

After each press the resolve/layout passes run again, so state changes, pushed screens and dismissed
presentations show up in the next press and in the PNG.

## The map JSON

```json
{
  "version": 1,
  "platform": "tvOS",
  "device": "Apple TV 4K",
  "size": {"width": 1920, "height": 1080},
  "modal": null,
  "initialFocus": "button-1199a3",
  "focused": "button-1199a3",
  "presses": [{"press": "down", "from": "button-1199a3", "to": "button-5d0e1a", "fromLabel": "Movie 1", "toLabel": "Movie 21",
               "note": "focus #1 \"Movie 1\" -> #9 \"Movie 21\""}],
  "elements": [
    {
      "id": "button-1199a3",
      "index": 1,
      "label": "Movie 1",
      "role": "button",
      "frame": [80, 140, 480, 270],
      "visible": true,
      "section": null,
      "moves": {"up": null, "down": "button-5d0e1a", "left": null, "right": "button-7f31c2"},
      "path": []
    }
  ],
  "sections": [{"id": "focusSection-02aa4f", "kind": "focusSection", "frame": [0, 0, 960, 1080], "elements": ["..."]}],
  "summary": {"elementCount": 30, "visibleCount": 11, "unreachableCount": 0, "issuesByKind": {"oneWay": 8}},
  "issues": [{"kind": "oneWay", "elements": ["...", "..."], "message": "..."}]
}
```

- `id` is `<role>-<hash of the view's structural identity>`: stable across runs of the same source
  (a `-2` suffix disambiguates rare collisions). `index` is the reading order (document order, tab bar
  first), the number drawn on the overlay and usable as `--focus "#3"`.
- `frame` is `[x, y, width, height]` in points, screen coordinates. A list row with one control is the
  whole row.
- `section` is the innermost section around the element.
- `moves` gives the target of each press; `path` is the shortest press sequence from `initialFocus`
  (null when unreachable).
- `initialFocus` is where focus started on the current screen (also `--focus`); `focused` is where it
  is after the presses (marked `"focused": true` on its element).
- Issue kinds: `noFocusableElements`; `unreachable` (no press path from the initial focus); `trap`
  (a group that can be entered but has no press leading back out); `oneWay` (A goes to B but the
  opposite press from B does not return to A; information, common with items of different sizes).

## Focused appearance

Each tvOS control draws its own focused state from `isFocused` (docs/TVOS.md): bordered buttons, toggles,
pickers and text fields turn into white lifted platters, `.card` / `.borderless` / `.plain` lift their
content, list rows become raised white platters, tab items, alert buttons and the search field draw
their own focused look. Custom `ButtonStyle`s and `.focusable()` views get no system effect, as on tvOS:
read `@Environment(\.isFocused)`, or add `.hoverEffect(.highlight)` / `.hoverEffect(.lift)`.
`Focus/TVFocusLook.swift` holds the shared metrics and the lift node. The scale is drawn only.

## Known differences from tvOS

- The one recorded move above that the remembered line does not explain. UIKit focus guides with their own
  preferred environments, and animated scrolling, are not modelled.
- An automatic `Picker` in a `List` is a segmented control with one element per option (tvOS 26), in a
  `Form` a row showing the value; tvOS 18 draws both as rows (est.).
- Focus effect geometry (the lift scale, parallax) does not change the frames used for movement.
