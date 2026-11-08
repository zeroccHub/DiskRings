#!/usr/bin/env python3
"""Copy Sources/ for the Linux AppKit type-check, rewriting only what Linux Swift cannot parse.

Linux Swift has no Objective-C runtime, so:
  * `@objc` / `@objc(name)` attributes are removed (same line, same column count → line
    numbers in diagnostics stay identical);
  * `#selector(expr)` becomes `__selector(expr)`, so `expr` (a method reference) must still
    resolve and type-check — a missing or misspelt action method is an error.
Because @objc disappears, this script checks it textually instead: every method named in a
`#selector(...)` must be declared `@objc` (or `override`, i.e. inherited from AppKit) in some
source file, otherwise the real build would fail with "argument of #selector refers to
instance method that is not exposed to Objective-C".
Usage: prep.py <Sources> <outdir>   exit 1 on @objc findings.
"""
import os, re, sys, shutil
src, out = sys.argv[1], sys.argv[2]
shutil.rmtree(out, ignore_errors=True)
texts = {}
for d, _, fs in os.walk(src):
    for f in fs:
        if f.endswith(".swift"):
            p = os.path.join(d, f); texts[p] = open(p, encoding="utf-8").read()

OBJC = re.compile(r'@objc(\([^)]*\))?\s?')
SEL = re.compile(r'#selector\(')
problems = []

def rewrite_selectors(line):
    """#selector(EXPR) -> __selector({ @MainActor in _ = (EXPR) }): EXPR must resolve; the
    closure is never run, and @MainActor lets it name main-actor methods from any context."""
    out, i = "", 0
    while True:
        j = line.find("#selector(", i)
        if j < 0: return out + line[i:]
        k, depth = j + len("#selector("), 1
        while depth:
            if k >= len(line): raise SystemExit(f"prep: unbalanced #selector in: {line}")
            depth += {"(": 1, ")": -1}.get(line[k], 0); k += 1
        expr = line[j + len("#selector("):k - 1]
        out += line[i:j] + "__selector({ @MainActor in _ = (" + expr + ") })"
        i = k
# method names referenced by #selector, e.g. "MainWindowController.goUp(_:)" -> ("MainWindowController", "goUp")
refs = []
for p, t in texts.items():
    for i, line in enumerate(t.splitlines(), 1):
        for m in re.finditer(r'#selector\(((?:\w+\.)*)(\w+)', line):
            refs.append((p, i, m.group(1).rstrip("."), m.group(2)))
alltext = "\n".join(texts.values())
APPKIT_PREFIXES = ("NS",)
for p, i, owner, name in refs:
    if owner.startswith(APPKIT_PREFIXES):
        continue                                   # SDK method, @objc by definition
    if name in ("getter", "setter"):
        continue
    decl = re.compile(r'(@objc(\([^)]*\))?\s+(?:(?:private|fileprivate|internal|public|open|final|override|static|class|@\w+)\s+)*func\s+' + name + r'\b)'
                      r'|((?:override\s+)(?:(?:public|open|final)\s+)*func\s+' + name + r'\b)')
    if not decl.search(alltext):
        problems.append(f"{p}:{i}: error: #selector refers to '{name}', which is not declared @objc (or an AppKit override) anywhere")

for p, t in texts.items():
    if re.search(r'\bQL[A-Z]\w*', t) and not re.search(r'^import Quartz\b', t, re.M):
        problems.append(f"{p}:1: error: uses Quick Look (QL*) types but does not 'import Quartz'")
    if re.search(r'\bUTType\b', t) and not re.search(r'^import UniformTypeIdentifiers\b', t, re.M):
        problems.append(f"{p}:1: error: uses UTType but does not 'import UniformTypeIdentifiers'")

for p, t in texts.items():
    rel = os.path.relpath(p, src)
    dst = os.path.join(out, rel); os.makedirs(os.path.dirname(dst), exist_ok=True)
    lines = []
    for line in t.splitlines(keepends=True):
        line = OBJC.sub("", line)
        line = rewrite_selectors(line)
        # The real SDK is an imported Objective-C module: its @MainActor annotations are
        # treated as @preconcurrency in Swift 5 mode. Mirror that for the Swift-source stubs.
        line = re.sub(r'^import (AppKit|Quartz|QuartzCore|UniformTypeIdentifiers)\b', r'@preconcurrency import \1', line)
        lines.append(line)
    open(dst, "w", encoding="utf-8").write("".join(lines))
for x in problems: print(x)
print(f"prep: {len(texts)} files, {len(refs)} #selector references, {len(problems)} @objc finding(s)")
sys.exit(1 if problems else 0)
