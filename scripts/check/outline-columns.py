#!/usr/bin/env python3
"""Gate: right outline column config (size never clipped, name absorbs width, no autosave)."""
import re, sys
s = open("Sources/DiskRingsApp/ResultsOutline.swift").read()
m = open("Sources/DiskRingsApp/MainWindowController.swift").read()
g = open("Sources/SunburstGeometry/OutlineColumns.swift").read()
need = {
  "firstColumnOnly autoresizing": (s, r"columnAutoresizingStyle\s*=\s*\.firstColumnOnlyAutoresizingStyle"),
  "no table autosave name": (s, r"view\.autosaveName\s*=\s*nil"),
  "no autosaved columns": (s, r"view\.autosaveTableColumns\s*=\s*false"),
  "name column autoresizes": (s, r'id == "name"[\s\S]{0,200}resizingMask\s*=\s*\.autoresizingMask'),
  "fixed columns not resizable": (s, r"c\.minWidth = w; c\.maxWidth = w\s*\n\s*c\.resizingMask = \[\]"),
  "fixed columns right-aligned": (s, r"headerCell\.alignment = \.right"),
  "refit on pane resize": (s, r"onResize = \{ \[weak self\] in self\?\.fitColumns\(\) \}"),
  "resize hook in outline view": (s, r"override func resize\(withOldSuperviewSize"),
  "widths from OutlineColumns": (s, r"OutlineColumns\.widths\(pane:"),
  "no horizontal scroller": (m, r"scroll\.hasHorizontalScroller = false"),
  "size minimum >= 72": (g, r"sizeMinimum: Double = (7[2-9]|[89]\d|\d{3})\b"),
  "no hard-coded 300pt name column": (s, None),
}
bad = []
for k, (src, pat) in need.items():
    if pat is None:
        if re.search(r'\("name", tr\("column\.name"\), 300\)', src): bad.append(k)
    elif not re.search(pat, src): bad.append(k)
for b in bad: print("outline-columns: FAIL", b)
print("outline-columns: %d/%d OK" % (len(need) - len(bad), len(need)))
sys.exit(1 if bad else 0)
