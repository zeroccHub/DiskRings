#!/usr/bin/env python3
"""Gate: nothing is ever drawn inside the toolbar NSSearchField by us (P1 stray '.*').
- no subview added to the search field (searchField.addSubview / f.addSubview after f = ...searchField)
- no '.*' label/badge view anywhere in the app target, no custom NSSearchFieldCell
- regex state is shown via SearchFieldConfig (placeholder/tooltip/footer), Contains at launch
- the build stamp is logged and shown in About."""
import re, sys, glob
app = {p: open(p).read() for p in glob.glob("Sources/DiskRingsApp/*.swift")}
mwc = app["Sources/DiskRingsApp/MainWindowController.swift"]
bad = []
for p, s in app.items():
    if re.search(r"searchField\s*\.\s*addSubview", s): bad.append(f"{p}: subview added to searchField")
    for m in re.finditer(r"let\s+(\w+)\s*=\s*[\w.]*searchField\b", s):
        if re.search(r"\b%s\s*\.\s*addSubview" % m.group(1), s): bad.append(f"{p}: subview added to search field via '{m.group(1)}'")
    if re.search(r'label\(\s*"\.\*"', s) or "regexBadge" in s: bad.append(f"{p}: '.*' badge view present")
    if re.search(r":\s*NSSearchFieldCell", s): bad.append(f"{p}: custom NSSearchFieldCell")
if "SearchFieldConfig.make" not in mwc: bad.append("SearchFieldConfig not used by the controller")
if "placeholderString = Self.searchFieldText(c.placeholderKey)" not in mwc: bad.append("placeholder not driven by SearchFieldConfig")
ts = open("Sources/SunburstGeometry/TreeSearch.swift").read()
if not re.search(r"addsSubviewsToField\s*=\s*false", ts): bad.append("SearchFieldConfig.addsSubviewsToField must be false")
if not re.search(r"public static let launch = Settings\(\)", ts): bad.append("launch settings must be the default (Contains)")
ad = app["Sources/DiskRingsApp/AppDelegate.swift"]
if "BuildInfo.logAtStartup()" not in ad or "BuildInfo.showAboutPanel()" not in ad: bad.append("build stamp not logged/shown")
if "stamp_build" not in open("build.sh").read(): bad.append("build.sh does not stamp DiskRingsBuildID")
for b in bad: print("search-field: FAIL", b)
print("search-field: %s" % ("OK (no views inside NSSearchField; regex via placeholder/tooltip/footer; build stamp wired)" if not bad else "%d problem(s)" % len(bad)))
sys.exit(1 if bad else 0)
