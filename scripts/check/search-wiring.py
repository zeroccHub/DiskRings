#!/usr/bin/env python3
"""Gate: the toolbar search field that is INSTALLED is the one the controller wired.

Static check of Sources/DiskRingsApp/MainWindowController.swift (box has no AppKit runtime):
  1. exactly one NSSearchToolbarItem( construction, stored in a property;
  2. the toolbar delegate's case for that item returns that same property (no copy / new item);
  3. that case wires delegate = self, target = self and action = #selector(...) on its searchField;
  4. the controller conforms to NSSearchFieldDelegate and implements controlTextDidChange;
  5. the runtime check verifySearchWiring() (installed item === stored item, delegate/target/action
     set; logs PROBLEM in category "filter") is called.
Read-only. Exit 1 with a diagnostic per failed rule."""
import re, sys
path = sys.argv[1] if len(sys.argv) > 1 else "Sources/DiskRingsApp/MainWindowController.swift"
src = open(path, encoding="utf-8").read()
errs = []
made = re.findall(r"(?:let|var)\s+(\w+)\s*=\s*NSSearchToolbarItem\(", src)
if len(re.findall(r"NSSearchToolbarItem\(", src)) != 1 or len(made) != 1:
    errs.append("expected exactly one NSSearchToolbarItem(...) stored in a property")
else:
    item = made[0]
    m = re.search(r"case\s+" + item + r"\.itemIdentifier\s*:(.*?)(?=\n\s*case\s|\n\s*default\s*:)", src, re.S)
    if not m:
        errs.append(f"toolbar delegate has no 'case {item}.itemIdentifier:'")
    else:
        body = m.group(1)
        if not re.search(r"return\s+" + item + r"\s*$", body.strip(), re.M):
            errs.append(f"search case must 'return {item}' (the wired instance)")
        for rule, pat in [("delegate = self", r"\.delegate\s*=\s*self"), ("target = self", r"\.target\s*=\s*self"),
                          ("action = #selector", r"\.action\s*=\s*#selector\(")]:
            if not re.search(item + r"\.searchField" + pat, body):
                errs.append(f"search case does not set {item}.searchField{' ' + rule}")
if not re.search(r"extension\s+MainWindowController\s*:\s*[^{]*NSSearchFieldDelegate", src):
    errs.append("MainWindowController does not conform to NSSearchFieldDelegate")
if "func controlTextDidChange(" not in src:
    errs.append("controlTextDidChange(_:) not implemented")
if not re.search(r"verifySearchWiring\(\)", src.split("func verifySearchWiring", 1)[0]):
    errs.append("verifySearchWiring() is never called")
for e in errs:
    print(f"{path}: error: search wiring: {e}")
print(f"search-wiring: {len(errs)} problem(s)")
sys.exit(1 if errs else 0)
