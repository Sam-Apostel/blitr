#!/usr/bin/env python3
"""Generates the tiny pixel font bundled with the Tests/Projects fixture.

The fixture's UI package needs a font of its own to prove that fonts in a package's resources are
found by Font.custom(_:size:). Rather than copying a third-party font, this draws a 5x7 pixel
alphabet (A-Z, digits, a little punctuation; lowercase maps to the capitals) with fontTools.
The output is committed; re-run only to change the design:

    python3 scripts/make-fixture-font.py Tests/Projects/Orchard/OrchardUI/Sources/OrchardUI/Resources/OrchardPixel.ttf
"""
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "zero": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "one": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "two": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "three": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "four": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "five": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "six": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "seven": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "eight": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "nine": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "period": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "comma": ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
    "hyphen": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "colon": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "exclam": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "space": ["00000"] * 7,
}
CODEPOINTS = {"zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
              "eight": "8", "nine": "9", "period": ".", "comma": ",", "hyphen": "-", "colon": ":", "exclam": "!", "space": " "}
PIXEL = 100  # font units per pixel; 1000 units per em


def draw(rows):
    pen = TTGlyphPen(None)
    for y, row in enumerate(rows):
        for x, bit in enumerate(row):
            if bit != "1":
                continue
            left, top = x * PIXEL, (7 - y) * PIXEL
            pen.moveTo((left, top - PIXEL))
            pen.lineTo((left, top))
            pen.lineTo((left + PIXEL, top))
            pen.lineTo((left + PIXEL, top - PIXEL))
            pen.closePath()
    return pen.glyph()


def main(path):
    order = [".notdef"] + list(GLYPHS)
    cmap = {}
    for name in GLYPHS:
        char = CODEPOINTS.get(name, name)
        cmap[ord(char)] = name
        if len(name) == 1:
            cmap[ord(name.lower())] = name
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap(cmap)
    glyphs = {".notdef": draw(["11111", "10001", "10001", "10001", "10001", "10001", "11111"])}
    glyphs.update({name: draw(rows) for name, rows in GLYPHS.items()})
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (600, 0) for name in order})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({"familyName": "Orchard Pixel", "styleName": "Regular", "psName": "OrchardPixel-Regular",
                            "licenseDescription": "Part of the swift-ui-screenshot test fixtures; same licence as the repository."})
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    builder.setupPost()
    builder.save(path)


if __name__ == "__main__":
    main(sys.argv[1])
