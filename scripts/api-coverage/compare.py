#!/usr/bin/env python3
"""Compares extracted usage with the declaration index of our SwiftUI module.

Usage: compare.py <index.json> <out.json> [--private repo1,repo2] <usage.json>...

Every site is assigned one status:
  covered     name (and, for calls, a label sequence) found in our SwiftUI module
  label_gap   the name exists but no overload accepts these labels
  candidate   unknown to our module, not app-defined, not stdlib/Foundation: a possible gap
              (confirmed or refuted later by compiling a snippet: confirm.py)
  app         defined by the app itself (types, extensions, modifiers)
  other       belongs to another framework (see frameworks.json + import evidence)
  ignored     not SwiftUI (stdlib/Foundation/Dispatch, unattributable local calls)

Label matching is an ordered-subsequence test against every declared overload with the
same name (defaults are not visible in a symbol graph), so `covered` is an upper bound;
confirm.py compiles the top candidates to correct it.
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
FW = json.load(open(os.path.join(HERE, "frameworks.json")))
APPLE_MODULES = set(FW["apple_modules"])
ALWAYS_SWIFTUI = set(FW.get("swiftui_names", []))
FW_NAMES = FW["names"]                      # exact name -> framework
FW_PREFIX = [(p, f) for p, f in FW["prefixes"]]
VIEWLIKE_PROTOCOLS = {"View", "ViewModifier", "Shape", "InsettableShape", "Scene", "App", "Widget",
                      "ButtonStyle", "PrimitiveButtonStyle", "ToggleStyle", "LabelStyle", "ShapeStyle",
                      "UIViewRepresentable", "NSViewRepresentable", "WKInterfaceObjectRepresentable"}


def load_index(path):
    idx = json.load(open(path))["modules"]
    sui = idx["SwiftUI"]
    t = {
        "sui_types": set(sui["types"]),
        "sui_by_name": defaultdict(list),
        "sui_funcs": {f["name"] for f in sui["funcs"]},
        "sui_member_names": set(),
        "obs": set(idx["Observation"]["types"]),
    }
    for m in sui["members"]:
        t["sui_by_name"][m["name"]].append(m)
    for m in sui["members"]:
        t["sui_member_names"].add(m["name"])
    std_types, std_members = set(), set()
    for mod in ("Swift", "Foundation", "FoundationEssentials", "FoundationInternationalization", "FoundationNetworking", "Dispatch", "Combine"):
        std_types |= set(idx[mod]["types"])
        std_members |= {m["name"] for m in idx[mod]["members"]}
        std_members |= {f["name"] for f in idx[mod]["funcs"]}
    t["std_types"], t["std_members"] = std_types, std_members
    t["sigs"] = defaultdict(list)
    sp = os.path.join(os.path.dirname(path), "sigs.json")
    for sg in json.load(open(sp)) if os.path.exists(sp) else []:
        t["sigs"][sg["name"]].append(sg)
    return t


def labels_match(call, params):
    """Exact label match of a call against a parsed signature (params: label/default/closure).

    Call labels use '_' for unlabeled and '_{}' for an unlabeled (trailing) closure, which
    may fill any closure-typed parameter. Skipped parameters must have defaults."""
    n, m = len(call), len(params)

    def rec(i, j):
        if i == n:
            return all(p["default"] for p in params[j:])
        c = call[i]
        for k in range(j, m):
            p = params[k]
            if c == "_{}":
                ok = p["closure"]
            else:
                ok = (c == "_" and p["label"] == "") or c == p["label"]
            if ok and rec(i + 1, k + 1):
                return True
            if not p["default"]:
                return False   # cannot skip a required parameter
        return False
    return rec(0, 0)


def sig_match(call, sigs):
    return any(labels_match(call, s["params"]) for s in sigs)


SHIM = FW.get("shim_names", {})


def fw_of(name):
    if name in FW_NAMES:
        return FW_NAMES[name]
    for p, f in FW_PREFIX:
        if name.startswith(p) and len(name) > len(p) and name[len(p)].isupper():
            return f
    return None


def fw_mod(name):
    if name in FW.get("mod_names", {}):
        return FW["mod_names"][name]
    for p, f in FW.get("mod_prefixes", []):
        if name.startswith(p) and len(name) > len(p) and name[len(p)].isupper():
            return f
    return None


def path_platform(rel, repo, plats):
    p = rel.lower()
    if "tvos" in p or re.search(r"(^|[/ _-])tv([/ _-]|$)", p):
        return "tvos"
    if "watch" in p:
        return "watchos"
    if "macos" in p or re.search(r"(^|[/ _-])mac([/ _-]|$)", p) or "appkit" in p:
        return "macos"
    if len(plats) == 1:
        return plats[0]
    return "shared"


def main():
    argv = sys.argv[1:]
    index_path, out = argv[0], argv[1]
    argv = argv[2:]
    private = set()
    if argv and argv[0] == "--private":
        private = set(argv[1].split(","))
        argv = argv[2:]
    T = load_index(index_path)
    grp = lambda repo: "PRIVATE" if repo in private else repo
    files = {}
    for u in argv:
        files.update(json.load(open(u)))

    # app-defined names per repo
    app_decl, app_view_types = defaultdict(set), defaultdict(set)
    for f, r in files.items():
        app_decl[grp(r["repo"])] |= set(r["decls"])
    for f, r in files.items():
        pass
    app_conf = defaultdict(set)
    for f, r in files.items():
        app_conf[grp(r["repo"])] |= set(r["conforms"])

    # pass 1: which unknown modifier names have view-rooted evidence
    evidence = Counter()
    for f, r in files.items():
        for k, n in r["sites"].items():
            kind, name, labels, ctx = k.split("|", 3)
            if kind == "mod" and ctx.split(":")[0] in ("ctor", "type", "member"):
                root = ctx.split(":", 1)[1]
                if root in T["sui_types"] or (root in app_decl[grp(r["repo"])] and root not in T["std_types"]) or (
                        root not in T["std_types"] and fw_of(root) is None):
                    evidence[name] += n

    sites = []   # (api_display, status, kind, repo, plat, count, file, detail)
    for f, r in files.items():
        repo, plats = r["repo"], r.get("plats", ["ios"])
        plat = path_platform(r["rel"], repo, plats)
        decl = app_decl[grp(repo)]
        imports = r["imports"]
        for k, n in r["sites"].items():
            kind, name, labels, ctx = k.split("|", 3)
            L = labels.split(",") if labels else []
            res = classify(T, decl, evidence, kind, name, L, ctx)
            if res is None:
                continue
            api, status, extra = res
            sites.append((api, status, kind, repo, plat, n, f, extra, tuple(imports)))
        for c in r["conforms"]:
            c0 = c.split(".")[-1]
            if c0 in T["sui_types"]:
                sites.append((f"conformance: {c0}", "covered", "conform", repo, plat, 1, f, "", tuple(imports)))
            elif c0 in VIEWLIKE_PROTOCOLS or (c0 not in T["std_types"] and c0 not in decl and fw_of(c0) is None and c0[:1].isupper() and c0 in ALWAYS_SWIFTUI):
                sites.append((f"conformance: {c0}", "candidate", "conform", repo, plat, 1, f, "", tuple(imports)))

    # aggregate
    agg = {}
    for api, status, kind, repo, plat, n, f, extra, imports in sites:
        key = (api, status)
        a = agg.setdefault(key, dict(api=api, status=status, kind=kind, sites=0, repos=Counter(), files=set(),
                                     plats=Counter(), imports=Counter(), extra=Counter(), dirs=Counter()))
        a["sites"] += n
        a["repos"][repo] += n
        a["files"].add(f)
        a["plats"][plat] += n
        a["extra"][extra] += n
        for i in set(imports):
            a["imports"][i] += 1
        a["dirs"][f.rsplit("/", 1)[0] if "/" in f else f] += n
    rows = []
    for a in agg.values():
        a["files"] = sorted(a["files"])
        for k in ("repos", "plats", "imports", "extra", "dirs"):
            a[k] = dict(a[k])
        if a["status"] == "candidate":
            # names used (almost) only in files that import a third-party module belong to it
            tp = {m: c for m, c in a["imports"].items() if m not in APPLE_MODULES}
            if tp:
                m, c = max(tp.items(), key=lambda kv: kv[1])
                if c / len(a["files"]) >= 0.9 and len(a["files"]) >= 2 and a["kind"] in ("type", "init", "attr", "macro", "static", "scall", "conform"):
                    a["status"] = "other:3p:" + m
        rows.append(a)
    json.dump(dict(rows=rows, private=sorted(private), repos=sorted({r["repo"] for r in files.values()}),
                   loc=sum(r["lines"] for r in files.values())), open(out, "w"))
    tot = Counter()
    for a in rows:
        tot[a["status"]] += a["sites"]
    print(dict(tot), file=sys.stderr)


def classify(T, decl, evidence, kind, name, L, ctx):
    sui_t, by = T["sui_types"], T["sui_by_name"]
    if kind == "init":
        base = name
        if name in decl:
            return name, "app", ""
        if name in sui_t:
            sg = [x for x in T["sigs"].get("init", []) if x["owner"] == name]
            sigtxt = "init(" + "".join(("_" if l in ("_", "_{}") else l) + ":" for l in L) + ")"
            if not sg or sig_match(L, sg):
                return f"{name}(...)", "covered", ""
            if sigtxt in decl:
                return None   # the app declares this initializer itself (extension)
            return f"{name}({''.join(('_' if l in ('_', '_{}') else l) + ':' for l in L)})", "label_gap", ""
        if name in T["std_types"]:
            return None
        fw = fw_of(name)
        if fw:
            return f"{name}(...)", "other:" + fw, ""
        if name in T["obs"]:
            return None
        return f"{name}(...)", "candidate", "type"
    if kind == "type":
        if name in decl or name in T["std_types"]:
            return None
        if name in sui_t:
            return f"type {name}", "covered", ""
        if name in T["obs"]:
            return None
        fw = fw_of(name)
        if fw:
            return f"type {name}", "other:" + fw, ""
        if name in ("Self", "Content", "Label", "Value", "Body", "T", "Element", "ID"):
            return None
        return f"type {name}", "candidate", "type"
    if kind == "mod":
        if name in decl:
            return None if name not in by else (f".{name}(...)", "covered", "")
        rk = ctx.split(":")[0]
        if name in by:
            sg = [x for x in T["sigs"].get(name, []) if x["kind"] == "func"]
            if not sg:
                return None
            lab = "".join(("_" if l in ("_", "_{}") else l) + ":" for l in L)
            if sig_match(L, sg):
                return f".{name}(...)", "covered", ""
            return f".{name}({lab})", "label_gap", ""
        if name in T["std_members"]:
            return None
        if evidence.get(name, 0) == 0:
            return None
        lab = "".join(("_" if l in ("_", "_{}") else l) + ":" for l in L)
        fw = fw_mod(name)
        if fw:
            return f".{name}({lab})", "other:" + fw, rk
        return f".{name}({lab})", "candidate", rk
    if kind == "scall" or kind == "static":
        ty, _, mem = name.rpartition(".")
        top = ty.split(".")[0]
        if top in decl or ty in decl:
            return None
        if top in T["std_types"] and top not in sui_t:
            return None
        if top in sui_t or ty.split(".")[-1] in sui_t:
            tail = ty.split(".")[-1]
            ms = [m for m in by.get(mem, []) if m["owner"] == tail or tail in m["path"]]
            if ms:
                if kind == "scall":
                    sg = [x for x in T["sigs"].get(mem, []) if x["owner"] == tail or (mem == "init" and x["owner"] == tail)]
                    if not sg or sig_match(L, sg):
                        return f"{ty}.{mem}(...)", "covered", ""
                    return f"{ty}.{mem}({''.join(('_' if l in ('_', '_{}') else l) + ':' for l in L)})", "label_gap", ""
                return f"{ty}.{mem}", "covered", ""
            if mem[:1].isupper() and mem in sui_t:
                return f"{ty}.{mem}", "covered", ""
            if mem in ("self", "init", "none") or mem in decl:
                return None
            return (f"{ty}.{mem}" + ("(...)" if kind == "scall" else ""), "candidate", "static")
        fw = fw_of(top)
        if fw:
            return f"{ty}.{mem}", "other:" + fw, ""
        return None
    if kind in ("imember", "imcall"):
        mem = name
        if mem in decl:
            return None
        fname, _, rest = ctx.partition("(")
        lab = rest.rstrip(":)") if rest else ""
        # only count when the receiving API is SwiftUI (known to us) or a gap candidate
        recv = by.get(fname, []) if fname else []
        recv_known = bool(recv) or fname in sui_t or fname in T["sui_funcs"]
        recv_gap = fname and (evidence.get(fname, 0) > 0) and fname not in T["std_members"]
        if not (recv_known or recv_gap):
            return None
        if fname in T["std_members"] and not any(m["owner"] == "View" for m in recv):
            return None
        if fname in ("Image", "Color") and not by.get(mem):
            # `Image(.name)` / `Color(.name)`: generated asset-catalog symbols, or NSColor/UIColor members
            if mem.endswith("Color") or mem in ("label", "separator", "link"):
                return f"{fname}(_:) .{mem}", "other:UIKit/AppKit colors", ""
            return None
        if "uiImage" in lab or "nsImage" in lab or "uiColor" in lab or "nsColor" in lab or fname == "ColorPicker_":
            return f"{fname}({lab}:) .{mem}", "other:UIKit/AppKit", ""
        if mem in ("init", "none", "some", "zero", "infinity", "self", "default", "main", "current", "shared", "standard", "allCases", "max", "min", "leastNonzeroMagnitude"):
            if mem not in by:
                return None
        exists = [m for m in by.get(mem, [])]
        if not exists:
            # nested enum value, e.g. Edge.Set members are recorded with owner Set
            return (f"{fname}({lab or '_'}:) .{mem}" if fname else f".{mem}", "candidate", "implicit")
        # contextual check: expected parameter types of overloads of fname at this label
        expected = set()
        for m in recv:
            labels = m["labels"] or []
            for i, l in enumerate(labels):
                if l == (lab if lab != "_" else "") and i < len(m["params"]):
                    expected.add(m["params"][i])
        if expected:
            owners = {m["owner"] for m in exists}
            # protocol members: `.automatic` on ListStyle etc. are declared on the protocol extension
            if owners & expected or any(e in ("Bool", "String", "Int", "Double", "CGFloat", "Edge", "Set") for e in expected) or any(
                    m["owner"] in expected for m in exists):
                return f"{fname}({lab or '_'}:) .{mem}", "covered", ""
            return (f"{fname}({lab or '_'}:) .{mem}", "context_gap", ",".join(sorted(expected)))
        return f"{fname}({lab or '_'}:) .{mem}", "covered", ""
    if kind == "attr":
        if name in decl:
            return None
        if name in sui_t:
            return f"@{name}", "covered", ""
        if name in ("MainActor", "Sendable", "available", "escaping", "discardableResult", "objc", "inlinable", "frozen", "unchecked",
                    "preconcurrency", "ViewBuilder_", "testable", "autoclosure", "main", "propertyWrapper", "resultBuilder",
                    "dynamicMemberLookup", "dynamicCallable", "usableFromInline", "globalActor", "retroactive", "unknown", "State_", "IBOutlet",
                    "IBAction", "nonobjc", "NSManaged", "convention", "inline", "_spi", "_exported", "available_"):
            return None
        if name in SHIM:
            return f"@{name}", "candidate", "shim:" + SHIM[name]
        if name in T["obs"]:
            return f"@{name}", "candidate", "shim:Observation"
        fw = fw_of(name)
        if fw:
            return f"@{name}", "other:" + fw, ""
        return f"@{name}", "candidate", "attr"
    if kind == "macro":
        if name == "Preview":
            return "#Preview", "covered", ""
        if name in T["std_types"]:
            return None
        fw = fw_of(name)
        if fw:
            return f"#{name}", "other:" + fw, ""
        if name in ("available", "if", "file", "line", "function", "selector", "keyPath", "colorLiteral", "imageLiteral", "fileLiteral",
                    "warning", "error", "filePath", "fileID", "dsohandle", "column", "unavailable", "expect", "require", "Test", "isolation"):
            return None
        return f"#{name}", "candidate", "macro"
    if kind == "keypath":
        if name in decl:
            return None
        ev = [m for m in by.get(name, []) if m["owner"] == "EnvironmentValues"]
        if ev:
            return f"\\.{name}", "covered", ""
        if name.startswith("widget") or name == "showsWidgetContainerBackground":
            return f"\\.{name}", "other:WidgetKit", ""
        return f"\\.{name}", "candidate", "envkey"
    if kind == "func":
        if name in decl:
            return None
        if name in T["sui_funcs"]:
            return f"{name}(...)", "covered", ""
        if name in ("withAnimation", "withTransaction"):
            return f"{name}(...)", "candidate", "func"
        return None
    return None


if __name__ == "__main__":
    main()
