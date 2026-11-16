#!/usr/bin/env python3
"""Compare the renderer's tvOS focus map with focus moves recorded on a real Apple TV simulator.

    scripts/compare-focus.py [--set tvos-26.5] [--only REGEX] [--out out/focus] [--verbose]

Reads <references>/<set>/focus/<screen>-<preview>.json (written by scripts/mac/, the real focus engine's
initial focus and, for every element, where each press moves focus after reaching the element along its
recorded `path`) and focus/probes/*.json (longer press sequences where history matters). For each recording
it renders the same preview with `--focus-map` and compares, matching elements by label:

  - the initial focus;
  - every recorded move (from, direction) -> target. Our moves come from our map, computed on the first
    layout. When our path to an element differs from the recorded one, or a move disagrees (the presses
    change what the static map does not see: scroll offsets, a tab selected by focus, a page switched by
    onChange), the recorded path is rendered with `--press` and the moves of the element focused at the end
    are used, so both sides have the same history (docs/FOCUS.md, "History");
  - every probe: the sequence is rendered with `--press`, and the focused element after each press compared.

Prints one line per preview and per probe (mismatches / total) and, with --verbose, every mismatch.
Exits 1 if anything mismatches. The reference set is fetched like scripts/calibrate.py does.
"""
import argparse, collections, json, os, re, subprocess, sys

def references_root():
    """Where reference captures live: on this Mac, outside the repository (they are re-captured, never committed).
    BLITR_REFERENCES overrides it."""
    return os.environ.get("BLITR_REFERENCES") or os.path.expanduser(
        "~/Library/Application Support/blitr/references")

def require_set(path, name, what):
    if not os.path.exists(path):
        sys.exit(f"no {what} for reference set {name} in {references_root()}; capture it with the scripts in scripts/mac/")

SOURCES = {"TVFocus": "Examples/TVFocus.swift", "TVControls": "Examples/TVControls.swift"}
DIRS = ["up", "down", "left", "right"]

class Renderer:
    def __init__(self, root, out, device):
        self.root, self.out, self.device = root, out, device
        # BLITR_TOOL: another build of the tool (a before/after comparison).
        self.tool = os.environ.get("BLITR_TOOL") or os.path.join(
            subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip(), "blitr")
        self.cache = {}

    def focus_map(self, source, preview, presses=None):
        key = (source, preview, presses)
        if key in self.cache:
            return self.cache[key]
        tag = re.sub(r"[^A-Za-z0-9]+", "-", f"{os.path.basename(source)}-{preview}-{presses or 'start'}")
        png, js = os.path.join(self.out, tag + ".png"), os.path.join(self.out, tag + ".json")
        cmd = [self.tool, "render", os.path.join(self.root, source), "--preview", str(preview), "-o", png,
               "--device", self.device, "--focus-map", js]
        if presses:
            cmd += ["--press", presses]
        for _ in range(3):
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode == 0:
                break
        if r.returncode != 0:
            print(f"render failed: {' '.join(cmd[2:])}: {r.stderr.strip().splitlines()[-1:]}", file=sys.stderr)
            self.cache[key] = None
            return None
        self.cache[key] = json.load(open(js))
        return self.cache[key]

def labels(doc):
    """id -> label, with duplicate labels numbered in reading order ("Movie 1", "Movie 1#2")."""
    seen = collections.Counter()
    out = {}
    for e in sorted(doc["elements"], key=lambda e: e.get("index", 0)):
        lab = e.get("label") or e["id"]
        seen[lab] += 1
        out[e["id"]] = lab if seen[lab] == 1 else f"{lab}#{seen[lab]}"
    return out

def compare_preview(rec, source, preview, renderer, verbose):
    ours = renderer.focus_map(source, preview)
    if ours is None:
        return None
    rl, ol = labels(rec), labels(ours)
    ours_by_label = {ol[e["id"]]: e for e in ours["elements"]}
    mismatches = []
    total = 0
    if rl.get(rec.get("initialFocus")) != ol.get(ours.get("initialFocus")):
        mismatches.append(("initial", "", rl.get(rec.get("initialFocus")), ol.get(ours.get("initialFocus"))))
    total += 1
    def agrees(moves, names):
        for d in DIRS:
            if d in e.get("moves", {}):
                want = rl.get(e["moves"][d]) if e["moves"][d] else None
                got = names.get(moves[d]) if moves and moves.get(d) else None
                if want != got:
                    return False
        return True

    for e in rec["elements"]:
        lab = rl[e["id"]]
        mine = ours_by_label.get(lab)
        rec_path = e.get("path")
        mine_moves, mine_labels = (mine or {}).get("moves"), ol
        same_path = mine is not None and (mine.get("path") or []) == (rec_path or [])
        if rec_path and not (same_path and agrees(mine_moves, ol)):
            # Replay the recorded path so both sides have the same history and state.
            after = renderer.focus_map(source, preview, ",".join(rec_path))
            if after is not None:
                al = labels(after)
                focused = after.get("focused")
                if al.get(focused) != lab:
                    for d in DIRS:
                        if d in e.get("moves", {}):
                            total += 1
                            mismatches.append(("path", f"{lab} via {','.join(rec_path)}", lab, al.get(focused)))
                    continue
                mine_moves, mine_labels = next(x for x in after["elements"] if x["id"] == focused).get("moves"), al
        for d in DIRS:
            if d not in e.get("moves", {}):
                continue
            total += 1
            want = rl.get(e["moves"][d]) if e["moves"][d] else None
            got = None
            if mine_moves is None:
                got = "<missing element>"
            elif mine_moves.get(d):
                got = mine_labels.get(mine_moves[d])
            if want != got:
                mismatches.append(("move", f"{lab} {d}", want, got))
    return total, mismatches

def compare_probe(probe, source, preview, renderer):
    steps = probe["steps"]
    presses = ",".join(s["press"] for s in steps if s["press"] != "launch")
    ours = renderer.focus_map(source, preview, presses)
    if ours is None:
        return None
    ol = labels(ours)
    presses_log = ours.get("presses", [])
    for p in presses_log:  # maps written before the labels were logged: read them from the note
        if "fromLabel" not in p:
            m = re.search(r'focus #\d+ (?:"(.*)"|\S+) -> #\d+ (?:"(.*)"|\S+)', p.get("note", ""))
            p["fromLabel"] = m.group(1) if m else ol.get(p.get("from"))
            p["toLabel"] = m.group(2) if m else p["fromLabel"]
    got = [presses_log[0].get("fromLabel") if presses_log else ol.get(ours.get("focused"))]
    for k, p in enumerate(presses_log):
        if p["press"] in DIRS:
            got.append(p.get("toLabel"))
        elif p.get("to") is None:
            got.append(None)  # tvOS would leave the app
        elif k + 1 < len(presses_log):
            got.append(presses_log[k + 1].get("fromLabel"))
        else:
            got.append(ol.get(ours.get("focused")))
    want = [s.get("focused") for s in steps]
    mismatches = []
    for i, (w, g) in enumerate(zip(want, got + [None] * (len(want) - len(got)))):
        if w != g:
            mismatches.append(("probe", f"step {i} ({steps[i]['press']})", w, g))
    return len(want), mismatches

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="tvos-26.5")
    ap.add_argument("--device", default="apple-tv-4k")
    ap.add_argument("--only", default=None, help="regex on the recording name")
    ap.add_argument("--out", default="out/focus")
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--json", default=None, help="write the per-preview results here")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(references_root(), args.set)
    require_set(os.path.join(base, "focus"), args.set, "focus recordings")
    out = os.path.join(root, args.out)
    os.makedirs(out, exist_ok=True)
    renderer = Renderer(root, out, args.device)
    results = {}
    grand = [0, 0]
    focus_dir = os.path.join(base, "focus")
    for name in sorted(os.listdir(focus_dir), key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", n)]):
        if not name.endswith(".json") or (args.only and not re.search(args.only, name)):
            continue
        rec = json.load(open(os.path.join(focus_dir, name)))
        source = SOURCES.get(rec["screen"])
        if source is None:
            continue
        r = compare_preview(rec, source, rec["preview"], renderer, args.verbose)
        if r is None:
            continue
        total, mism = r
        grand[0] += len(mism); grand[1] += total
        results[name] = {"preview": rec.get("previewName"), "mismatches": len(mism), "total": total,
                         "details": [list(m) for m in mism]}
        print(f"{len(mism):3d} / {total:3d}  {name[:-5]} ({rec.get('previewName')})")
        if args.verbose:
            for kind, what, want, got in mism:
                print(f"        {kind:7s} {what:32s} real: {want}  ours: {got}")
    probes = os.path.join(focus_dir, "probes")
    if os.path.isdir(probes):
        for name in sorted(os.listdir(probes)):
            if not name.endswith(".json") or (args.only and not re.search(args.only, name)):
                continue
            probe = json.load(open(os.path.join(probes, name)))
            source = SOURCES.get(probe["screen"])
            r = compare_probe(probe, source, probe["preview"], renderer) if source else None
            if r is None:
                continue
            total, mism = r
            grand[0] += len(mism); grand[1] += total
            results[name] = {"preview": probe.get("previewName"), "mismatches": len(mism), "total": total,
                             "details": [list(m) for m in mism]}
            print(f"{len(mism):3d} / {total:3d}  probe {probe['probe']} ({probe.get('previewName')})")
            if args.verbose:
                for kind, what, want, got in mism:
                    print(f"        {kind:7s} {what:32s} real: {want}  ours: {got}")
    print(f"{grand[0]} mismatches of {grand[1]} compared")
    if args.json:
        json.dump(results, open(args.json, "w"), indent=1)
    return 1 if grand[0] else 0

if __name__ == "__main__":
    sys.exit(main())
