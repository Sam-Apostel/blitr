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
- **Native macOS** (issue #19): the same engine builds and renders on a Mac, against a filtered SDK so user code
  sees the same frameworks as on Linux (ARCHITECTURE.md, "macOS").
- **Calibration** (`docs/REFERENCE.md`, `scripts/calibrate.py`): simulator references live on the `data/references` branch (`ios-27.0`, `ios-26.5`, `tvos-26.5` light and dark, `watchos-26.5` on three watches). The tool renders and compares against them.

| Set | Typical screen difference |
|---|---|
| iOS 27.0 | under 1.5% |
| tvOS 26.5 light | under 1.6% |

The iOS 27 sum over all screens is 26.6% in light and 30.5% in dark.

- **Extra outputs:** the accessibility tree, tap targets, `compare` heatmaps and `check --json`.
- **Device frames** (issue #26): `--frame` draws generic hardware around a render from the device profile; `--frame-dir` uses the user's own frame images.

## Open, in priority order

| # | Item | Needs a Mac |
|---|---|---|
| [#24](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/24) | watchOS chrome: lists, navigation, measured safe areas. References are in (`watchos-26.5`). | no |
| [#22](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/22) | Liquid Glass: the light glass model and the selected tab's vibrancy | no |
| [#21](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/21) | SF Symbol frames, per glyph | measuring on a Mac helps |
| [#23](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/23) | tvOS: one focus move, List toggle rows, tvOS 18 | tvOS 18 needs captures |
| [#25](https://github.com/Sam-Apostel/swift-ui-screenshot/issues/25) | Smaller gaps found on real apps: map tiles, LazyVStack text spacing, clock gaps, representables | no |

#2 and #3 are the umbrella issues for the Mac reference work.

## How to work on it

- **Build:** `scripts/bootstrap.sh`, then `swift build`.
- **Check it still works:** `Tests/Projects/run.sh`, `Tests/Frameworks/run.sh` and `Tests/Interaction/run.sh`, plus the regression loop below. CI runs the same.
- **Regression loop:** `scripts/regression.sh OUT_DIR`, then `scripts/regression.sh --compare BEFORE AFTER`. It renders every `.swift` file under `Tests/Corpus` and `Examples` with `--open-fonts`. Use `--device apple-tv` for files matching `*TV*`. Do it before and after a change and compare the PNGs byte for byte. It renders at a fixed `--date` and time zone, so clocks and timelines draw the same every run.
- **Calibration:**
  1. Run `scripts/calibrate.py --ios 27.0 --scheme light --jobs 1`, or `--platform tvos --set tvos-26.5`.
  2. Measure from the reference PNGs and accessibility JSONs.
  3. Gate each change to the OS version it was measured on.
  4. Mark the constant `// measured: <OS> simulator`.
  5. Make sure no screen gets worse.
- **New reference sets:** commit them straight to the orphan `data/references` branch. Captures never go on `main`. The capture scripts are in `scripts/mac/`.
