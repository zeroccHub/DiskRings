#!/usr/bin/env python3
"""Gate: drag-to-delete-zone shares protection path; no 「拖到这里」; internal pasteboard only."""
import re, sys, glob
bad = []
mwc = open("Sources/DiskRingsApp/MainWindowController.swift").read()
chrome = open("Sources/DiskRingsApp/Chrome.swift").read()
outline = open("Sources/DiskRingsApp/ResultsOutline.swift").read()
sun = open("Sources/DiskRingsApp/SunburstView.swift").read()
core = open("Sources/DiskScanCore/BasketDrag.swift").read()

need = [
  ("shared addNodesToBasket", mwc, r"func addNodesToBasket\(_ nodes: \[FileNode\]\)"),
  ("collectSelected uses addNodesToBasket", mwc, r"func collectSelected[\s\S]{0,300}addNodesToBasket"),
  ("sunburst collect uses addNodesToBasket", mwc, r"func sunburstView\(_ view: SunburstView, collect[\s\S]{0,120}addNodesToBasket"),
  ("drop evaluate uses protectionReason", mwc, r"func evaluateBasketDrop[\s\S]{0,400}protectionReason"),
  ("drop accept uses addNodesToBasket", mwc, r"func acceptBasketDrop[\s\S]{0,300}addNodesToBasket"),
  ("DeleteBar registers internal type only", chrome, r"registerForDraggedTypes\(\[NSPasteboard\.PasteboardType\(BasketDrag\.pasteboardType\)\]\)"),
  ("DeleteBar drag highlight", chrome, r"setDragHighlight|dragHighlight"),
  ("outline pasteboard writer", outline, r"pasteboardWriterForItem"),
  ("outline local-only drag mask", outline, r"setDraggingSourceOperationMask\(\[\], forLocal: false\)"),
  ("sunburst beginDraggingSession", sun, r"beginDraggingSession"),
  ("private pasteboard UTI", core, r'pasteboardType = "app\.diskrings\.DiskRings\.internal-file-nodes"'),
]
for name, src, pat in need:
  if not re.search(pat, src):
    bad.append(name)

# No 「拖到这里」 / Drop here anywhere in app UI strings / sources
blob = chrome + mwc + open("scripts/l10n_table.py").read()
for phrase in ["拖到这里", "Drop here", "Drag here", "Drop items here"]:
  if phrase in blob:
    bad.append(f"forbidden placeholder present: {phrase}")

# Must not register fileURL for the delete bar (no Finder drop)
if re.search(r"registerForDraggedTypes\([^\)]*fileURL", chrome):
  bad.append("DeleteBar must not accept fileURL / Finder drops")

for b in bad: print("basket-drag: FAIL", b)
print("basket-drag: %d checks, %d fail" % (len(need)+2, len(bad)))
sys.exit(1 if bad else 0)
