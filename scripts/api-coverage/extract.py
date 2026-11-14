#!/usr/bin/env python3
"""Extracts SwiftUI-relevant usage from Swift sources by parsing them with `swiftc -dump-parse`.

Usage: extract.py <out.json> [--jobs N] <name>=<dir>[:platforms] ...

Nothing is built or run: files are copied to a scratch name and only parsed.
`swiftc -dump-parse` drops #if blocks entirely, so conditions are evaluated here
(os(), canImport(), DEBUG) and the active branch is spliced in, once per platform
config; results are merged by max count per site key.

Output: JSON with per-file records:
  sites:   {key: count}        key = "kind|name|labels|ctx"
  imports: [module...]
  decls:   [names defined by the app: types, funcs, vars, enum cases]
  conforms:[protocol names in inheritance clauses (regex over the source)]
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

SKIP_DIRS = {".build", "Pods", "Carthage", "node_modules", "DerivedData", ".git", "Tests", "UITests", "Vendor", "Checkouts"}
CONFIGS = {"ios": "iOS", "tvos": "tvOS", "macos": "macOS", "watchos": "watchOS"}
UIKIT = {"iOS", "tvOS"}
TOKEN = re.compile(r'(?:[^\s()"]|"(?:[^"\\]|\\.)*")+|\(|\)')


def eval_cond(cond, plat):
    """Evaluates a #if condition for platform `plat` (iOS/tvOS/macOS/watchOS)."""
    toks = re.findall(r"&&|\|\||!|\(|\)|[A-Za-z_][\w.]*(?:\([^()]*(?:\([^()]*\))?[^()]*\))?", cond)
    pos = [0]

    def atom():
        t = toks[pos[0]]
        pos[0] += 1
        if t == "!":
            return not atom()
        if t == "(":
            v = orr()
            pos[0] += 1
            return v
        m = re.match(r"(\w+)\((.*)\)$", t)
        if m:
            f, arg = m.groups()
            if f == "os":
                return arg == plat
            if f == "canImport":
                return not ((arg == "UIKit" and plat not in UIKIT) or (arg == "AppKit" and plat != "macOS")
                            or (arg == "WatchKit" and plat != "watchOS"))
            if f == "targetEnvironment":
                return False
            if f in ("swift", "compiler"):
                return True
            return False
        return t in ("DEBUG", "true")

    def andd():
        v = atom()
        while pos[0] < len(toks) and toks[pos[0]] == "&&":
            pos[0] += 1
            r = atom()
            v = v and r
        return v

    def orr():
        v = andd()
        while pos[0] < len(toks) and toks[pos[0]] == "||":
            pos[0] += 1
            r = andd()
            v = v or r
        return v
    try:
        return orr()
    except IndexError:
        return False


def preprocess(src, plat):
    """Keeps only the active branches of #if blocks for `plat`; inactive lines become blank."""
    out, stack = [], []   # stack entries: [parent_active, taken, active]
    for line in src.split("\n"):
        st = line.strip()
        m = re.match(r"#(if|elseif)\b(.*)", st)
        if st.startswith("#if ") or st == "#if" or st.startswith("#if("):
            parent = all(e[2] for e in stack)
            v = eval_cond(st[3:], plat)
            stack.append([parent, v, v])
            out.append("")
        elif re.match(r"#elseif\b", st) and stack:
            e = stack[-1]
            v = (not e[1]) and eval_cond(st[7:], plat)
            e[1] = e[1] or v
            e[2] = v
            out.append("")
        elif re.match(r"#else\b", st) and stack:
            e = stack[-1]
            e[2] = not e[1]
            e[1] = True
            out.append("")
        elif st.startswith("#endif") and stack:
            stack.pop()
            out.append("")
        else:
            out.append(line if all(e[2] for e in stack) else "")
    return "\n".join(out)


class Node:
    __slots__ = ("tag", "attrs", "pos", "kids")

    def __init__(self, tag):
        self.tag, self.attrs, self.pos, self.kids = tag, {}, [], []


def parse_sexp(text):
    text = re.sub(r"range=\[[^\]]*\]", "range=R", text)
    text = re.sub(r"<anonymous @ 0x[0-9a-f]+>", "anon", text)
    toks = TOKEN.findall(text)
    stack, root = [], []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "(":
            i += 1
            n = Node(toks[i].split("=", 1)[0] if not toks[i].startswith('"') else "?")
            if stack:
                stack[-1].kids.append(n)
            else:
                root.append(n)
            stack.append(n)
        elif t == ")":
            if stack:
                stack.pop()
        elif not stack:
            pass
        else:
            n = stack[-1]
            if "=" in t and not t.startswith('"'):
                k, v = t.split("=", 1)
                n.attrs[k] = v.strip('"')
            elif t.startswith('"'):
                n.pos.append(t.strip('"'))
        i += 1
    return root


def arg_labels(arglist):
    out = []
    for a in (arglist.kids if arglist else []):
        if a.tag != "argument":
            continue
        l = a.attrs.get("label")
        if l is None:
            # an unlabeled closure is (almost always) a trailing closure: "_{}" lets the comparison
            # match it against any closure-typed parameter
            l = "_{}" if a.kids and a.kids[0].tag == "closure_expr" else "_"
        out.append(l)
    return out


def lab(labels):
    return ",".join(labels)


class Walker:
    def __init__(self):
        self.sites = Counter()
        self.decls = set()

    def add(self, kind, name, labels="", ctx=""):
        self.sites[f"{kind}|{name}|{labels}|{ctx}"] += 1

    def type_chain(self, n):
        """If n is a (possibly nested) type reference like Foo or Foo.Bar, return the dotted name."""
        if n.tag == "unresolved_decl_ref_expr":
            nm = n.attrs.get("name", "")
            return nm if nm[:1].isupper() else None
        if n.tag == "unresolved_dot_expr" and n.kids:
            f = n.attrs.get("field", "")
            b = self.type_chain(n.kids[0])
            if b and f[:1].isupper():
                return b + "." + f
        return None

    def chain_root(self, n):
        while True:
            if n.tag == "call_expr" and n.kids:
                callee = n.kids[0]
                if callee.tag == "unresolved_decl_ref_expr":
                    nm = callee.attrs.get("name", "")
                    return ("ctor", nm) if nm[:1].isupper() else ("func", nm)
                n = callee
            elif n.tag == "unresolved_dot_expr" and n.kids:
                t = self.type_chain(n)
                if t:
                    return ("type", t)
                n = n.kids[0]
            elif n.tag == "unresolved_decl_ref_expr":
                nm = n.attrs.get("name", "")
                return ("type", nm) if nm[:1].isupper() else ("var", nm)
            elif n.tag == "unresolved_member_expr":
                return ("member", n.attrs.get("name", ""))
            elif n.tag in ("force_value_expr", "paren_expr", "optional_evaluation_expr", "bind_optional_expr") and n.kids:
                n = n.kids[0]
            else:
                return ("other", n.tag)

    def visit(self, n, ctx=""):
        t = n.tag
        if t.startswith("original_init"):
            return
        if t in ("struct_decl", "class_decl", "enum_decl", "protocol_decl", "actor_decl", "typealias", "associated_type_decl"):
            if n.pos:
                self.decls.add(n.pos[0].split("(")[0])
        elif t in ("func_decl", "var_decl", "enum_element_decl", "subscript_decl", "constructor_decl"):
            if n.pos:
                self.decls.add(n.pos[0].split("(")[0])
                self.decls.add(n.pos[0])
        elif t == "extension_decl":
            if n.pos:
                self.add("extends", n.pos[-1])
        elif t == "type_unqualified_ident":
            self.add("type", n.attrs.get("id", ""))
        elif t == "type_member" or t == "type_qualified_ident":
            pass
        elif t == "custom_attr":
            ty = next((k for k in n.kids if k.tag == "type_unqualified_ident"), None)
            if ty:
                al = next((k for k in n.kids if k.tag == "argument_list"), None)
                self.add("attr", ty.attrs.get("id", ""), lab(arg_labels(al)))
                if al:
                    for a in al.kids:
                        if ty.attrs.get("id") in ("Environment", "EnvironmentObject"):
                            self.keypaths(a)
                        for k in a.kids:
                            self.visit(k, "")
            return
        elif t == "macro_expansion_expr":
            self.add("macro", n.attrs.get("name", ""))
        elif t == "call_expr" and n.kids:
            self.call(n, ctx)
            return
        elif t == "unresolved_dot_expr" and n.kids:
            tc = self.type_chain(n.kids[0])
            f = n.attrs.get("field", "")
            if tc:
                self.add("static", f"{tc}.{f}")
            elif n.kids[0].tag == "unresolved_member_expr":
                pass
        elif t == "unresolved_member_expr":
            self.add("imember", n.attrs.get("name", ""), "", ctx)
        elif t == "unresolved_decl_ref_expr":
            nm = n.attrs.get("name", "")
            if nm[:1].isupper():
                self.add("typeref", nm)
        sub = "" if t in ("closure_expr", "brace_stmt") else ctx
        for k in n.kids:
            self.visit(k, sub)

    def keypaths(self, n):
        if n.tag == "keypath_expr":
            for k in n.kids:
                if k.tag == "parsed_path":
                    pass
            names = []

            def collect(x):
                if x.tag in ("unresolved_dot_expr",) or x.tag.startswith("parsed_path"):
                    if "field" in x.attrs:
                        names.append(x.attrs["field"])
                for y in x.kids:
                    collect(y)
            collect(n)
            if names:
                self.add("keypath", names[-1])
        else:
            for k in n.kids:
                self.keypaths(k)

    def call(self, n, ctx):
        callee = n.kids[0]
        al = next((k for k in n.kids[1:] if k.tag == "argument_list"), None)
        labels = arg_labels(al)
        fname = None
        ct = callee.tag
        if ct == "unresolved_decl_ref_expr":
            nm = callee.attrs.get("name", "")
            if nm[:1].isupper():
                self.add("init", nm, lab(labels), ctx)
            else:
                self.add("func", nm, lab(labels), ctx)
            fname = nm
        elif ct == "unresolved_dot_expr" and callee.kids:
            f = callee.attrs.get("field", "")
            base = callee.kids[0]
            tc = self.type_chain(base)
            if tc:
                self.add("scall", f"{tc}.{f}", lab(labels), ctx)
            else:
                rk, rn = self.chain_root(base)
                self.add("mod", f, lab(labels), f"{rk}:{rn}" if rk in ("ctor", "type", "member", "func") else rk + ":" + (rn if rn in ("content", "self") else ""))
                self.visit(base, ctx)
            fname = f
        elif ct == "unresolved_member_expr":
            f = callee.attrs.get("name", "")
            self.add("imcall", f, lab(labels), ctx)
            fname = f
        else:
            self.visit(callee, ctx)
        if al:
            for idx, a in enumerate(a for a in al.kids if a.tag == "argument"):
                l = a.attrs.get("label", "_")
                actx = f"{fname}({l}:)" if fname else ""
                for k in a.kids:
                    self.visit(k, actx)
                    if fname in ("environment", "Environment", "EnvironmentObject") or l == "keyPath":
                        self.keypaths(k)


def dump(path, plat, swiftc):
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "f.swift")
        src = open(path, encoding="utf-8", errors="replace").read()
        open(f, "w").write(preprocess(src, plat))
        r = subprocess.run([swiftc, "-dump-parse", f], capture_output=True, text=True, errors="replace")
        return (r.stdout if r.stdout.lstrip().startswith("(source_file") else r.stderr), src


def process(args):
    path, plats, swiftc = args
    configs = plats
    src0 = open(path, encoding="utf-8", errors="replace").read()
    if not re.search(r"^\s*#(if|elseif)\b.*\b(os|canImport|targetEnvironment)\(", src0, re.M):
        configs = plats[:1]
    sites, decls = Counter(), set()
    for c in configs:
        text, src = dump(path, CONFIGS[c], swiftc)
        w = Walker()
        for root in parse_sexp(text):
            w.visit(root)
        for k, v in w.sites.items():
            sites[k] = max(sites[k], v)
        decls |= w.decls
    imports = sorted(set(re.findall(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:struct |class |enum |protocol |func |typealias |var )?(\w+)", src0, re.M)))
    clean = re.sub(r"//.*|/\*.*?\*/", "", src0, flags=re.S)
    conforms = []
    for m in re.finditer(r"\b(?:struct|class|enum|actor|extension|protocol)\s+[\w.]+(?:<[^>{]*>)?\s*:\s*([^{]+?)(?:where\b[^{]*)?\{", clean):
        conforms += [re.sub(r"<.*", "", x.strip()) for x in m.group(1).split(",")]
    return path, dict(sites=dict(sites), imports=imports, decls=sorted(decls), conforms=conforms, lines=src0.count("\n"))


def list_files(root):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS and not d.endswith("Tests")]
        for fn in fns:
            if fn.endswith(".swift") and fn != "Package.swift":
                yield os.path.join(dp, fn)


def main():
    argv = sys.argv[1:]
    out = argv.pop(0)
    jobs = 4
    if argv and argv[0] == "--jobs":
        jobs = int(argv[1])
        argv = argv[2:]
    swiftc = os.environ.get("SWIFTC", "swiftc")
    work, meta, meta_plats = [], {}, {}
    for spec in argv:
        name, rest = spec.split("=", 1)
        root, _, plats = rest.partition(":")
        plats = [p for p in plats.split(",") if p] or ["ios"]
        for f in list_files(root):
            work.append((f, plats, swiftc))
            meta[f] = (name, os.path.relpath(f, root))
            meta_plats[f] = plats
    print(len(work), "files", file=sys.stderr)
    result = {}
    with ThreadPoolExecutor(jobs) as ex:
        for i, (path, rec) in enumerate(ex.map(process, work)):
            name, rel = meta[path]
            rec["repo"], rec["rel"], rec["plats"] = name, rel, meta_plats[path]
            result[f"{name}/{rel}"] = rec
            if i % 200 == 0:
                print(i, file=sys.stderr)
    json.dump(result, open(out, "w"))


main()
