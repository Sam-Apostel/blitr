# Reference: accessibility outputs and compare

Details for `--accessibility-tree`, `--tap-targets`, `--accessibility-outline` and
`swiftui-screenshot compare`. The README has the short version.

## Accessibility tree and tap targets

For agents and CI that want structure rather than pixels:

```
swiftui-screenshot render Screen.swift --accessibility-tree a11y.json --tap-targets taps.png --accessibility-outline
```

| Flag | Output |
|---|---|
| `--accessibility-tree <file.json>` | The accessibility tree, tap-target data and an `issues` array. |
| `--tap-targets <file.png>` | The screenshot dimmed, every interactive element's hit rect outlined and lightly filled: green when both sides are at least 44pt, red otherwise (with a `WxH` label). |
| `--accessibility-outline` | The tree as indented text on stdout, one element per line: `button "Follow" (16,360 170x38)`. With `--json` the text is in the result's `outline` field. |

With several images (`--all`, `--scheme both`) the file names get the same suffix as the PNGs
(`a11y-Dark-dark.json`), in `--out-dir` unless the flag value has its own directory. The `--json` result lists
`accessibilityTree`, `tapTargets` and an `accessibility` summary. Rendering is unaffected: the PNG is
byte-identical with or without these flags.

The tree follows what VoiceOver would see, approximately: `Text` is static text, images are labelled by
their symbol or asset name (`Image(decorative:)` is hidden), buttons, links, menus, toggles, sliders, steppers,
pickers and text fields are elements with label, value and traits, and `.accessibilityElement(children:)`,
`.accessibilityLabel/Value/Hint/Identifier/AddTraits/Hidden/SortPriority` are honoured. Navigation bar, tab bar,
list section headers, alerts, dialogs and sheets are read from the system chrome; elements behind a modal
presentation are omitted. `onTapGesture` and friends make a view a tap target.

JSON shape (frames are points in screen coordinates):

```json
{ "version": 1, "device": "iPhone 16", "size": {"width": 393, "height": 852}, "scale": 3, "colorScheme": "light",
  "modal": {"kind": "alert", "obscuredElements": 24},
  "elements": [ { "role": "button", "label": "Follow", "value": "...", "hint": "...", "identifier": "...",
                  "traits": ["button"], "enabled": true, "frame": {"x": 20, "y": 359, "width": 170, "height": 38},
                  "interactive": true, "hitFrame": {"x": 20, "y": 359, "width": 170, "height": 38},
                  "meetsMinimumSize": false, "offscreen": true, "truncated": true, "inputLabels": ["..."],
                  "actions": ["..."], "children": [] } ],
  "summary": {"elementCount": 12, "interactiveCount": 3, "issueCount": 2, "byRole": {"button": 3},
              "issuesByKind": {"smallTarget": 2}},
  "issues": [ {"kind": "smallTarget", "message": "...", "frame": {"x": 0, "y": 0, "width": 0, "height": 0},
               "label": "Follow", "identifier": "...", "related": {"x": 0, "y": 0, "width": 0, "height": 0}} ] }
```

Always present on an element: `role`, `label` (possibly empty), `traits`, `enabled`, `frame`, `interactive`,
`actions`, `children`. Present only when set: `value`, `hint`, `identifier`, `inputLabels`; `hitFrame` and
`meetsMinimumSize` only when `interactive`; `offscreen` and `truncated` only when true. Top level: `modal` only when an
alert, dialog or sheet is presented; `issues` is always present. Roles: `button`, `link`, `header`, `image`,
`staticText`, `switch`, `slider`, `stepper`, `picker`, `segmentedControl`, `textField`, `secureTextField`,
`textEditor`, `searchField`, `datePicker`, `colorPicker`, `progress`, `gauge`, `tab`, `tabBar`, `navigationBar`,
`alert`, `dialog`, `sheet`, `group`. Scroll content below the fold stays in the tree, flagged `offscreen`.

Issue kinds: `smallTarget` (hit area under 44x44pt), `missingLabel` (interactive element with no label),
`imageMissingLabel` (image read only by its asset name), `duplicateIdentifier`, `overlappingTargets` (`related` is the
other frame) and `truncatedText` (cut off by its line limit). System controls and bar items get the platform's
expanded 44pt hit region; a lone control in a list row is hit across the whole row.
[`Examples/Accessibility.swift`](Examples/Accessibility.swift) contains one of each problem.

## Comparing against references

`compare` is the Linux half of a calibration loop: screenshots captured from the real iOS Simulator
(references) are compared with this tool's renders (candidates), so you can see where and by how much
the render is off.

```
swiftui-screenshot compare <reference> <candidate> [options]
```

`<reference>` and `<candidate>` are two PNG files, or two directories compared by relative file name
(files present on one side only are listed). The suggested layout for references is
`Tests/Reference/<ios>/<device>/<scheme>/<name>.png` with an optional `<name>.json` of element frames; render
with `--accessibility-tree <name>.json` next to the candidate PNG and both trees are picked up automatically.
`scripts/calibrate.py` does the whole loop for a reference set: it renders every captured preview at the set's
OS version, device, scheme and time zone (`--time-zone`, from the manifest's `simulatorTimeZone`; Europe/Brussels
for sets that record none) and compares the two directories.

| Option | Meaning |
|---|---|
| `--out-dir <dir>` | Writes `<name>.heatmap.png`, `<name>.compare.png` and `report.json` there. |
| `--scale <n>` | Pixels per point of both images (default 3); everything is reported in points. |
| `--threshold <0..1>` | Per-pixel perceptual tolerance (default 0.1, as in pixelmatch). |
| `--mask x,y,w,h` | Region in points left out of the comparison (repeatable). `--mask-file <json>`: `{"Name.png": [[x,y,w,h]], "*": [...]}`. |
| `--reference-tree <json>`, `--tree <json>` | Element frames of each side (files, or directories in directory mode). Default: `<name>.json` beside each PNG. |
| `--status-bar <pt>`, `--home-indicator <pt>` | Heights of the zones reported separately (default 54 and 34; 0 turns them off; ignored for images under 400pt tall). |
| `--max-shift <px>` | Largest offset searched (default 12). |
| `--baseline <scores.json>` | With `--update-baseline`, store each image's score; otherwise compare against it. `--fail-on-regression` exits 1 when an image scores more than `--epsilon` (default 0.0005) below its baseline. |
| `--json` | Print the report on stdout instead of the summary. |

The exit code is 0 whenever the comparison ran, unless `--fail-on-regression` triggers. The summary has one line
per image, worst first, then details (shift runs, clusters, geometry) for the worst three.

**Pixels.** Each pixel pair is compared with pixelmatch's YIQ distance; pixels that only differ because of
anti-aliasing are ignored (and counted). `score` is `(1 - diffShare) * (1 - meanDistance)`, 1 meaning identical,
where `diffShare` is the share of differing pixels and `meanDistance` the mean 0..1 distance over all compared
pixels. If the sizes differ the overlapping top-left region is compared and the rest counts as differing. `clusters`
are the 10 largest groups of differing pixels (merged when within 6pt) with their bounding box in points, pixel
count and the mean reference and candidate colour of their pixels.

**Shift runs.** The most useful output for layout calibration. For every pixel row the comparison finds the
vertical offset (within +-12px) at which the candidate matches the reference best, picks one offset per row with
a penalty for changing it, and keeps the stretches where a non-zero offset removes at least half of the error.
Each stretch is then searched for a horizontal offset in bands of about 32pt, and neighbouring bands with the
same offsets become one run: `y 261 to 839pt: candidate is 2pt higher than reference` means that rows 261 to 839pt of
the reference appear 2pt higher in the candidate (positive `dy`: candidate lower, positive `dx`: candidate further
right). `explained` is the share of the error in that stretch that the shift removes. The status bar and home indicator zones are also reported on their own (`shift.zones`).

**Geometry.** With both trees, elements are matched by identifier, then role and label (in reading order), then
label alone, then unlabeled elements of the same role when the counts agree. Deltas are candidate minus
reference in points; `systematic` groups equal offsets ("everything from y=285pt down (21 elements) is 2pt
higher", "9 button elements are 4pt taller"). Elements without a counterpart are listed per side.

**Reference tree schema** (to be produced from the simulator): a list, or an object with `elements` / `children`,
of nodes that nest through `children`:

```json
[ { "role": "XCUIElementTypeButton", "label": "Follow", "value": "optional", "identifier": "optional",
    "frame": {"x": 20, "y": 359, "width": 170, "height": 38}, "children": [] } ]
```

`role` may also be given as `type` / `elementType` and is matched case-insensitively with the `XCUIElementType`
prefix removed (`Button`, `button` and `XCUIElementTypeButton` agree; `Text` is `staticText`; application and window
nodes are skipped). `label` may be `title` / `name`. `frame` may also be `[x, y, w, h]` or `"{{x, y}, {w, h}}"`. This
tool's own `--accessibility-tree` output is accepted on either side.

**`report.json`**: `{version, reference, candidate, scale, threshold, summary{images, identical, differing,
onlyInReference[], onlyInCandidate[], worstScore}, regressions[], warnings[], images[]}`, worst first. Each image has
`name, referenceFile, candidateFile, reference{width,height}, candidate{...}, sizeMismatch, compared{...},
metrics{score, diffPixels, diffShare, meanDistance, maxDistance, antialiasedIgnored, maskedPixels, comparedPixels,
outsidePixels}, clusters[{x, y, width, height, pixels, referenceColor, candidateColor}], shift{maxShiftPx,
runs[{y0, y1, dy, dx, dyPx, dxPx, explained, description}], bands[{y0, y1, dyPx, dxPx, diffShare, status}],
zones{statusBar, homeIndicator}}, images{heatmap, composite}, geometry{matched, moved, unmatchedReference[],
unmatchedCandidate[], systematic[], deltas[{role, label, dx, dy, dw, dh, reference, candidate}]}, baseline{status, score,
delta}`. In the heatmap the reference is faded, differing pixels are red, ignored anti-aliasing yellow, masks hatched
blue, size-mismatch areas magenta, cluster boxes green and shift runs a blue bar on the left edge. The composite
is `reference | candidate | heatmap`.

Limits: one offset per pixel row (a screen whose left and right halves moved differently reports the dominant
one); shifts beyond `--max-shift` (for example list rows that each grow by 4pt, which accumulate) are not
followed, so use the geometry deltas there; the pixel comparison runs in a runner compiled against the
SwiftUI module (like `devices`), so it needs `swiftc` on first use.

