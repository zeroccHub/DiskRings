#!/usr/bin/env python3
"""Copies the AppKit shim, moving @MainActor from delegate PROTOCOLS onto each requirement.

Why: on the box (Swift 6.0.3) a class that conforms to a @MainActor protocol in its
declaration is inferred @MainActor as a whole, so a nonisolated @objc helper on an
NSApplicationDelegate class type-checks here. The Mac build (Swift 6.1.2, SDK 15.5) rejected
exactly that (8d609e17: AppDelegate.showAbout → BuildInfo.showAboutPanel). Without the
protocol-level attribute nothing is inferred: only the protocol requirements are main-actor,
so every other member of a conforming class is nonisolated unless the class itself is
annotated. That is the stricter of the two behaviours, so the gate errs on the safe side.
usage: shim-noinfer.py <shim dir> <out dir>"""
import re, sys, os, glob
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for p in glob.glob(os.path.join(src, "*.swift")):
    s = open(p).read()
    res, pos = [], 0
    for m in re.finditer(r"@preconcurrency @MainActor public protocol (\w+)([^{]*)\{", s):
        i = m.end(); d = 1; j = i
        while d:
            d += (s[j] == "{") - (s[j] == "}"); j += 1
        body = s[i:j - 1]
        body = re.sub(r"(^|[\n;{]\s*)(func |var )", lambda k: k.group(1) + "@MainActor " + k.group(2), body)
        res.append(s[pos:m.start()]); res.append("public protocol %s%s{%s}" % (m.group(1), m.group(2), body)); pos = j
    res.append(s[pos:])
    open(os.path.join(out, os.path.basename(p)), "w").write("".join(res))
