#!/usr/bin/env python3
"""Offline map tiles (--map-tiles), used by Tests/Maps/tiles.sh.

    tiles.py make <dir>                 writes <dir>/<z>/<x>/<y>.png for zooms 3 to 8 around the test coordinates
    tiles.py check <Rect.png> <Deep.png> <Heading.png>

The tiles are a grey checkerboard with a red dot at `CENTER` and a blue dot at `OFFSET` (the coordinates of
Tests/Maps/MapTiles.swift). `check` finds the dots in the renders (made at --scale 1, 300x300) and compares their
positions with Web Mercator: the red dot at the centre, the blue one where the map rect puts it, and for the
rotated camera at the same bearing turned by the heading.
"""
import math, struct, sys, zlib, os

CENTER = (50.85, 4.35)
OFFSET = (51.10, 4.70)
WORLD = 2.0 ** 28
TILE = 64          # pixels per tile side
DOT = 2.0          # dot radius in tile pixels
SIZE = 300         # render size in points (and pixels, at --scale 1)


def map_point(lat, lon):
    """MKMapPoint of a coordinate."""
    x = (lon + 180) / 360 * WORLD
    s = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * WORLD
    return x, y


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def read_png(path):
    """8-bit RGB or RGBA, not interlaced: a list of rows of (r, g, b)."""
    data = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and color in (2, 6), (depth, color)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    bpp = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows, previous = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = previous[i]
            c = previous[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(width)])
        previous = line
    return rows


def make(directory):
    dots = [(map_point(*CENTER), (220, 0, 0)), (map_point(*OFFSET), (0, 0, 220))]
    for z in range(3, 9):
        n = 2 ** z
        span = WORLD / n
        # Tiles within 3 degrees of the centre.
        x0, y0 = map_point(CENTER[0] + 3, CENTER[1] - 3)
        x1, y1 = map_point(CENTER[0] - 3, CENTER[1] + 3)
        for tx in range(int(x0 // span), int(x1 // span) + 1):
            for ty in range(int(y0 // span), int(y1 // span) + 1):
                # One tile at zoom 8 is left out: it is drawn from its zoom 7 parent.
                ox, oy = map_point(*OFFSET)
                if z == 8 and tx == int(ox // span) and ty == int(oy // span):
                    continue
                rows = []
                for py in range(TILE):
                    row = []
                    for px in range(TILE):
                        colour = (200, 200, 200) if ((px // 16) + (py // 16)) % 2 else (235, 235, 235)
                        gx = (tx * TILE + px + 0.5) / (n * TILE) * WORLD
                        gy = (ty * TILE + py + 0.5) / (n * TILE) * WORLD
                        for (dx, dy), c in dots:
                            if math.hypot(gx - dx, gy - dy) <= DOT * span / TILE:
                                colour = c
                        row.extend(colour)
                    rows.append(row)
                os.makedirs(f"{directory}/{z}/{tx}", exist_ok=True)
                write_png(f"{directory}/{z}/{tx}/{ty}.png", TILE, TILE, rows)


def centroid(rows, test):
    xs = ys = count = 0
    for y, row in enumerate(rows):
        for x, (r, g, b) in enumerate(row):
            if test(r, g, b):
                xs += x + 0.5; ys += y + 0.5; count += 1
    return (xs / count, ys / count) if count else None


def red(r, g, b): return r > 150 and g < 80 and b < 80
def blue(r, g, b): return b > 150 and r < 80 and g < 80


def check(rect_png, deep_png, heading_png):
    failures = 0
    def expect(name, found, want, tolerance=1.5):
        nonlocal failures
        if found is None:
            print(f"FAIL {name}: dot not found"); failures += 1; return
        error = math.hypot(found[0] - want[0], found[1] - want[1])
        status = "PASS" if error <= tolerance else "FAIL"
        failures += status == "FAIL"
        print(f"{status} {name}: at ({found[0]:.1f}, {found[1]:.1f}), expected ({want[0]:.1f}, {want[1]:.1f})")
    c, o = map_point(*CENTER), map_point(*OFFSET)
    for name, path, width in (("rect", rect_png, WORLD / 90), ("deep", deep_png, WORLD / 256)):
        rows = read_png(path)
        scale = SIZE / width
        expect(f"{name}: centre dot", centroid(rows, red), (SIZE / 2, SIZE / 2))
        expect(f"{name}: offset dot", centroid(rows, blue),
               (SIZE / 2 + (o[0] - c[0]) * scale, SIZE / 2 + (o[1] - c[1]) * scale), tolerance=2.5)
    rows = read_png(heading_png)
    expect("heading: centre dot", centroid(rows, red), (SIZE / 2, SIZE / 2))
    found = centroid(rows, blue)
    if found is None:
        print("FAIL heading: offset dot not found"); failures += 1
    else:
        # A heading of 30 degrees turns the map 30 degrees anticlockwise on screen.
        north_up = math.degrees(math.atan2(o[1] - c[1], o[0] - c[0]))
        seen = math.degrees(math.atan2(found[1] - SIZE / 2, found[0] - SIZE / 2))
        error = abs((seen - (north_up - 30) + 180) % 360 - 180)
        status = "PASS" if error < 2 else "FAIL"
        failures += status == "FAIL"
        print(f"{status} heading: offset dot at bearing {seen:.1f}, expected {north_up - 30:.1f} (drawn from the zoom 7 parent)")
    return failures


if __name__ == "__main__":
    if sys.argv[1] == "make":
        make(sys.argv[2])
    else:
        sys.exit(1 if check(*sys.argv[2:5]) else 0)
