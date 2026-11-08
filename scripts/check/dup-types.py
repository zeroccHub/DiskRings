#!/usr/bin/env python3
"""Fail if two files declare the same top-level type name in the single-module build.

build.sh compiles Sources/DiskScanCore + SunburstGeometry + DiskRingsApp as ONE module
(-D SINGLE_MODULE), so a class name used in two of those directories clashes even though
SwiftPM (separate modules) accepts it. Only internal/public/open declarations count:
private/fileprivate top-level types are file-scoped and may repeat.
Usage: scripts/check/dup-types.py [Sources]   exit 1 on duplicates.
"""
import os, re, sys
root = sys.argv[1] if len(sys.argv) > 1 else "Sources"
DECL = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*((?:public|open|internal|private|fileprivate|final|indirect|nonisolated)\s+)*'
                  r'(class|struct|enum|protocol|actor|typealias)\s+([A-Za-z_]\w*)')
seen = {}
for d, _, fs in os.walk(root):
    for f in sorted(fs):
        if not f.endswith(".swift"): continue
        p = os.path.join(d, f)
        for i, line in enumerate(open(p, encoding="utf-8"), 1):
            if line[:1].isspace(): continue          # nested / indented: not top level
            m = DECL.match(line)
            if not m or (m.group(2) == "class" and line.lstrip().startswith("class func")): continue
            if re.match(r'^(?:@\w+\s+)*(private|fileprivate)\b', line): continue
            seen.setdefault(m.group(3), []).append(f"{p}:{i}")
dups = {k: v for k, v in seen.items() if len(v) > 1}
for k, v in sorted(dups.items()):
    print(f"error: duplicate top-level type '{k}' in the single module:\n  " + "\n  ".join(v))
print(f"dup-types: {len(seen)} top-level types, {len(dups)} duplicate name(s)")
sys.exit(1 if dups else 0)
