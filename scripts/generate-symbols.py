#!/usr/bin/env python3
"""Generate Sources/SwiftUI/Symbols/SymbolData.generated.swift.

Downloads the pinned Phosphor Icons release (MIT) from the npm registry, looks up every
SF Symbol name in scripts/symbol_map.py, and writes the artwork as one compact raw string
literal that is parsed lazily at runtime. Nothing is read from disk at runtime.

    python3 scripts/generate-symbols.py [--cache DIR]

Line format of the literal (tab separated):   name <TAB> viewBoxW,viewBoxH <TAB> layer|layer|...
Layer:  F:<d>                 nonzero fill
        E:<d>                 even-odd fill
        S:<w>,<cap>,<join>:<d>  stroke (cap b/r/s, join m/r/b); stroke-only elements carry no fill
A trailing "@b" on the name marks the bold-weight outline of the same symbol.
"""
import argparse, io, math, os, re, sys, tarfile, tempfile, urllib.request
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symbol_map import MAP  # noqa: E402

PACKAGE = "@phosphor-icons/core"
VERSION = "2.1.1"
URL = f"https://registry.npmjs.org/{PACKAGE}/-/core-{VERSION}.tgz"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources/SwiftUI/Symbols/SymbolData.generated.swift")
LICENSE_OUT = os.path.join(ROOT, "Sources/SwiftUI/Symbols/LICENSE-phosphor-icons.txt")
SVG_NS = "{http://www.w3.org/2000/svg}"


# ---------------------------------------------------------------- SVG -> layers
def num(v, default=0.0):
    if v is None:
        return default
    m = re.match(r"\s*(-?[\d.]+(?:e-?\d+)?)", v)
    return float(m.group(1)) if m else default


def fmt(x):
    s = ("%.2f" % x).rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def shape_to_d(el):
    tag = el.tag.replace(SVG_NS, "")
    g = lambda k: num(el.get(k))
    if tag == "path":
        return el.get("d", "")
    if tag == "circle":
        cx, cy, r = g("cx"), g("cy"), g("r")
        return ellipse_d(cx, cy, r, r)
    if tag == "ellipse":
        return ellipse_d(g("cx"), g("cy"), g("rx"), g("ry"))
    if tag == "rect":
        x, y, w, h = g("x"), g("y"), g("width"), g("height")
        rx = num(el.get("rx"), num(el.get("ry")))
        ry = num(el.get("ry"), rx)
        if rx <= 0 and ry <= 0:
            return f"M{fmt(x)} {fmt(y)}h{fmt(w)}v{fmt(h)}h{fmt(-w)}Z"
        rx, ry = min(rx, w / 2), min(ry, h / 2)
        return (f"M{fmt(x+rx)} {fmt(y)}H{fmt(x+w-rx)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x+w)} {fmt(y+ry)}"
                f"V{fmt(y+h-ry)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x+w-rx)} {fmt(y+h)}H{fmt(x+rx)}"
                f"A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x)} {fmt(y+h-ry)}V{fmt(y+ry)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x+rx)} {fmt(y)}Z")
    if tag == "line":
        return f"M{fmt(g('x1'))} {fmt(g('y1'))}L{fmt(g('x2'))} {fmt(g('y2'))}"
    if tag in ("polyline", "polygon"):
        pts = [float(v) for v in re.findall(r"-?[\d.]+(?:e-?\d+)?", el.get("points", ""))]
        pairs = list(zip(pts[0::2], pts[1::2]))
        if not pairs:
            return ""
        d = "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pairs)
        return d + ("Z" if tag == "polygon" else "")
    return ""


def ellipse_d(cx, cy, rx, ry):
    return (f"M{fmt(cx-rx)} {fmt(cy)}A{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(cx+rx)} {fmt(cy)}"
            f"A{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(cx-rx)} {fmt(cy)}Z")


def compact_d(d):
    d = re.sub(r"\s+", " ", d.strip())
    d = re.sub(r"\s*([A-Za-z])\s*", r"\1", d)
    return d


def parse_svg(path):
    root = ET.parse(path).getroot()
    vb = [float(v) for v in (root.get("viewBox") or "0 0 24 24").replace(",", " ").split()]
    layers = []

    def walk(el, inherited):
        style = dict(inherited)
        for k in ("fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "fill-rule", "clip-rule", "opacity"):
            if el.get(k) is not None:
                style[k] = el.get(k)
        tag = el.tag.replace(SVG_NS, "")
        if tag in ("defs", "clipPath", "mask", "title", "desc"):
            return
        if tag in ("path", "circle", "ellipse", "rect", "line", "polyline", "polygon"):
            if num(style.get("opacity"), 1) < 0.5:
                return
            d = compact_d(shape_to_d(el))
            if d:
                fill = style.get("fill", "black")
                stroke = style.get("stroke", "none")
                if fill != "none":
                    even = style.get("fill-rule", style.get("clip-rule")) == "evenodd"
                    layers.append(("E" if even else "F", d))
                if stroke != "none":
                    cap = {"butt": "b", "round": "r", "square": "s"}.get(style.get("stroke-linecap", "butt"), "b")
                    join = {"miter": "m", "round": "r", "bevel": "b"}.get(style.get("stroke-linejoin", "miter"), "m")
                    layers.append((f"S{fmt(num(style.get('stroke-width'), 1))},{cap},{join}", d))
        for child in el:
            walk(child, style)

    walk(root, {})
    return vb, layers


def encode(name, vb, layers):
    body = "|".join(f"{k}:{d}" if k in "FE" else f"{k}:{d}" for k, d in layers)
    return f"{name}\t{fmt(vb[2])},{fmt(vb[3])}\t{body}"


# ---------------------------------------------------------------- main
def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    tgz = os.path.join(cache, f"phosphor-core-{VERSION}.tgz")
    if not os.path.exists(tgz):
        print("downloading", URL, file=sys.stderr)
        with urllib.request.urlopen(URL) as r, open(tgz, "wb") as f:
            f.write(r.read())
    out = os.path.join(cache, f"phosphor-{VERSION}")
    if not os.path.isdir(out):
        os.makedirs(out)
        with tarfile.open(tgz) as t:
            t.extractall(out, filter="data")
    return os.path.join(out, "package")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "swiftui-symbol-cache"))
    args = ap.parse_args()
    pkg = fetch(args.cache)
    assets = os.path.join(pkg, "assets")

    def icon(weight, name):
        suffix = "" if weight == "regular" else f"-{weight}"
        p = os.path.join(assets, weight, f"{name}{suffix}.svg")
        return p if os.path.exists(p) else None

    lines, missing = [], []
    for sf in sorted(MAP):
        target = MAP[sf]
        fill_name = None
        if isinstance(target, tuple):
            target, fill_name = target
        else:
            fill_name = target
        reg = icon("regular", target)
        if not reg:
            missing.append((sf, target))
            continue
        vb, layers = parse_svg(reg)
        lines.append(encode(sf, vb, layers))
        bold = icon("bold", target)
        if bold:
            vbb, lb = parse_svg(bold)
            lines.append(encode(sf + "@b", vbb, lb))
        if fill_name:
            fp = icon("fill", fill_name)
            if fp:
                vbf, lf = parse_svg(fp)
                lines.append(encode(sf + ".fill", vbf, lf))
    for sf, t in missing:
        print(f"warning: {sf} -> {t}: no such Phosphor icon", file=sys.stderr)

    data = "\n".join(lines)
    assert '"""' not in data
    swift = (
        "// GENERATED by scripts/generate-symbols.py -- do not edit.\n"
        f"// Artwork: {PACKAGE} {VERSION} (MIT, see LICENSE-phosphor-icons.txt), stand-ins for SF Symbols.\n"
        "// Format: see the header of scripts/generate-symbols.py.\n\n"
        "enum SymbolData {\n"
        f"    static let iconSet = \"Phosphor Icons {VERSION}\"\n"
        f"    static let count = {len(lines)}\n"
        '    static let source = #"""\n' + data + '\n"""#\n}\n'
    )
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(swift)
    with open(os.path.join(pkg, "LICENSE")) as src, open(LICENSE_OUT, "w") as dst:
        dst.write(f"Phosphor Icons {VERSION} ({PACKAGE})\nhttps://github.com/phosphor-icons/core\n\n" + src.read())
    names = {l.split("\t")[0] for l in lines if "@b" not in l.split("\t")[0]}
    print(f"wrote {OUT}: {len(names)} names ({len(lines)} entries incl. bold), {len(data)//1024} KiB", file=sys.stderr)


if __name__ == "__main__":
    main()
