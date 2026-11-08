#!/usr/bin/env python3
"""Gate: home page re-applies semantic colours on appearance change (three modes)."""
import re, sys
bad = []
home = open("Sources/DiskRingsApp/HomePageView.swift").read()
theme = open("Sources/DiskRingsApp/Theme+AppKit.swift").read()
app = open("Sources/DiskRingsApp/AppDelegate.swift").read()
mwc = open("Sources/DiskRingsApp/MainWindowController.swift").read()
pref = open("Sources/DiskScanCore/AppearancePreference.swift").read()

need = [
  ("HomePageView.refreshAppearance", home, r"func refreshAppearance\(\)"),
  ("viewDidChangeEffectiveAppearance calls refreshAppearance", home,
   r"func viewDidChangeEffectiveAppearance[\s\S]{0,120}refreshAppearance\(\)"),
  ("refresh walks CardView.applyChrome", home, r"for case let card as CardView[\s\S]{0,80}card\.applyChrome\(\)"),
  ("home uses drBgWindow", home, r"resolvedCGColor\(\.drBgWindow\)"),
  ("tip uses drAccentContainer (FDA)", home, r"drAccentContainer"),
  ("home accent token wired", theme, r"static let drAccent"),
  ("freeTrack token wired", theme, r"static let drFreeTrack"),
  ("CardView uses drBgGroup", home, r"func applyChrome[\s\S]{0,120}drBgGroup"),
  ("CardView uses drSeparator", home, r"func applyChrome[\s\S]{0,200}drSeparator"),
  ("dynamic drBgWindow token", theme, r"static let drBgWindow"),
  ("dynamic drBgGroup token", theme, r"static let drBgGroup"),
  ("resolvedCGColor helper", theme, r"func resolvedCGColor"),
  ("applyAppearance posts notification", app, r"appearanceDidChangeNotification"),
  ("applyAppearance uses resolvedAppearance", app, r"pref\.resolvedAppearance"),
  ("MWC observes appearance notification", mwc, r"AppDelegate\.appearanceDidChangeNotification"),
  ("MWC calls homePage.refreshAppearance", mwc, r"homePage\.refreshAppearance\(\)"),
  ("AppearancePreference.resolvedAppearance", pref, r"var resolvedAppearance"),
  ("three modes: system/light/dark", pref, r"case system, light, dark"),
]

for name, src, pat in need:
  if not re.search(pat, src):
    bad.append(name)

# Hard-coded light-only fills on home CALayers are forbidden (must go through tokens / resolvedCGColor).
# Allow RGB only inside Theme.swift / ThemeTokens — not in HomePageView card/tip chrome.
for phrase in ["NSColor(srgbRed:", "NSColor(calibratedWhite:", "CGColor(red:", "0xFFFFFF", "0xF2F2F2"]:
  # tip/card chrome section: reject one-shot white fills
  if phrase in home and "resolvedCGColor" in home:
    # only fail if used as a layer background assignment without resolvedCGColor nearby… keep simple:
    if re.search(r"layer\?\.backgroundColor\s*=\s*[^\n]*" + re.escape(phrase), home):
      bad.append(f"hard-coded layer fill: {phrase}")

# controlBackgroundColor on home CALayers is the old freeze path — must use design tokens
if re.search(r"resolvedCGColor\(\.controlBackgroundColor\)", home):
  bad.append("home still uses controlBackgroundColor for CALayer (use drBg*)")

for b in bad:
  print("home-appearance: FAIL", b)
print("home-appearance: %d checks, %d fail" % (len(need), len(bad)))
sys.exit(1 if bad else 0)
