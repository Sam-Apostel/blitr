#!/usr/bin/env python3
"""Confirms candidate gaps by compiling one tiny snippet per API with blitr.

Usage: confirm.py <compare.json> <blitr binary> <out.json> [--top N] [--workdir DIR]

All snippets go into ONE source file, each in its own function/struct on its own line, so the
compiler reports every failing line and each error is attributable to exactly one API. An API is
a confirmed gap when its line produces an error naming it ("has no member", "cannot find ... in
scope", "unknown attribute", "no macro named"...). Lines that compile, or fail for another reason
(wrong argument types), are reported as `compiles` / `other-error` and are NOT gaps.
"""
import json
import re
import subprocess
import sys

MISSING = re.compile(r"has no member|cannot find|unknown attribute|no macro named|is not a member type|not a member type|"
                     r"cannot infer contextual base|no such module|undeclared|has no type")


def snippet(api, status, extra):
    """Returns (statement-or-decl, token that must appear in a matching error)."""
    m = re.match(r"^type (.+)$", api)
    if m:
        return f"typealias _T = {m.group(1)}", m.group(1).split(".")[-1]
    m = re.match(r"^conformance: (.+)$", api)
    if m:
        return f"struct _C: {m.group(1)} {{}}", m.group(1)
    if api == "@Entry":
        return "extension EnvironmentValues { @Entry var _confirmEntry: Int = 0 }", "Entry"
    if api in ("@Observable", "@ObservationIgnored"):
        return f"@Observable final class _Confirm{api[1:]} {{ @ObservationIgnored var x = 0 }}", api[1:]
    m = re.match(r"^@(\w+)$", api)
    if m:
        return f"struct _A {{ @{m.group(1)} var x: Int = 0 }}", m.group(1)
    m = re.match(r"^#(\w+)$", api)
    if m:
        return f"func _f() {{ let _ = #{m.group(1)} }}", m.group(1)
    m = re.match(r"^\\\.(\w+)$", api)
    if m:
        return f"func _f() {{ let _ = \\EnvironmentValues.{m.group(1)} }}", m.group(1)
    m = re.match(r"^\.(\w+)\((.*)\)$", api)
    if m:
        return f"struct _V: View {{ var body: some View {{ Text(\"a\").{m.group(1)}() }} }}", m.group(1)
    m = re.match(r"^([A-Za-z_][\w.]*)\(\.\.\.\)$", api)
    if m:
        t = m.group(1)
        if "." in t:
            return f"func _f() {{ let _ = {t} }}", t.split(".")[-1]
        return f"func _f() {{ let _ = {t}.self }}", t
    m = re.match(r"^(\w+)\(([^)]*)\) \.(\w+)$", api)
    if m:
        f, labels, mem = m.groups()
        first = labels.split(":")[0] if labels else "_"
        arg = (f"{first}: " if first not in ("", "_") else "") + f".{mem}"
        if f[0].isupper():
            return f"func _f() {{ let _ = {f}({arg}) }}", mem
        return f"struct _V: View {{ var body: some View {{ Text(\"a\").{f}({arg}) }} }}", mem
    m = re.match(r"^([A-Z][\w.]*)\.(\w+)$", api)
    if m:
        return f"func _f() {{ let _ = {m.group(1)}.{m.group(2)} }}", m.group(2)
    return None, None


def run_manual(path, binary, work):
    """Realistic, complete call-site snippets: any compile error on a snippet's lines marks it failing."""
    items = list(json.load(open(path)).items())
    out = {}
    for start in range(0, len(items), 20):
        lines = ["import SwiftUI", "import WidgetKit", "import ActivityKit", "import AppIntents", "#Preview { Text(\"x\") }"]
        spans = {}
        for i, (name, code) in enumerate(items[start:start + 20]):
            decl = re.match(r"^(struct|final|@|extension|func|#Preview)", code)
            body = code if decl else f"struct _V{i}: View {{ var body: some View {{ {code} }} }}"
            first = len(lines) + 1
            lines += body.split("\n")
            spans[name] = (first, len(lines))
        p = work + "/manual_snippets.swift"
        open(p, "w").write("\n".join(lines) + "\n")
        res = subprocess.run([binary, "render", p, "-o", "/dev/null"], capture_output=True, text=True)
        errs = [(int(m.group(1)), m.group(2)) for m in re.finditer(r"^[^\n]*?manual_snippets\.swift:(\d+):\d+: error: (.*)$", res.stderr + res.stdout, re.M)]
        for name, (a, b) in spans.items():
            es = [e for ln, e in errs if a <= ln <= b]
            out[name] = "compiles" if not es else "fails: " + es[0][:140]
    return out


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == "--manual":
        res = run_manual(argv[1], argv[2], argv[4] if len(argv) > 4 else "/tmp")
        json.dump(res, open(argv[3], "w"), indent=1)
        for k, v in res.items():
            print(("OK   " if v == "compiles" else "FAIL ") + k + ("" if v == "compiles" else "  <- " + v))
        return
    cmp_path, binary, out = argv[0], argv[1], argv[2]
    top, work = 100000, "/tmp"
    if "--top" in argv:
        top = int(argv[argv.index("--top") + 1])
    rows = json.load(open(cmp_path))["rows"]
    cand = [r for r in rows if r["status"] in ("candidate", "context_gap")]
    others = [r for r in rows if r["status"].startswith("other:") and not r["status"].startswith("other:3p:")]
    cand.sort(key=lambda r: -r["sites"])
    others.sort(key=lambda r: -r["sites"])
    cand = cand[:top] + others[:80]
    batch_size = 25    # the tool reads stderr after stdout: keep each batch's diagnostics under the pipe buffer
    result = {}
    for start in range(0, len(cand), batch_size):
        lines = ["import SwiftUI", "import WidgetKit", "import ActivityKit", "import AppIntents", "#Preview { Text(\"x\") }"]
        index = {}
        for i, r in enumerate(cand[start:start + batch_size]):
            code, token = snippet(r["api"], r["status"], r["extra"])
            if code is None:
                continue
            code = code.replace("_V", f"_V{i}").replace("_T", f"_T{i}").replace("_C:", f"_C{i}:").replace("_A ", f"_A{i} ").replace("_f(", f"_f{i}(")
            lines.append(code)
            index[len(lines)] = (r["api"], token)
        path = work + "/confirm_snippets.swift"
        open(path, "w").write("\n".join(lines) + "\n")
        res = subprocess.run([binary, "render", path, "-o", "/dev/null"], capture_output=True, text=True)
        errs = {}
        for m in re.finditer(r"^[^\n]*?confirm_snippets\.swift:(\d+):\d+: error: (.*)$", res.stderr + res.stdout, re.M):
            errs.setdefault(int(m.group(1)), []).append(m.group(2))
        for ln, (api, token) in index.items():
            es = errs.get(ln, [])
            if any(MISSING.search(e) and token in e for e in es):
                result[api] = "gap"
            elif es:
                result[api] = "other-error: " + es[0][:120]
            else:
                result[api] = "compiles"
    json.dump(result, open(out, "w"), indent=1)
    from collections import Counter
    print(Counter(v.split(":")[0] for v in result.values()), file=sys.stderr)


main()
