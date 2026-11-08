#!/usr/bin/env python3
"""Drops Swift-6-mode diagnostics that are artifacts of prep.py's #selector rewrite.

prep.py turns #selector(T.m(_:)) into __selector({ @MainActor in _ = (T.m(_:)) }) so the
method name must still resolve on Linux. Swift 6.0.3 in -swift-version 6 treats that unapplied
reference to a main-actor method as a nonisolated call ("call to main actor-isolated instance
method ... in a synchronous nonisolated context"), although a real #selector forms no call.
Only diagnostics of exactly that text whose column lies INSIDE a __selector(...) span are
dropped; everything else is kept. usage: filter-selector-artifacts.py <log> <prep src dir>"""
import re, sys
log, src = sys.argv[1], sys.argv[2]
keep, dropped = [], 0
pat = re.compile(r"^Sources/(.+?):(\d+):(\d+): error: call to main actor-isolated (instance|static) method '[^']+' in a synchronous nonisolated context")
lines = open(log).read().splitlines()
for ln in lines:
    m = pat.match(ln)
    if m:
        f, row, col = m.group(1), int(m.group(2)), int(m.group(3))
        text = open(f"{src}/{f}").read().splitlines()[row - 1]
        inside = any(s.start() < col - 1 < s.end() for s in re.finditer(r"__selector\(\{ @MainActor in _ = \((?:[^()]|\([^()]*\))*\) \}\)", text))
        if inside: dropped += 1; continue
    keep.append(ln)
open(log, "w").write("\n".join(keep) + "\n")
print(f"filter-selector-artifacts: dropped {dropped} #selector rewrite artifact(s)", file=sys.stderr)
