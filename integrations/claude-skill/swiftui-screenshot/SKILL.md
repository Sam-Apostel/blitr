---
name: swiftui-screenshot
description: Render SwiftUI views to PNG on Linux. Use after changing SwiftUI code, or when asked to see, check or verify how a screen looks, in light/dark, on another device or at a larger text size. No Xcode needed.
---

# Seeing SwiftUI on Linux with swiftui-screenshot

`swiftui-screenshot` compiles your SwiftUI sources against its own implementation of the SwiftUI
API and draws the result with Skia. It is an approximation of Apple's renderer: good for layout,
spacing, colours, text and structure; not pixel-identical to a device.

Check it is there with `swiftui-screenshot doctor`. If the command is missing, tell the user; do not
try to install it yourself unless asked.

## Render

```
swiftui-screenshot list Sources/Feature/ProfileView.swift          # which previews exist
swiftui-screenshot render Sources/Feature/ProfileView.swift -o /tmp/profile.png
swiftui-screenshot render Sources/Feature --all --out-dir /tmp/shots --scheme both
swiftui-screenshot render Sources/Feature/Row.swift --view "Row(item: .sample)" --layout fit
```

Then open the PNG files and look at them. Write them outside the source tree (for example `/tmp`)
so they do not end up in a commit.

What is drawn, first match wins: `--view "<expression>"`, `#Preview` blocks (`--preview <n|name>`
or `--all`), `PreviewProvider` types, the first `WindowGroup` of an `@main App`. A directory renders
a whole module; pass the directory (or all files) that the view depends on, not only the one file.

## Choosing what to render

- Device: `--device iphone-16` (default), `iphone-se` for small screens, `iphone-16-pro-max`, `ipad`, `apple-tv-4k`
  (tvOS, early support; `--platform tvos` also picks the `#if os(tvOS)` code). `swiftui-screenshot devices` lists them.
- Design: the default look is the latest iOS (`--ios 27`, Liquid Glass). `--ios 26` and `--ios 18` (flat) draw the older
  looks; use one of them when the app targets that release. Glass geometry is estimated, not measured.
- Appearance: `--scheme light|dark|both`. Check dark mode for anything with colours.
- Layout: `device` (full screen with status bar, default), `fit` (just the view, good for components,
  with `--width <pt>` to propose a width), `fixed` with `--width`/`--height`.
- Text size: `--dynamic-type xxxLarge` or `accessibility3` to find truncation and overlap.
- Images and fonts: `--assets <dir>` for `.xcassets`, `--fonts <dir>` for custom fonts.
- Structure instead of pixels: `--accessibility-outline` (text), `--accessibility-tree f.json`, `--tap-targets f.png`
  (hit areas under 44pt in red). They do not change the PNG.
- Slow or odd output: `--no-cache` recompiles, `-v` shows the compiler command.

## Reading the result

- The tool prints each PNG path and its pixel size. `--json` prints one JSON object per image.
- Warnings are lines starting with `warning:` on stderr (or the `warnings` array in `--json`). They name
  anything not rendered faithfully: an SF Symbol with no open equivalent (drawn as a placeholder),
  a missing asset, a UIKit-backed view. Mention relevant ones to the user.
- Fonts are open substitutes (Inter with SF Pro's advance widths, so line breaks match to about 1%) unless Apple's
  fonts are installed (`--open-fonts` forces the substitutes). Glyph shapes differ. Compare structure, not exact glyph shapes.
- Animations, gestures, scrolling position and real data are not simulated: you see a first frame.
  `.task` closures get a short budget (`--task-budget <s>`) before the frame is taken.

## When a file does not compile

The tool prints the compiler errors against your file names, then says the sources did not compile
against the Linux SwiftUI module.

- An error saying a type, modifier or member does not exist (`has no member`, `cannot find 'X' in
  scope` for a SwiftUI API) is a gap in the renderer. The user's code is probably fine for Xcode.
  Do not rewrite it to work around the renderer. Render a smaller piece with `--view`, or give a
  preview a simplified stand-in, and tell the user which API is unsupported.
- Errors in the user's own code (typos, missing files from the module) are ordinary bugs: fix them.
  If a type comes from another file, include that file or directory in the command.
- An error that says the modules were built with a different Swift version means the toolchain on
  PATH does not match; `swiftui-screenshot version` and `doctor` show both. Report it, do not fight it.
- Code that needs frameworks beyond SwiftUI/Foundation (SwiftData, MapKit, network calls) will not
  build; render a view that takes plain values instead.

## Habit

After a UI change, render the affected previews in light and dark, look at the images, and say what
you saw (and any warnings) before calling the change done. If the project has no `#Preview` for the
view, add one: it is how the tool finds the view and it is useful in Xcode too.
