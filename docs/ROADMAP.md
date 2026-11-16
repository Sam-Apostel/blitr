# Roadmap

Where the renderer stands, what is open (in priority order), and which items need a Mac. Each open item links to its issue, which has the evidence and the numbers.

## Done

- **Engine:** the SwiftUI API surface, reimplemented on Linux with Skia and HarfBuzz. iOS 18, 26 and 27 design, chosen with `--ios`; the latest is the default.
- **Platforms:** iPhone, iPad, Apple TV, Apple Watch, widgets and Live Activities.
- **Project mode** (`docs/PROJECTS.md`): XcodeGen, `.pbxproj` and SwiftPM projects, cached per-module builds, asset and string catalogs, and `--locale`. A real app's iPhone, TV, widget and Watch targets compile and render from unmodified source.
- **Framework shims** (`docs/FRAMEWORKS.md`): about 40 Apple frameworks, each its own module, all compiled into the one engine library.
- **tvOS focus** (`docs/FOCUS.md`): `--press`, `--focus`, `--focus-map` and `--focus-overlay`. Checked against tvOS 26.5 recordings: 18 of 465 moves still differ.
- **Interaction capture** (`docs/INTERACTION.md`): scripted taps, typing and scrolling. Outputs are frames, filmstrips, GIF, APNG, WebP and MP4, plus full-content captures.
- **Time and network:** `Task.sleep` runs on a virtual clock and renders are offline by default.
- **Maps** (`docs/MAPS.md`): markers, annotations and overlays on a placeholder surface, or on offline tiles the user
  supplies (`--map-tiles`).
- **Native macOS** (issue #19): the same engine builds and renders on a Mac, against a filtered SDK so user code
  sees the same frameworks as on Linux (ARCHITECTURE.md, "macOS").
- **Calibration** (`docs/REFERENCE.md`, `scripts/calibrate.py`): simulator references live on the `data/references` branch (`ios-27.0`, `ios-26.5`, `tvos-26.5` light and dark, `watchos-26.5` on three watches). The tool renders and compares against them.

| Set | Typical screen difference |
|---|---|
| iOS 27.0 | under 1.5% |
| tvOS 26.5 light, dark | under 1.6%, under 1.4% |
| watchOS 26.5 (46mm, 42mm, Ultra 2) | under 0.9%, the clock masked |

The iOS 27 sum over all screens is 26.6% in light and 30.5% in dark.

- **Extra outputs:** the accessibility tree, tap targets, `compare` heatmaps and `check --json`.
- **Device frames** (issue #26): `--frame` draws generic hardware around a render from the device profile; `--frame-dir` uses the user's own frame images.

## Open, in priority order

| # | Item | Needs a Mac |
|---|---|---|
| [#24](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/24) | watchOS chrome: safe areas, lists, titles, buttons and page dots are measured; toolbar items, the back button and bounded (scrolling) screens are open. | captures for the rest |
| [#22](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/22) | Liquid Glass: iOS 27 glass is a fitted response curve and the selected tab is vibrant. Open: the dark bar and alert curves are held partway to the old model because our lens smears blurred content near the rim (NavigationTabs-Tabs, GlassTabsAndSheets-4); text under the reference tab bars stays readable, so the system may blur less than our 14pt. | no |
| [#21](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/21) | SF Symbol frames, per glyph | measuring on a Mac helps |
| [#23](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/23) | tvOS: one focus move, tvOS 18, the few looks the set does not show (docs/TVOS.md checklist) | tvOS 18 needs captures |
| [#25](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/25) | Smaller gaps found on real apps: the `Interactions-Loading` preview varies between runs; LazyVStack spacing is measured on iOS 27 only; overrides in extensions of UIKit classes other than UIWindow's motion events are left out | iOS 18 and 26 captures |

#2 and #3 are the umbrella issues for the Mac reference work.

## How to work on it

- **Build:** `scripts/bootstrap.sh`, then `swift build`.
- **Check it still works:** `Tests/Projects/run.sh`, `Tests/Frameworks/run.sh` and `Tests/Interaction/run.sh`, plus the regression loop below. CI runs the same.
- **Regression loop:** `scripts/regression.sh OUT_DIR`, then `scripts/regression.sh --compare BEFORE AFTER`. It renders every `.swift` file under `Tests/Corpus` and `Examples` with `--open-fonts`. Use `--device apple-tv` for files matching `*TV*`. Do it before and after a change and compare the PNGs byte for byte. It renders at a fixed `--date` and time zone, so clocks and timelines draw the same every run.
- **Calibration:**
  1. Run `scripts/calibrate.py --ios 27.0 --scheme light --jobs 1`, or `--platform tvos --set tvos-26.5`, or `--platform watchos --device apple-watch-ultra-2`.
  2. Measure from the reference PNGs and accessibility JSONs.
  3. Gate each change to the OS version it was measured on.
  4. Mark the constant `// measured: <OS> simulator`.
  5. Make sure no screen gets worse.
- **New reference sets:** commit them straight to the orphan `data/references` branch. Captures never go on `main`. The capture scripts are in `scripts/mac/`.
