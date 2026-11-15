# swiftui-screenshot

A reimplementation of SwiftUI for Linux, drawn with Skia and HarfBuzz, that renders screenshots from unmodified SwiftUI source. Read `ARCHITECTURE.md` first, then `docs/ROADMAP.md` for what is done and what is open.

## Build and check

- **Build:** `scripts/bootstrap.sh` once (fetches Skia into `Vendor/`), then `swift build`. In the cloud environment the toolchain is at `/opt/swift/usr/bin`. On a Mac, `brew install harfbuzz pkg-config` first; see "macOS" in `docs/ARCHITECTURE.md`.
- **Suites:** `Tests/Projects/run.sh`, `Tests/Frameworks/run.sh` and `Tests/Interaction/run.sh`. CI runs them.
- **Regression loop, before and after every change** (`scripts/regression.sh OUT_DIR`, then `scripts/regression.sh --compare BEFORE AFTER`):
  - Render each file in `Tests/Corpus/*.swift`, `Examples/*.swift`, `Examples/ApiGaps/*.swift` and `Examples/Frameworks/*.swift`, with `--all --scheme both --open-fonts`. For `*TV*` files add `--device apple-tv`.
  - Compare the before and after PNGs byte for byte. Every difference must be intended.
  - `ContainersLayout` and `Interactions-Loading` vary between runs, so ignore them.
- **Stale builds:** after renaming products or libraries, run `rm -rf .build/out` before building.

## Calibration rules

- **References:** they live on the orphan branch `data/references`, never on `main`. `scripts/calibrate.py` fetches them into the gitignored `Tests/Reference/`.
- **Running it:** run `calibrate.py` with `--jobs 1`. Parallel jobs collide on the shared module cache.
- **Measured constants:**
  - Take every constant from the reference PNGs or accessibility JSONs, not from memory.
  - Mark each with `// measured: <OS version> simulator`.
  - Gate it to the OS version it was measured on (`--ios 18/26/27`).
  - Widen the gate only when another version's references agree.
- **No regressions:** a change must not make any other screen worse by 0.05% or more. Report before and after numbers per screen.

## Working conventions

- **Commits:** no AI attribution (no `Co-Authored-By`, no generated-by lines, no session links) and no model names, in commits or on GitHub.
- **GitHub text:** write PR bodies and comments with the GitHub MCP tools, not `gh api`.
- **Merging:** PRs go to `main` and are merged once CI is green.
- **Third-party apps used as test beds:** read them in place. Never copy their code, names, strings or images into this repository. Examples and tests reproduce the pattern in generic code of their own.
- **Agents:**
  - Have each agent start with `git reset --hard origin/<branch>`, because worktrees can be created from an older commit.
  - Keep two or three agents at most.
  - Agents don't push. The orchestrating session replays their commits and runs the regression loop.
