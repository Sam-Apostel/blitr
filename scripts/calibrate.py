#!/usr/bin/env python3
"""Render every screen that has a simulator reference and compare the two.

    scripts/calibrate.py [--ios 27.0] [--device iphone-16] [--scheme light] [--only REGEX] [--out out/cal]

Reads Tests/Reference/ios-<version>/manifest.json (written by scripts/mac/capture-references.sh),
renders each listed preview with the renderer at the same OS version, device and scheme, then runs
`swiftui-screenshot compare` on the two directories. Prints one line per screen, worst first, and
leaves heatmaps, side-by-side images and report.json under <out>/<scheme>/compare.

Use Apple's fonts (scripts/fetch-apple-fonts.sh) and, if you have one, the SF Symbols name map,
so that font and symbol differences do not drown out layout differences.
"""
import argparse, concurrent.futures, json, os, re, subprocess, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ios", default="27.0")
    ap.add_argument("--device", default="iphone-16")
    ap.add_argument("--scheme", default="light")
    ap.add_argument("--only", default=None, help="regex on the screen key")
    ap.add_argument("--out", default="out/cal")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--no-render", action="store_true", help="reuse renders from a previous run")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ref_root = os.path.join(root, "Tests", "Reference", f"ios-{args.ios}")
    manifest = json.load(open(os.path.join(ref_root, "manifest.json")))
    ref_dir = os.path.join(ref_root, args.device, args.scheme)
    bin_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip()
    tool = os.path.join(bin_dir, "swiftui-screenshot")
    out = os.path.join(root, args.out, args.scheme)
    ours = os.path.join(out, "ours")
    os.makedirs(ours, exist_ok=True)
    major = args.ios.split(".")[0]

    jobs = []
    for screen in manifest["screens"]:
        key = screen["key"]
        if screen.get("skipped") or (args.only and not re.search(args.only, key)):
            continue
        for preview in screen.get("previews", []):
            if preview.get("skipped"):
                continue
            name = f"{key}-{preview['index']}"
            if not os.path.exists(os.path.join(ref_dir, name + ".png")):
                continue
            jobs.append((name, screen["source"], preview["index"]))

    def render(job):
        name, source, index = job
        png = os.path.join(ours, name + ".png")
        cmd = [tool, "render", os.path.join(root, source), "--preview", str(index), "-o", png,
               "--ios", major, "--device", args.device, "--scheme", args.scheme, "--scale", "3",
               "--accessibility-tree", os.path.join(ours, name + ".json")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        return name, r.returncode, r.stderr.strip().splitlines()[-1:] if r.returncode else []

    if not args.no_render:
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            for name, code, err in pool.map(render, jobs):
                if code != 0:
                    print(f"render failed: {name}: {' '.join(err)}", file=sys.stderr)

    # Compare only the files both sides have.
    names = [n for n, _, _ in jobs if os.path.exists(os.path.join(ours, n + ".png"))]
    ref_sel = os.path.join(out, "reference")
    os.makedirs(ref_sel, exist_ok=True)
    for stale in os.listdir(ref_sel):
        os.remove(os.path.join(ref_sel, stale))
    for n in names:
        for ext in (".png", ".json"):
            src = os.path.join(ref_dir, n + ext)
            if os.path.exists(src):
                os.symlink(src, os.path.join(ref_sel, n + ext))
    for stale in os.listdir(ours):
        if os.path.splitext(stale)[0] not in names:
            os.remove(os.path.join(ours, stale))
    cmp_out = os.path.join(out, "compare")
    r = subprocess.run([tool, "compare", ref_sel, ours, "--out-dir", cmp_out, "--scale", "3"],
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    return r.returncode

if __name__ == "__main__":
    sys.exit(main())
