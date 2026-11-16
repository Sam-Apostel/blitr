#!/usr/bin/env python3
"""Builds docs/API-GAPS.md from compare.json + confirm.json (+ manual.json).

Usage: report.py <compare.json> <confirm.json> <manual.json> <usage.json>... --out docs/API-GAPS.md
                 [--private-out private-report.txt]

Repos listed in compare.json's `private` field are reported only as one aggregate
"private corpus" column in the public document; per-repo detail goes to --private-out
(a local file that must not be committed).
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
FW = json.load(open(os.path.join(HERE, "frameworks.json")))
CUR = json.load(open(os.path.join(HERE, "curation.json")))["entries"]
SHIMMED = {"Combine": "partial shim", "UIKit": "partial shim", "Observation": "none", "Foundation": "swift-corelibs-foundation"}


def fw_of(name):
    if name in FW["names"]:
        return FW["names"][name]
    for p, f in FW["prefixes"]:
        if name.startswith(p) and len(name) > len(p) and name[len(p)].isupper():
            return f
    return None


def lead_type(api):
    m = re.match(r"^(?:type |conformance: )?([A-Z]\w*)", api)
    return m.group(1) if m else None


def resolve(row, confirm):
    """-> (bucket, info). bucket: covered | swiftui_gap | other | app | unattributed"""
    st, api = row["status"], row["api"]
    if st == "covered":
        return "covered", None
    if st == "app":
        return "app", None
    if confirm.get(api) == "compiles":
        return "covered", None
    # The generic snippet of a modifier passes no arguments: "missing argument" means the name and its
    # labels exist (the real call sites pass the arguments).
    exists = confirm.get(api, "").startswith("other-error: missing argument")
    if api in CUR:
        return ("covered", None) if exists else ("swiftui_gap", CUR[api])
    if st.startswith("other:3p:"):
        return "other", "third-party: " + st[9:]
    if st == "other:Xcode previews":
        if exists:
            return "covered", None
        return "swiftui_gap", {"cls": "b", "group": "Xcode preview modifiers (.previewLayout/.previewDevice/.previewDisplayName/.previewContext)",
                               "note": "preview-only metadata; layout and device are covered by the tool's --layout/--device flags"}
    if st.startswith("other:"):
        return "other", st[6:]
    if st in ("candidate", "context_gap", "label_gap"):
        t = lead_type(api)
        fw = fw_of(t) if t else None
        if fw and confirm.get(api, "gap") != "compiles":
            return "other", fw
        return "unattributed", None
    return "unattributed", None


def main():
    argv = sys.argv[1:]
    out = argv[argv.index("--out") + 1]
    pout = argv[argv.index("--private-out") + 1] if "--private-out" in argv else None
    pos = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] not in ("--out", "--private-out"))]
    cmp_path, conf_path, man_path = pos[:3]
    usage_paths = pos[3:]
    cmp = json.load(open(cmp_path))
    confirm = json.load(open(conf_path))
    manual = json.load(open(man_path))
    # A realistic manual snippet named after an API settles it (for calls the generic snippets cannot express).
    for name, result in manual.items():
        if result == "compiles":
            confirm[name] = "compiles"
    private = set(cmp["private"])
    rows = cmp["rows"]

    usage = {}
    for p in usage_paths:
        usage.update(json.load(open(p)))

    # ---- classify
    res = [(r, *resolve(r, confirm)) for r in rows]
    tot = defaultdict(lambda: Counter())     # scope -> bucket -> sites
    per_repo = defaultdict(Counter)
    per_plat = defaultdict(Counter)
    for r, bucket, info in res:
        for repo, n in r["repos"].items():
            scope = "private" if repo in private else "public"
            tot[scope][bucket] += n
            per_repo[repo][bucket] += n
        for pl, n in r["plats"].items():
            per_plat[pl][bucket] += n

    def share(c):
        d = c["covered"] + c["swiftui_gap"]
        return 100.0 * c["covered"] / d if d else float("nan")

    allc = tot["public"] + tot["private"]

    # ---- gap groups
    groups = {}
    for r, bucket, info in res:
        if bucket != "swiftui_gap":
            continue
        g = info.get("group") or r["api"]
        e = groups.setdefault(g, dict(api=g, cls=info["cls"], then=info.get("then"), plat=info.get("plat"), note=info.get("note", ""),
                                      fw=info.get("fw", ""), sites=0, pub_sites=0, priv_sites=0, pub_repos=set(), plats=Counter(), apis=[]))
        for repo, n in r["repos"].items():
            e["sites"] += n
            if repo in private:
                e["priv_sites"] += n
            else:
                e["pub_sites"] += n
                e["pub_repos"].add(repo)
        for pl, n in r["plats"].items():
            e["plats"][pl] += n
        e["apis"].append(r["api"])
        if info.get("note") and not e["note"]:
            e["note"] = info["note"]

    def gkey(e):
        return (-(1 if e["priv_sites"] else 0), -e["sites"], e["api"])
    ranked = sorted(groups.values(), key=gkey)

    # ---- other frameworks
    fwt = {}
    for r, bucket, info in res:
        if bucket != "other":
            continue
        e = fwt.setdefault(info, dict(fw=info, sites=0, files=set(), repos=set(), apis=Counter()))
        e["sites"] += r["sites"]
        e["files"] |= set(r["files"])
        e["repos"] |= {x for x in r["repos"] if x not in private}
        e["apis"][r["api"]] += r["sites"]
    fwlist = sorted(fwt.values(), key=lambda e: -e["sites"])

    # ---- write the public document
    L = []
    w = L.append
    pub, prv = tot["public"], tot["private"]
    w("# API coverage of the SwiftUI module\n")
    w("Measured against real-world SwiftUI code: how much of the API that apps actually call does `Sources/SwiftUI` already declare? "
      "Reproduce with `scripts/api-coverage/` (see its README). Counts are call sites, not distinct APIs.\n")
    w("## Headline\n")
    w(f"- **{share(pub):.1f}% of SwiftUI call sites in the public corpus are covered** "
      f"({pub['covered']:,} covered, {pub['swiftui_gap']:,} not covered; {len(set(r for r in per_repo if r not in private))} repositories).")
    if prv["covered"] + prv["swiftui_gap"]:
        w(f"- Including one private corpus (an iOS/tvOS/watchOS app, aggregated, not itemised): **{share(allc):.1f}%** "
          f"({allc['covered']:,} covered, {allc['swiftui_gap']:,} not covered).")
    w("- \"SwiftUI call sites\" are modifier calls, view/type initialisers, static and implicit members (`.buttonStyle(.borderedProminent)`), "
      "property wrappers, macros, environment key paths and type/conformance uses that resolve to SwiftUI or to modules `import SwiftUI` re-exports "
      "(Observation, Combine). Sites that resolve to the app's own code, the standard library/Foundation, other Apple frameworks or third-party packages are excluded "
      "from both numerator and denominator and listed in the framework table.")
    w("- **Upper bound.** A call counts as covered when the name exists and its argument labels fit an overload (defaults taken from the emitted "
      "`SwiftUI.swiftinterface`); argument *types* are not checked, so real coverage is slightly lower. "
      f"A spot-check of {len(manual)} hand-written realistic snippets compiled for {sum(1 for v in manual.values() if v == 'compiles')} of them.")
    w("")
    w("Coverage by platform of the file the call site is in (shared = no platform signal in the path):\n")
    w("| platform | covered | not covered | share |\n|---|---:|---:|---:|")
    for pl in ("ios", "tvos", "watchos", "macos", "shared"):
        c = per_plat[pl]
        if c["covered"] + c["swiftui_gap"]:
            w(f"| {pl} | {c['covered']:,} | {c['swiftui_gap']:,} | {share(c):.1f}% |")
    w("")
    w("## Confirmed gaps, ranked\n")
    w("Every row was confirmed by compiling a snippet with `blitr` (or is a label/signature mismatch found by the interface comparison "
      "and spot-checked). Classes: **a** visual (changes pixels in a static frame, needs a real implementation), **b** inert (no effect on a static frame; a no-op shim is enough), "
      "**c** platform-specific (tvOS/watchOS/macOS only; the class it would otherwise be is in brackets), **d** other framework (see the second table). "
      "Order: APIs used by the private corpus first, then by call sites.\n")
    w("| # | API | public repos | public sites | private corpus sites | class | what it does visually |\n|---:|---|---:|---:|---:|:---:|---|")
    for i, e in enumerate(ranked, 1):
        cls = e["cls"] + (f" ({e['then']}, {e['plat']})" if e["cls"] == "c" else "")
        fwtag = f" [{e['fw']}]" if e["fw"] else ""
        note = e["note"].replace("|", "/")
        w(f"| {i} | `{e['api']}`{fwtag} | {len(e['pub_repos'])} | {e['pub_sites']} | {e['priv_sites']} | {cls} | {note} |")
    w("")
    w("## Other frameworks\n")
    w("Uses that resolve to another framework (class d), per framework: call sites, files and public repos. This table says which shim would unblock the most files. "
      "UIKit and Combine have partial shims in this repository already; their rows count only what is missing from them.\n")
    apple = [e for e in fwlist if not e["fw"].startswith("third-party")]
    third = [e for e in fwlist if e["fw"].startswith("third-party")]
    w("| framework | call sites | files | public repos | most-used APIs |\n|---|---:|---:|---:|---|")
    for e in apple[:30]:
        top = ", ".join(f"`{a}` {n}" for a, n in e["apis"].most_common(3))
        w(f"| {e['fw']} | {e['sites']:,} | {len(e['files'])} | {len(e['repos'])} | {top} |")
    tf = set()
    for e in third:
        tf |= e["files"]
    w(f"| *third-party packages ({len(third)} modules, auto-attributed by imports)* | {sum(e['sites'] for e in third):,} | {len(tf)} | | "
      + ", ".join(f"{e['fw'][12:]} {e['sites']}" for e in third[:6]) + " |")
    w("")
    bad = [(k, v) for k, v in manual.items() if v != "compiles"]
    w("## Signature findings\n")
    w("Hand-written snippets that use real Apple signatures and fail to compile here (failures caused by my own snippets were removed; several rows duplicate gaps in the table above):\n")
    for k, v in bad:
        w(f"- `{k}`: {v[7:] if v.startswith('fails: ') else v}")
    w("")
    w("## Not measured\n")
    w("- Argument types, generic constraints and result-builder content are not compared; only names, labels and defaults.\n"
      "- Behaviour: an API that compiles can still render wrongly or not at all; this is a declaration-level measurement.\n"
      "- Implicit members are checked against the parameter types the interface lists; unusual cases fall back to \"exists on some type\".\n"
      "- Names that resolve to neither our module, the standard library/Foundation, the app, nor a known framework (generic parameters, local packages, "
      f"asset-catalog symbols) are left out: {allc['unattributed']:,} sites.\n"
      "- `#if os(...)` branches are evaluated per platform config and merged by maximum count per site, so a call duplicated across platform branches counts once.\n")
    w("## Corpus\n")
    w("| name | repository | commit | platforms | Swift files | lines |\n|---|---|---|---|---:|---:|")
    corpus = [l.split() for l in open(os.path.join(HERE, "corpus.txt")) if l.strip() and not l.startswith("#")]
    files_by_repo = Counter()
    lines_by_repo = Counter()
    for k, rec in usage.items():
        files_by_repo[rec["repo"]] += 1
        lines_by_repo[rec["repo"]] += rec["lines"]
    for name, repo, sha, plats in corpus:
        w(f"| {name} | {repo} | `{sha[:10]}` | {plats} | {files_by_repo[name]} | {lines_by_repo[name]:,} |")
    w("")
    open(out, "w").write("\n".join(L) + "\n")

    # ---- private report (never committed)
    if pout:
        P = []
        pw = P.append
        pr = sorted(r for r in per_repo if r in private)
        pw("PRIVATE REPORT: do not commit\n")
        for repo in pr:
            c = per_repo[repo]
            pw(f"{repo}: covered {c['covered']}, swiftui_gap {c['swiftui_gap']}, other-framework {c['other']}, app {c['app']}, "
               f"unattributed {c['unattributed']}  -> coverage {share(c):.1f}%")
        pw("")
        for repo in pr:
            pw(f"== {repo} gaps (SwiftUI-world and other frameworks), by sites")
            lst = []
            for r, bucket, info in res:
                if bucket in ("swiftui_gap", "other") and repo in r["repos"]:
                    fs = sorted({f for f in r["files"] if f.startswith(repo + "/")})
                    lst.append((r["repos"][repo], r["api"], bucket, info if isinstance(info, str) else info.get("cls"), fs))
            lst.sort(key=lambda x: -x[0])
            for n, api, bucket, info, fs in lst[:40]:
                pw(f"  {n:4d} {api}  [{bucket}:{info}]  files: {', '.join(x.split('/', 1)[1] for x in fs[:6])}{' ...' if len(fs) > 6 else ''}")
            blocked = set()
            for r, bucket, info in res:
                if bucket in ("swiftui_gap", "other") and not (isinstance(info, str) and info.startswith("third-party")):
                    blocked |= {f for f in r["files"] if f.startswith(repo + "/")}
            allf = [f for f in usage if usage[f]["repo"] == repo]
            pw(f"  files with at least one gap: {len(blocked)} of {len(allf)}")
            imp = Counter()
            for f in allf:
                for m in usage[f]["imports"]:
                    imp[m] += 1
            pw("  imports (files): " + ", ".join(f"{m} {n}" for m, n in imp.most_common()))
            pw("")
        open(pout, "w").write("\n".join(P) + "\n")
    print("headline public %.2f combined %.2f" % (share(pub), share(allc)), file=sys.stderr)


main()
