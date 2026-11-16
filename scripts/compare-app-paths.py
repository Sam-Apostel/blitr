#!/usr/bin/env python3
"""Compare the renderer's remote navigation in an app with press sequences recorded on the tvOS simulator.

    scripts/compare-app-paths.py <recordings dir> [--only REGEX] [--out DIR] [--verbose] -- <render options>

<recordings dir> holds what scripts/mac/tvos/record-app.sh wrote: <name>.json per press sequence, with the
focused element after every press. For each one the app is rendered once with the same presses
(`render <render options> --press <presses> --focus-map ...`), and the element focus is on after every press
is compared with the recorded one. Elements match when one label contains the other (case and punctuation
ignored; tvOS leaves images out of a button's label where we may not), or else when their frames' centres are
within 40 pt. Prints one line per sequence (mismatches / steps) and, with --verbose, every step.
The render options are passed through, for example:

    scripts/compare-app-paths.py "$REFS/tvos-26.5-myapp" -- --project App/project.yml --target AppTV \\
        --view "RootView()" --env USE_SAMPLE_DATA=1
Writes <out>/<name>.png (our last frame) and <name>.json (our focus map).
"""
import argparse, json, os, re, subprocess, sys

DIRS = {"up", "down", "left", "right"}

def norm(label):
    return re.sub(r"[^0-9a-z]+", " ", (label or "").lower()).strip()

def same(want, got):
    """want, got: {label, frame} or None."""
    if not want or not want.get("label"):
        return not got or not got.get("label")
    if not got:
        return False
    a, b = norm(want.get("label")), norm(got.get("label"))
    if a and b and (a in b or b in a):
        return True
    wf, gf = want.get("frame"), got.get("frame")
    if wf and gf:
        wc = (wf[0] + wf[2] / 2, wf[1] + wf[3] / 2)
        gc = (gf[0] + gf[2] / 2, gf[1] + gf[3] / 2)
        return abs(wc[0] - gc[0]) <= 40 and abs(wc[1] - gc[1]) <= 40
    return False

def ours_after_each(doc):
    """The focused element after launch and after each press, from the focus map's press log."""
    elements = {e["id"]: e for e in doc.get("elements", [])}
    def el(eid, label=None):
        if eid is None:
            return None
        e = elements.get(eid)
        return {"label": label if label is not None else (e or {}).get("label"), "frame": (e or {}).get("frame")}
    log = doc.get("presses", [])
    steps = [el(log[0]["from"], log[0].get("fromLabel")) if log else el(doc.get("focused"))]
    for k, p in enumerate(log):
        if p["press"] in DIRS:
            steps.append(el(p.get("to") or p.get("from"), p.get("toLabel") or p.get("fromLabel")))
        elif p.get("to") is None and p.get("from") is not None:
            steps.append(None)  # menu with nothing to go back to: tvOS leaves the app
        elif k + 1 < len(log):
            steps.append(el(log[k + 1].get("from"), log[k + 1].get("fromLabel")))
        else:
            steps.append(el(doc.get("focused")))
    # Elements of the final screen carry frames; earlier ones only labels (their screen may be gone).
    return steps

def main():
    argv = sys.argv[1:]
    render_options = []
    if "--" in argv:
        i = argv.index("--")
        argv, render_options = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("recordings")
    ap.add_argument("--only")
    ap.add_argument("--out", default="out/app-paths")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args(argv)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tool = os.environ.get("BLITR_TOOL") or os.path.join(
        subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip(), "blitr")
    os.makedirs(args.out, exist_ok=True)
    grand = [0, 0]
    for name in sorted(os.listdir(args.recordings)):
        if not name.endswith(".json") or (args.only and not re.search(args.only, name)):
            continue
        rec = json.load(open(os.path.join(args.recordings, name)))
        if "steps" not in rec:
            continue
        stem = name[:-5]
        presses = ",".join(rec.get("presses", []))
        png, js = os.path.join(args.out, stem + ".png"), os.path.join(args.out, stem + ".json")
        cmd = [tool, "render", *render_options, "-o", png, "--focus-map", js]
        if presses:
            cmd += ["--press", presses]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"render failed for {stem}: {r.stderr.strip().splitlines()[-3:]}")
            continue
        ours = ours_after_each(json.load(open(js)))
        want = [s.get("focused") or None for s in rec["steps"]]
        bad = 0
        lines = []
        for i, w in enumerate(want):
            g = ours[i] if i < len(ours) else None
            ok = same(w, g)
            bad += not ok
            press = rec["steps"][i]["press"]
            lines.append(f"      {'  ' if ok else '!!'} {i:2d} {press:7s} real: {(w or {}).get('label', '-')!s:48.48s} ours: {(g or {}).get('label', '-')!s:.48s}")
        grand[0] += bad; grand[1] += len(want)
        print(f"{bad:3d} / {len(want):3d}  {stem}  [{presses}]")
        if args.verbose or bad:
            print("\n".join(lines))
    print(f"{grand[0]:3d} / {grand[1]:3d}  total")
    sys.exit(1 if grand[0] else 0)

if __name__ == "__main__":
    main()
