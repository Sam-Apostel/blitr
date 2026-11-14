# swiftui-screenshot

Renders SwiftUI source code to a PNG on headless Linux. No macOS, no simulator, no browser.

```
swiftui-screenshot render ContentView.swift -o shot.png
```

![Screens rendered on Linux](docs/images/screens-1.png)
![More screens rendered on Linux](docs/images/screens-2.png)

Every image above was produced on Linux from the unmodified SwiftUI files in
[`Tests/Corpus/`](Tests/Corpus).

## How it works

Apple's SwiftUI is closed-source and only runs on Apple platforms, so this project is a
reimplementation: a Swift module **named `SwiftUI`** that your code compiles against
unchanged, with its own layout engine, text engine and rasterizer.

1. Your sources are rewritten slightly (`#Preview` becomes a registered entry, `@main` is
   dropped, `#if os(iOS)` branches are kept).
2. They are compiled with the regular Swift toolchain against this module.
3. The resulting program resolves the view tree, lays it out with SwiftUI's
   propose/size/place protocol, draws it with Skia, and writes a PNG.

A cold render takes about a second including compilation; repeat renders of the same
sources are cached and take about half that. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Install

The tool compiles your sources at render time, so it needs a Swift toolchain of the exact version
it was built with (currently 6.4.2; `swiftui-screenshot version` and `doctor` say which).

**From a release** (Ubuntu 24.04, x86_64 or arm64):

```
curl -fsSL https://github.com/Sam-Apostel/swift-ui-screenshot/releases/latest/download/install.sh | bash -s -- --claude-instructions
```

`install.sh` installs `libharfbuzz0b` if missing, the pinned Swift toolchain into `/opt/swift` if no
matching `swiftc` is found, unpacks the tarball to `/opt/swiftui-screenshot`, links
`/usr/local/bin/swiftui-screenshot` and runs `doctor`. It is idempotent and quiet on success. Options:
`--prefix DIR`, `--version vX.Y.Z`, `--from <tarball path or URL>`, `--bin-dir DIR`, `--claude-instructions`
(adds a short block about the tool to `~/.claude/CLAUDE.md`), and `--apple-fonts
--accept-apple-font-license` (fetches Apple's fonts from Apple under Apple's terms; see `scripts/fetch-apple-fonts.sh`, which
is also installed in `share/swiftui-screenshot/`).

In a Claude Code cloud environment, use that line as the setup script (it runs as root; the
toolchain download is about 1 GB, so it can take a few minutes on first run). To let agents in an
app repository know how to use the tool, copy `integrations/claude-skill/swiftui-screenshot` into
the repository's `.claude/skills/`.

> While this repository is private, release assets cannot be downloaded anonymously and the line
> above fails. Make the repository (or its release assets) public, or download the `.tar.gz` and its
> `.sha256` yourself and run `./install.sh --from ./swiftui-screenshot-vX.Y.Z-linux-x86_64.tar.gz`.

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed; `scripts/make-dist.sh`
builds the same relocatable tarball locally (`bin/`, `lib/swiftui-screenshot/`, `share/swiftui-screenshot/`).

**From source** (Swift 6 toolchain, `libharfbuzz-dev`, `curl`, `unzip`):

```
scripts/bootstrap.sh     # fetches pinned Skia and open fonts into Vendor/ (checksummed)
swift build -c release
"$(swift build -c release --show-bin-path)/swiftui-screenshot" doctor
```

**Docker** (the image keeps the toolchain, since your code is compiled at render time):

```
docker build -t swiftui-screenshot .
docker run --rm -v "$PWD:/work" swiftui-screenshot render MyView.swift -o shot.png
```

## Usage

```
swiftui-screenshot render <file-or-dir>... [options]
swiftui-screenshot list <file-or-dir>...       # previews found in the sources
swiftui-screenshot devices
swiftui-screenshot doctor
```

What gets rendered, first match wins: `--view "ContentView()"`, a `#Preview` (pick with
`--preview <index|name>`, or `--all`), a `PreviewProvider`, or the first `WindowGroup` of an
`@main App`.

| Option | Meaning |
|---|---|
| `-o file.png`, `--out-dir dir` | Where to write. `--out-dir` is required when several images are produced. |
| `--scheme light\|dark\|both` | Appearance. |
| `--device iphone-16` | Screen size, scale, safe areas, size classes and status bar of a device: every iPhone from SE / 11 to the 17 family and Air, current iPads. Names are forgiving (`iphone-16-pro`, `"iPhone 16 Pro"`, `iphone16pro`). See `devices`. |
| `--orientation portrait\|landscape` | `landscape-left` / `landscape-right` also work. Swaps the size, uses landscape insets; iPhones hide the status bar. `#Preview(traits: .landscapeLeft / .sizeThatFitsLayout / .fixedLayout(...))` set the defaults per preview; flags override them. |
| `--rounded-corners` | Clip to the device's rounded display, corners transparent. |
| `--show-island` | Draw the Dynamic Island or notch on top (simulator screenshots do not show it). |
| `--layout device\|fit\|fixed` | Full screen with status bar; or just the view's own size; or an exact `--width`/`--height`. |
| `--dynamic-type xxxLarge` | Dynamic Type size. |
| `--assets dir` | Images and `.xcassets` catalogs. The directories you pass as sources are searched automatically. |
| `--fonts dir` | Extra fonts, including your own SF Pro (see below). |
| `--json` | One JSON object per image, with size and warnings. |

Pass a directory to render a multi-file module. Anything that is not rendered faithfully is
reported as a warning (an unmapped SF Symbol, a missing asset, a UIKit view).

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

## What is supported

- **Layout**: stacks, frames, padding, alignment guides, `Spacer`, `GeometryReader`, safe
  area, `ScrollView`, lazy stacks and grids, `Grid`, `ViewThatFits`, custom `Layout`s.
- **Drawing**: shapes with continuous corners, gradients, materials, shadows, blur, masks,
  blend modes, transforms, `Canvas`.
- **Text**: wrapping, truncation, Markdown and interpolation in literals, all font designs
  and weights, Dynamic Type, emoji.
- **Controls**: `Button` and its styles, `Toggle`, `Slider`, `Stepper`, `Picker`,
  `TextField`, `DatePicker`, `ProgressView`, `Gauge`, `Label`, `Menu`, and more.
- **System chrome**, drawn to iOS 18 metrics: `NavigationStack` (large and inline titles,
  toolbars, search), `TabView`, `List`/`Form`/`Section`, sheets, alerts, confirmation dialogs.
- **State**: `@State`, `@Binding`, `@Observable`, `ObservableObject`/`@Published`,
  `@Environment`, `@AppStorage`, preferences. `onAppear` and `.task` run before the frame
  is taken, so views show their loaded state.
- **SF Symbols**: about 1,500 names drawn from an open icon set.
- Gestures, animations, transitions and focus APIs compile and are ignored; accessibility modifiers feed the
  accessibility outputs above and never change the picture.

## Limitations

- **It is an approximation.** Output is close to a simulator screenshot, not identical.
  Spacing constants for system components were set from knowledge of iOS, not measured
  against a device; they live in named constants (`ListMetrics`, `NavigationBarMetrics`, ...)
  so they can be calibrated.
- **Fonts.** SF Pro cannot be redistributed. Inter is used instead, so text is slightly
  wider or narrower than on a device, which can change where lines wrap. To use the real
  fonts, put your own `SF-Pro.ttf` (and optionally `SF-Pro-Italic.ttf`, `SF-Mono.ttf`,
  `NewYork.ttf`, `SF-Pro-Rounded.ttf`) in a directory and pass `--fonts`.
- **SF Symbols** are stand-ins from Phosphor Icons. They are recognisable but not Apple's
  artwork; unmapped names render as a dashed placeholder and are listed as warnings.
  Multicolor and hierarchical rendering fall back to a single color.
- **iOS 18 design language.** Liquid Glass (iOS 26 and later) is not reproduced.
- **One static frame.** No animation, gestures or scrolling; content is shown at scroll
  offset zero. Remote images (`AsyncImage`) show their placeholder. Network calls in
  `.task` will generally not complete.
- **Apple frameworks other than SwiftUI are not available.** `UIViewRepresentable`,
  MapKit, Charts, SwiftData, WebKit, AVKit and third-party packages will not compile or
  render. A small UIKit shim covers `UIColor`, `UIScreen`, `UIDevice` and similar.
- **API coverage is broad but not complete.** An API this module lacks is a compile error
  naming it, never a silently wrong picture.
- **Left-to-right text only.** iPhone layouts are the tested path; iPad profiles exist but
  split views render a single column.

## Licences

The code in this repository is the project's own. It builds on, and `scripts/bootstrap.sh`
downloads, third-party components under their own licences: Skia (BSD-3-Clause, prebuilt
by the SkiaSharp project, MIT), HarfBuzz (MIT), Inter, Nunito, Source Serif 4, JetBrains
Mono and Noto Color Emoji (SIL OFL 1.1), and Phosphor Icons (MIT, artwork compiled into
`Sources/SwiftUI/Symbols`). SwiftUI, SF Pro and SF Symbols are trademarks of Apple Inc.;
this project is not affiliated with Apple and contains no Apple code, fonts or artwork.
