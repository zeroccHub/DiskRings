#!/usr/bin/env python3
"""Gate: context-menu 「加入删除区」 shares the button path (promote clickedRow + actionNodes)."""
import re, sys
mwc = open("Sources/DiskRingsApp/MainWindowController.swift").read()
ro = open("Sources/DiskRingsApp/ResultsOutline.swift").read()
need = {
  "menu item uses collectSelected": (mwc, r'button\.addToBasket".*#selector\(collectSelected'),
  "button uses collectSelected": (mwc, r'addButton\.action = #selector\(collectSelected'),
  "menuWillOpen promotes selection": (mwc, r'func menuWillOpen[\s\S]{0,200}promoteClickedRowIntoSelectionIfNeeded'),
  "collectSelected uses actionNodes": (mwc, r'func collectSelected[\s\S]{0,500}addNodesToBasket\(outline\.actionNodes\)'),
  "addNodesToBasket shared": (mwc, r"func addNodesToBasket\(_ nodes: \[FileNode\]\)"),
  "promote helper exists": (ro, r'func promoteClickedRowIntoSelectionIfNeeded'),
  "actionNodes uses OutlineActionTargets": (ro, r'OutlineActionTargets\.rowIndexes'),
}
bad = [k for k,(src,pat) in need.items() if not re.search(pat, src)]
for b in bad: print("basket-menu: FAIL", b)
print("basket-menu: %d/%d OK" % (len(need)-len(bad), len(need)))
sys.exit(1 if bad else 0)
