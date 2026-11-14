#!/usr/bin/env python3
"""Builds the declaration index from swift-symbolgraph-extract output.

Usage: build_index.py <out.json> <name>=<symbolgraph-dir> ...
  e.g. build_index.py index.json SwiftUI=sg/SwiftUI Swift=sg/Swift Foundation=sg/Foundation

For every module, records top-level type names and, for every member, its owner
type path, kind, argument labels (from the `name(a:_:)` title) and the
parameter type names. Nothing is read from the sources: the symbol graph of the
built module is the authority.
"""
import glob
import json
import os
import re
import sys


def type_name_of(fragments):
    """Last dotted component of the type spelled by declaration fragments (`name: type`)."""
    text = "".join(f["spelling"] for f in fragments)
    if ": " in text:
        text = text.split(": ", 1)[1]
    text = re.sub(r"(inout|some|any|@escaping|@autoclosure|@Sendable|@MainActor)\s+", "", text)
    text = re.sub(r"<.*>", "", text).rstrip("?!").strip("[]() ")
    return text.split(".")[-1]


def labels_of(title):
    m = re.match(r"^[^(]*\((.*)\)$", title)
    if not m:
        return None
    inner = m.group(1)
    return inner.split(":")[:-1] if inner else []


def main():
    out = sys.argv[1]
    index = {"modules": {}}
    for spec in sys.argv[2:]:
        mod, d = spec.split("=", 1)
        types, members, funcs = set(), [], []
        for path in glob.glob(os.path.join(d, "*.symbols.json")):
            g = json.load(open(path))
            for s in g["symbols"]:
                kind = s["kind"]["identifier"].replace("swift.", "")
                pc = s["pathComponents"]
                if kind in ("struct", "class", "enum", "protocol", "typealias", "actor", "macro"):
                    types.add(pc[-1])
                    if len(pc) > 1:
                        members.append({"owner": pc[-2], "path": pc[:-1], "name": pc[-1], "kind": kind,
                                        "labels": None, "params": []})
                    continue
                if kind == "associatedtype":
                    continue
                title = s["names"]["title"]
                name = re.sub(r"\(.*$", "", pc[-1])
                name = name.split(".")[-1] or name
                if len(pc) == 1:
                    funcs.append({"name": name, "labels": labels_of(title), "kind": kind,
                                  "params": [type_name_of(p["declarationFragments"])
                                             for p in s.get("functionSignature", {}).get("parameters", [])]})
                    continue
                params = [type_name_of(p["declarationFragments"]) for p in s.get("functionSignature", {}).get("parameters", [])]
                # resolve generic params to their constraint protocol
                cons = {c["lhs"]: c["rhs"] for c in s.get("swiftGenerics", {}).get("constraints", []) if c["kind"] == "conformance"}
                params = [cons.get(p, p) for p in params]
                members.append({"owner": pc[-2], "path": pc[:-1], "name": name, "kind": kind,
                                "labels": labels_of(title) if kind in ("method", "init", "type.method", "func.op", "subscript") else None,
                                "params": params})
        index["modules"][mod] = {"types": sorted(types), "members": members, "funcs": funcs}
        print(mod, len(types), "types", len(members), "members", len(funcs), "funcs", file=sys.stderr)
    json.dump(index, open(out, "w"))


main()
