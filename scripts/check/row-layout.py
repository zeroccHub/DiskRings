#!/usr/bin/env python3
"""Gate: results-list rows stay single-line, truncated and fixed-height (P1 row overflow)."""
import re, sys
src = open("Sources/DiskRingsApp/ResultsOutline.swift").read()
need = {
    "configureSingleLine sets usesSingleLineMode": r"f\.usesSingleLineMode\s*=",
    "configureSingleLine sets cell.wraps": r"f\.cell\?\.wraps\s*=",
    "configureSingleLine sets maximumNumberOfLines": r"f\.maximumNumberOfLines\s*=",
    "configureSingleLine sets lineBreakMode": r"f\.lineBreakMode\s*=",
    "name configured single-line (tail)": r"configureSingleLine\(name,\s*ResultRowLayout\.name\)",
    "path configured single-line (middle)": r"configureSingleLine\(path,\s*ResultRowLayout\.path\)",
    "badge configured single-line": r"configureSingleLine\(badge,",
    "fixed row height per item": r"heightOfRowByItem[\s\S]{0,200}ResultRowLayout\.rowHeight",
    "badge fixed trailing constraint": r"badge\.trailingAnchor\.constraint\(equalTo: trailingAnchor",
    "name stops before badge": r"name\.trailingAnchor\.constraint\(lessThanOrEqualTo: badge\.leadingAnchor",
}
bad = [k for k, r in need.items() if not re.search(r, src)]
if re.search(r"cell\.name\.attributedStringValue", src):
    bad.append("name cell must not use attributedStringValue (resets wrapping)")
for k in bad: print("row-layout: FAIL", k)
print("row-layout: %d/%d properties OK" % (len(need) - len([b for b in bad if b in need]), len(need)))
sys.exit(1 if bad else 0)
