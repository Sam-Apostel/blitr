# Project mode

Point the tool at one view file inside a real project and it works out the rest:

```
swiftui-screenshot render App/Sources/HarvestListView.swift
swiftui-screenshot list   App/Sources/HarvestListView.swift      # every preview of the target
swiftui-screenshot check  App/Sources/ToolsView.swift            # compile only; summarize what is unsupported
swiftui-screenshot check  --target Orchard --json
```

`Tests/Projects/Orchard` is a complete example (an iPhone app, a TV app, a Foundation-only model package,
a UI package with a font and an asset catalog, a string catalog in two languages), described both by an
XcodeGen spec and by an Xcode project. `Tests/Projects/run.sh` exercises everything below and runs in CI.

## Discovery

From the entry file the tool walks up to the nearest project description that has a target compiling
that file, trying in each directory, in this order:

1. `project.yml` (XcodeGen): `sources` (paths, `includes`, `excludes`, `buildPhase`, `type: folder`,
   `optional`), `dependencies` (`package:` with `product`/`products`, `target:`, `sdk:`/`framework:`),
   `packages:` (local `path:`; `url:`/`github:` are remote), `include:`, `targetTemplates`, multi-platform
   targets, `options.deploymentTarget`, `options.developmentLanguage`, and the Debug build settings that
   matter for compiling (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`, `OTHER_SWIFT_FLAGS -D`, `SWIFT_VERSION`).
2. `X.xcodeproj` (`project.pbxproj`): native targets, their Sources and Resources phases, Xcode 16
   file-system-synchronized folders with their membership exceptions (in both directions), local and
   remote package references (including older projects that add a package folder as a file reference),
   target dependencies, `SDKROOT` and the deployment target of the Debug configuration.
3. `Package.swift`: read with `swift package dump-package` on a copy of the manifest in the cache (the
   package directory is never written to), cached by the manifest's contents. Targets, `path:`,
   `sources:`, `exclude:`, `resources:` (and resources SwiftPM picks up without being declared:
   catalogs, `.lproj`), `define` settings, language mode, dependencies on local packages.

A description that does not compile the file is skipped, so a stray `Package.swift` higher up does not
capture an unrelated file, and a loose file outside any project renders as before. When several targets
compile the file, applications win over extensions; `--target` chooses.

The target's platform becomes the default `--platform` (tvOS targets render on the Apple TV profile).
watchOS, macOS and visionOS targets compile with their `#if os(...)` branches but are drawn at iPhone
size, with a warning, until those platforms have device profiles.

| Flag | Meaning |
|---|---|
| `--project <path>` | `project.yml`, `X.xcodeproj`, `Package.swift`, or a directory holding one |
| `--target <name>` | The target to build. Without an entry file, renders the target's `@main App` (or `--view`) |
| `--no-project` | Compile only the given files, as for a loose file |
| `--whole-target` | Compile every file of the target instead of the entry's closure |
| `--locale <id>` | Language for string catalogs and `.strings` (default: the project's development language) |

Remote packages cannot be fetched. They are reported by name (`warning: SunCalc (remote package …)
cannot be built here`) and the build continues; it only fails if the entry's closure imports them.

## Modules

Every local package target the target depends on is compiled as its own module (a dynamic library), in
dependency order, then the target itself into the runner:

- A module whose files import only Foundation-level modules compiles unchanged (no rewriting, and
  without the SwiftUI module on its search path, so `#if canImport(SwiftUI)` stays false as on Linux).
- A module that imports SwiftUI (or any other module this tool provides, or any Apple framework) gets
  the same rewriting as app code (`#Preview`, `@main`, `#if os(...)`, `#available`) and compiles against
  the SwiftUI module. Its own previews are blanked out: only the entry file's previews are registered.
- Package targets get `-D DEBUG`, `-package-name`, their declared language mode and defines; app targets
  their Debug compilation conditions.
- Every module implicitly imports `SwiftUIScreenshotFoundation`, which supplies what Linux Foundation
  lacks and Apple code expects from `import Foundation`: `String(localized:)`, `String.LocalizationValue`,
  `LocalizedStringResource`, and `FoundationNetworking` (URLSession) re-exported.

Each module is cached under `~/.cache/swiftui-screenshot/modules/<Name>-<hash>`, the hash covering its
(rewritten) sources, flags, generated files, its dependencies' hashes, the SwiftUI module, the shim
modules and this tool's binary. Rendering another view of the same project recompiles only the target's
closure; a second render of the same view reuses the runner as well.

Compile errors are reported per module with the original paths and line numbers: rewritten files are
compiled from a mirror of their absolute paths, and every rewrite keeps line breaks where they were.

## Dependency closure

The compiler accepts a module only if every file compiles, so by default only the entry file and the
files it transitively needs are compiled (`compiling 4 of 9 files of Orchard` with `-v`, which also
lists why each file was included). The analysis is token-based and conservative:

- a file is included when it declares, at top level, a type, function, variable, typealias, protocol,
  operator or macro whose name an included file mentions (in code or string interpolations, not comments);
- an extension of a type declared in an included file is included when it adds a conformance, when an
  included file mentions one of its members, or when a member is named like a common protocol requirement
  (`body`, `id`, `hash`, `makeUIView`, ...);
- an extension of any other type (`View`, `Color`, `EnvironmentValues`, a package's type) is included when
  an included file mentions one of its members (so `.cardStyle()`, `\.seasonDay` and `.brandRed` pull in
  their files), or when it adds a conformance to a type an included file mentions;
- previews and `PreviewProvider`s of other files are blanked first, so they do not pull in more files;
- names in inactive `#if` branches still count, which only ever adds files.

`--view "RootView()"` adds the names in the expression as roots. An entry file without previews renders
the target's `@main App`, whose file becomes a root. `--whole-target` turns the analysis off.

## Resources

- **Asset catalogs** of every module are given to the renderer. Color sets: light and dark, `display-p3`
  (converted to sRGB), gray (`white`) components; high-contrast variants are skipped for the standard look;
  a color that refers to a system color is reported. Image sets: 1x/2x/3x. Vector PDF/SVG images and symbol
  sets are not supported and are reported. `bundle:` arguments are accepted; names are looked up in every
  catalog of the build.
- **Generated asset symbols**: as Xcode does, each module with a catalog gets `ColorResource.name`,
  `ImageResource.name`, `Color.name` and `ShapeStyle.name` members (lower camel case, trailing
  `Color`/`Image` dropped), skipping names the module declares itself. `Color(.name)`, `Image(.name)`,
  `UIColor(resource:)`, `UIImage(resource:)` work.
- **`Bundle.module`**: a package target with resources gets SwiftPM's accessor, pointing at a staging
  directory (symlinks, `.process` flattened, `.copy` kept). App targets' resources are staged next to the
  runner, so `Bundle.main.url(forResource:withExtension:)` finds them.
- **Fonts** among a module's resources are handed to the renderer, so `Font.custom("Name", size:)` finds
  them. `import CoreText` resolves to a stand-in whose `CTFontManagerRegisterFontsForURL` and friends
  succeed without doing anything.
- **Strings**: `.xcstrings` catalogs and `<lang>.lproj/*.strings` of every module are flattened into one
  table for `--locale` (falling back to the source language), which `Text("key")`, `LocalizedStringKey`
  (with `%@`/`%lld`/`%lf`/`%1$@` placeholders for interpolations, Markdown kept), `String(localized:)` and
  `LocalizedStringResource` read. Plural variations pick `zero`/`one`/`two`/`other` by the first integer
  argument; languages whose rules need `few`/`many` get `other`. Device variations use `other`.

## check

`check` compiles without rendering (type-checking the target; dependency modules are built and cached)
and summarizes the compiler's errors instead of printing them:

```
FAILED target Orchard (9 files)
  Unsupported, from 4 errors in 2 files:
    Frameworks not available on Linux:
      ARKit: 1 file imports it; uses ARWorldTrackingConfiguration ×2, ARSession ×1
      SunCalc: 1 file imports it; uses daylightHours ×1
```

The compiler stops at the first missing module, so `check` first probes every imported module
(`#if !canImport`), replaces the missing ones with empty stand-ins and type-checks again: the names used
from each missing framework then show up as errors and are attributed to it. Groups: frameworks not
available (files importing each, symbols used), APIs missing from the module (`View.someModifier(label:)`,
`Color.someName`, with argument labels read from the source), names not found, calls with no matching
overload, other errors. `-v` adds every error line; `--json` prints the same as JSON, with every
diagnostic. A failed `render` prints the same summary after the compiler's output.

`check <file>` checks the entry's closure; `check --target Name` checks the whole target.

## Scouting aids

To see past a blocking gap without changing this repository, three environment variables add code to a
project build: `SWIFTUI_SCREENSHOT_MODULES` (colon-separated directories of extra `Name.swiftmodule` +
`libName.so`, e.g. stand-ins for frameworks), `SWIFTUI_SCREENSHOT_IMPORTS` (modules imported into every
file compiled against the SDK, to add members to existing types) and `SWIFTUI_SCREENSHOT_EXTRA_SOURCES`
(Swift files compiled into the entry target). They are part of the cache key.

## Not supported

- Remote packages, binary targets, macro and plugin targets, Carthage and CocoaPods.
- Xcode workspaces, xcconfig files, per-file compiler flags, Objective-C sources, mixed-language targets.
- XcodeGen YAML anchors and aliases (reported), `projectReferences`, settings groups.
- Plural rules beyond zero/one/two/other, string tables other than by merging, `.stringsdict`.
- Vector and symbol images in catalogs; asset folder namespaces.
