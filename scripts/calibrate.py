#!/usr/bin/env python3
"""Render every screen that has a simulator reference and compare the two.

    scripts/calibrate.py [--ios 27.0] [--device iphone-16] [--scheme light] [--only REGEX] [--out out/cal]
    scripts/calibrate.py --platform tvos --device apple-tv-4k --set tvos-26.5 [--scheme dark]
    scripts/calibrate.py --platform watchos --device apple-watch-ultra-2 --set watchos-26.5

Reads <references>/<set>/manifest.json (written by scripts/mac/capture-references.sh; the set is
ios-<version> by default), renders each listed preview with the renderer at the same OS version, device
and scheme, then runs `swiftui-screenshot compare` on the two directories. For tvOS sets the manifest's
press variants (`<screen>-<preview>-<presses>.png`, the state after those Siri Remote presses) are rendered
with `--press`, or with `--focus` where FOCUS_VARIANTS names the element the presses land on, so the
look is compared independently of the focus engine. tvOS images are 2 px/pt and have no status bar. watchOS
images are 2 px/pt too, and the watch's clock is masked: the simulator draws the real time there, because
watchOS refuses the status bar override. Prints one line per screen, worst first, and
leaves heatmaps, side-by-side images and report.json under <out>/<scheme>/compare.

Reference captures live on this Mac, outside the repository (references_root(), default
~/Library/Application Support/swiftui-screenshot/references); they are re-captured, never committed.

Renders use the time zone the set was captured in (dates and times on screen): the device's
`simulatorTimeZone` in the manifest, else a manifest-level `timeZone`, else Europe/Brussels, where the sets
recorded before the field existed (tvos-26.5) were captured. `--time-zone` overrides it.

Use Apple's fonts (scripts/fetch-apple-fonts.sh) and, if you have one, the SF Symbols name map,
so that font and symbol differences do not drown out layout differences.
"""
import argparse, concurrent.futures, json, os, re, subprocess, sys

def references_root():
    """Where reference captures live: on this Mac, outside the repository (they are re-captured, never committed).
    SWIFTUI_SCREENSHOT_REFERENCES overrides it."""
    return os.environ.get("SWIFTUI_SCREENSHOT_REFERENCES") or os.path.expanduser(
        "~/Library/Application Support/swiftui-screenshot/references")

def require_set(path, name, what):
    if not os.path.exists(path):
        sys.exit(f"no {what} for reference set {name} in {references_root()}; capture it with the scripts in scripts/mac/")

# Time zone of reference sets that record none (scripts/mac/*capture* write `simulatorTimeZone` per device).
DEFAULT_TIME_ZONE = "Europe/Brussels"

# Press variants rendered with --focus instead of --press: the element the presses land on.
FOCUS_VARIANTS = {"TVControls-0-right-right": "Prominent"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ios", default=None, help="OS version (default 27.0, or the set's version)")
    ap.add_argument("--platform", default="ios", choices=["ios", "tvos", "watchos"])
    ap.add_argument("--set", default=None, help="reference set (default <platform>-<version>)")
    ap.add_argument("--device", default=None, help="default iphone-16, apple-tv-4k on tvOS, apple-watch-series-10-46mm on watchOS")
    ap.add_argument("--scheme", default="light")
    ap.add_argument("--only", default=None, help="regex on the screen key")
    ap.add_argument("--out", default="out/cal")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--no-render", action="store_true", help="reuse renders from a previous run")
    ap.add_argument("--time-zone", default=None, help="IANA time zone to render in (default: the set's)")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tvos = args.platform == "tvos"
    watchos = args.platform == "watchos"
    if args.device is None:
        args.device = {"tvos": "apple-tv-4k", "watchos": "apple-watch-series-10-46mm"}.get(args.platform, "iphone-16")
    if args.set is None:
        args.set = f"{args.platform}-{args.ios or ('26.5' if tvos or watchos else '27.0')}"
    if args.ios is None:
        args.ios = args.set.split("-", 1)[1]
    scale = "2" if tvos or watchos else "3"
    ref_root = os.path.join(references_root(), args.set)
    require_set(os.path.join(ref_root, "manifest.json"), args.set, "manifest.json")
    manifest = json.load(open(os.path.join(ref_root, "manifest.json")))
    ref_dir = os.path.join(ref_root, args.device, args.scheme)
    bin_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip()
    tool = os.path.join(bin_dir, "swiftui-screenshot")
    out = os.path.join(root, args.out, args.scheme)
    ours = os.path.join(out, "ours")
    os.makedirs(ours, exist_ok=True)
    major = args.ios.split(".")[0]
    time_zone = (args.time_zone or manifest.get("devices", {}).get(args.device, {}).get("simulatorTimeZone")
                 or manifest.get("timeZone") or DEFAULT_TIME_ZONE)

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
            jobs.append((name, screen["source"], preview["index"], None))
            for variant in manifest.get("devices", {}).get(args.device, {}).get("pressVariants", []):
                if variant["screen"] != key or variant["preview"] != preview.get("name"):
                    continue
                vname = name + "-" + variant["presses"].replace(",", "-")
                if os.path.exists(os.path.join(ref_dir, vname + ".png")):
                    jobs.append((vname, screen["source"], preview["index"], variant["presses"]))

    def render(job):
        name, source, index, presses = job
        png = os.path.join(ours, name + ".png")
        cmd = [tool, "render", os.path.join(root, source), "--preview", str(index), "-o", png,
               "--ios", major, "--device", args.device, "--scheme", args.scheme, "--scale", scale, "--time-zone", time_zone,
               "--accessibility-tree", os.path.join(ours, name + ".json")]
        if tvos:
            cmd += ["--platform", "tvos"]
        if presses and name in FOCUS_VARIANTS:
            cmd += ["--focus", FOCUS_VARIANTS[name]]
        elif presses:
            cmd += ["--press", presses]
        # Parallel renders of one source share its compile cache and can collide; retry those.
        for _ in range(3):
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode == 0:
                break
        return name, r.returncode, r.stderr.strip().splitlines()[-1:] if r.returncode else []

    if not args.no_render:
        for job in jobs:
            for stale in (".png", ".json"):
                if os.path.exists(os.path.join(ours, job[0] + stale)):
                    os.remove(os.path.join(ours, job[0] + stale))
        # The first render of each source compiles it; the others reuse that build, so run them after it.
        first = {}
        for job in jobs:
            first.setdefault(job[1], job)
        rest = [j for j in jobs if first[j[1]] is not j]
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            for batch in (list(first.values()), rest):
                for name, code, err in pool.map(render, batch):
                    if code != 0:
                        print(f"render failed: {name}: {' '.join(err)}", file=sys.stderr)

    # Compare only the files both sides have.
    names = [n for n, _, _, _ in jobs if os.path.exists(os.path.join(ours, n + ".png"))]
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
    cmp = [tool, "compare", ref_sel, ours, "--out-dir", cmp_out, "--scale", scale]
    if tvos or watchos:
        cmp += ["--status-bar", "0", "--home-indicator", "0"]
    if watchos and names:
        # The clock in the top trailing corner shows the time of the capture, not a fixed one: leave it out.
        with open(os.path.join(ours, names[0] + ".json")) as f:
            width = json.load(f)["size"]["width"]
        cmp += ["--mask", f"{width - 90},8,90,36"]
    r = subprocess.run(cmp, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    return r.returncode

if __name__ == "__main__":
    sys.exit(main())
