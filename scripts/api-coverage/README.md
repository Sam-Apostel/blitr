# API coverage measurement

Measures how much of the SwiftUI API used by real apps `Sources/SwiftUI` already declares, and ranks the
gaps. The result is `docs/API-GAPS.md`.

```
scripts/api-coverage/run-all.sh <work-dir-outside-the-repo> \
    [--extra name=/path/to/local/corpus:ios,tvos ...] [--private name1,name2]
```

`--extra` adds local corpora (for example a private app) next to the public list in `corpus.txt`; with
`--private` the public document only aggregates them and `private-report.txt` (written next to the
output, never committed) carries the per-target detail.

## Pipeline

| step | script | what it does |
|---|---|---|
| 1 | `fetch-corpus.sh`, `corpus.txt` | shallow clones of the public repos at pinned commits into the work dir. Downloaded code is parsed only, never built or run. |
| 2 | `parse_interface.py`, `build_index.py` | index of our module: argument labels and defaults from the emitted `SwiftUI.swiftinterface`; types, members and enum cases from `swift symbolgraph-extract` (also for Swift, Foundation, Dispatch, Combine, Observation, to recognise non-SwiftUI names) |
| 3 | `extract.py` | parses every file with `swiftc -dump-parse` and collects modifier calls with labels, initialisers, static/implicit members with the receiving call as context, attributes, macros, environment key paths, conformances, and the names the app declares itself. `swiftc -dump-parse` drops `#if` blocks, so `os()`/`canImport()` conditions are evaluated in the script and the active branch is spliced in per platform config |
| 4 | `compare.py`, `frameworks.json` | classifies every site: covered, label gap, candidate gap, app-defined, other framework, ignored. `frameworks.json` maps names/prefixes to frameworks (hand-maintained) |
| 5 | `confirm.py`, `manual_checks.json` | compiles one snippet per candidate (batched, one line each, errors attributed by line) with `blitr render`; `manual_checks.json` holds realistic call-site snippets used as a spot-check of "covered" |
| 6 | `report.py`, `curation.json` | merges everything into the document. `curation.json` is the hand-made class (a visual, b inert, c platform-specific, d other framework) and one-line note per confirmed SwiftUI gap |

## Method limits

- "Covered" = the name exists and the call's labels fit an overload (defaults taken from the interface). Argument types are not checked, so the number is an upper bound.
- Names that cannot be attributed (generic parameters, local packages, asset catalog symbols) are excluded from the denominator.
- `frameworks.json` and `curation.json` are judgement: when the corpus changes, new unattributed names show up in the `unattributed` count and need a look.
- `frameworks_update.py` is the helper that generated most of the `names` entries; edit the JSON directly afterwards.
