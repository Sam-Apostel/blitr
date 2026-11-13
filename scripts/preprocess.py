#!/usr/bin/env python3
"""Rewrites a SwiftUI source file so it can be rendered headlessly.

  #Preview("Name", ...) { body }   ->  let __preview_N = _PreviewEntry("Name") { body }
  @Previewable                      ->  (removed)
  @main                             ->  (removed; the generated main.swift is the entry point)

Writes the rewritten file plus a main.swift that registers every preview.
Comments and string literals are skipped so only real code is touched.
Usage: preprocess.py <source.swift>... <output-dir>
"""
import os
import re
import sys


def code_spans(src):
    """Yields (start, end, is_code) covering src, separating comments/strings from code."""
    i, n, start = 0, len(src), 0
    while i < n:
        two = src[i:i + 2]
        if two == '//':
            j = src.find('\n', i)
            j = n if j < 0 else j
        elif two == '/*':
            depth, j = 1, i + 2
            while j < n and depth:
                if src[j:j + 2] == '/*': depth += 1; j += 2
                elif src[j:j + 2] == '*/': depth -= 1; j += 2
                else: j += 1
        elif src[i] == '"' or (src[i] == '#' and re.match(r'#+"', src[i:])):
            m = re.match(r'(#*)("""|")', src[i:])
            hashes, quote = m.group(1), m.group(2)
            close = quote + hashes
            j = i + len(m.group(0))
            while j < n:
                if src[j] == '\\' and not hashes: j += 2; continue
                if src.startswith(close, j): j += len(close); break
                if quote == '"' and src[j] == '\n': break
                j += 1
        else:
            i += 1
            continue
        if i > start: yield (start, i, True)
        yield (i, j, False)
        i = start = j
    if start < n: yield (start, n, True)


def matching_paren(src, open_index):
    depth = 0
    for i in range(open_index, len(src)):
        if src[i] == '(': depth += 1
        elif src[i] == ')':
            depth -= 1
            if depth == 0: return i
    return -1


def rewrite(src, counter):
    code = [False] * len(src)
    for a, b, is_code in code_spans(src):
        if is_code:
            for k in range(a, b): code[k] = True
    out, i, names = [], 0, []
    for m in re.finditer(r'#Preview\b|@Previewable\s*|@main\b', src):
        if not code[m.start()] or m.start() < i: continue
        out.append(src[i:m.start()])
        token = m.group(0)
        if token.startswith('@Previewable'):
            i = m.end()
        elif token == '@main':
            i = m.end()
        else:
            j = m.end()
            name = 'nil'
            k = j
            while k < len(src) and src[k] in ' \t': k += 1
            if k < len(src) and src[k] == '(':
                close = matching_paren(src, k)
                args = src[k + 1:close]
                first = re.match(r'\s*("(?:[^"\\]|\\.)*")', args)
                if first: name = first.group(1)
                j = close + 1
            ident = '__preview_%d' % counter[0]
            counter[0] += 1
            names.append(ident)
            out.append('@MainActor let %s = SwiftUI._PreviewEntry(%s)' % (ident, name))
            i = j
    out.append(src[i:])
    return ''.join(out), names


def main():
    *sources, outdir = sys.argv[1:]
    os.makedirs(outdir, exist_ok=True)
    counter, entries = [0], []
    for index, path in enumerate(sources):
        with open(path, encoding='utf-8') as f:
            src = f.read()
        rewritten, names = rewrite(src, counter)
        entries += names
        # Old-style previews: `struct X_Previews: PreviewProvider`.
        for m in re.finditer(r'struct\s+(\w+)\s*:\s*[^{]*\bPreviewProvider\b', rewritten):
            entries.append('SwiftUI._PreviewEntry("%s") { %s.previews }' % (m.group(1), m.group(1)))
        name = os.path.basename(path)
        if name == 'main.swift': name = 'main_%d.swift' % index
        with open(os.path.join(outdir, name), 'w', encoding='utf-8') as f:
            f.write(rewritten)
    with open(os.path.join(outdir, 'main.swift'), 'w', encoding='utf-8') as f:
        f.write('import SwiftUI\n\nMainActor.assumeIsolated {\n    SwiftUI._ScreenshotRunner.run([\n')
        for e in entries: f.write('        %s,\n' % e)
        f.write('    ])\n}\n')


if __name__ == '__main__':
    main()
