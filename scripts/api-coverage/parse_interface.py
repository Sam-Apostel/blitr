#!/usr/bin/env python3
"""Parses SwiftUI.swiftinterface into call signatures (labels, defaults, closure-ness).

Usage: parse_interface.py <SwiftUI.swiftinterface> <sigs.json>

A symbol graph does not say which parameters have default values; the module interface
does (`width: CGFloat? = nil`), and that decides whether a call with fewer labels still
matches an overload.
"""
import json
import re
import sys


def strip_mods(s):
    return re.sub(r"\b\w+::", "", s)


def split_top(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([<{":
            depth += 1
        elif ch in ")]>}":
            depth -= 1 if not (ch == ">" and cur.endswith("-")) else 0
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


def balanced(s, start):
    """Index just past the ')' matching the '(' at s[start]."""
    depth = 0
    for i in range(start, len(s)):
        c = s[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(s)


def parse_params(text):
    out = []
    for p in split_top(text):
        p = p.strip()
        default = None
        # default value: top-level ' = '
        depth = 0
        for i, ch in enumerate(p):
            if ch in "([<{":
                depth += 1
            elif ch in ")]>}":
                if not (ch == ">" and p[i - 1:i] == "-"):
                    depth -= 1
            elif ch == "=" and depth == 0 and p[i - 1:i] == " ":
                default = p[i + 1:].strip()
                p = p[:i].strip()
                break
        m = re.match(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(\w+)\s+)?(\w+)\s*:\s*(.*)$", p, re.S)
        if not m:
            continue
        a, b, ty = m.groups()
        label = a if a else b
        out.append(dict(label="" if label == "_" else label, default=default is not None or ty.endswith("..."),
                        closure="->" in ty))
    return out


def main():
    src = open(sys.argv[1]).read().split("\n")
    stack = []   # (indent, owner)
    sigs = []
    for line in src:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        while stack and stack[-1][0] >= indent and line.strip().startswith("}"):
            stack.pop()
            break
        t = strip_mods(line.strip())
        m = re.match(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|open\s+|package\s+)?(?:final\s+)?(struct|class|enum|protocol|extension|actor)\s+([\w.]+)", t)
        if m and t.endswith("{"):
            stack.append((indent, m.group(2).split(".")[-1]))
            continue
        if t.startswith("}"):
            continue
        m = re.search(r"\b(func|init)\b\s*(\w+|[^\s(]*)?\s*(?:<[^(]*>)?\s*\(", t)
        if m and "public" in t.split(m.group(1))[0] + "public" and stack:
            kind = m.group(1)
            name = "init" if kind == "init" else m.group(2)
            # find '(' of the parameter list
            open_idx = t.index("(", m.start())
            if kind == "func":
                # skip generic clause
                gm = re.search(r"\bfunc\s+[^\s(<]+\s*(<.*?>)?\s*\(", t)
                open_idx = gm.end() - 1 if gm else open_idx
            else:
                gm = re.search(r"\binit\??\s*(<.*?>)?\s*\(", t)
                open_idx = gm.end() - 1 if gm else open_idx
            end = balanced(t, open_idx)
            sigs.append(dict(owner=stack[-1][1], name=name, kind=kind, params=parse_params(t[open_idx + 1:end - 1]),
                             static="static " in t.split(kind)[0]))
    json.dump(sigs, open(sys.argv[2], "w"))
    print(len(sigs), "signatures", file=sys.stderr)


main()
