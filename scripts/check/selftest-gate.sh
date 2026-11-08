#!/usr/bin/env bash
# Proves the gate catches the two defects of the failed Mac build (b8f45c6b): it copies the
# project to a temp dir, re-injects them, and expects ./build.sh check to FAIL with the
# matching diagnostics. Box only; writes only to a mktemp dir that it removes.
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -R Sources scripts build.sh "$T/"
pass=0; fail=0
expect() { # name pattern
  if grep -qE "$2" "$T/out.txt"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi
}
# 1) duplicate CapacityBarView (home-page bar renamed back)
sed -i.bak 's/VolumeUsageBarView/CapacityBarView/g' "$T/Sources/DiskRingsApp/HomePageView.swift"
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with a duplicate type"; exit 1; }
expect "duplicate type name reported" "duplicate top-level type 'CapacityBarView'"
mv "$T/Sources/DiskRingsApp/HomePageView.swift.bak" "$T/Sources/DiskRingsApp/HomePageView.swift"
# 2) missing member: Sector.span removed
sed -i.bak '/public var span: Double { endAngle - startAngle }/d' "$T/Sources/SunburstGeometry/ChartModel.swift"
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with a missing member"; exit 1; }
expect "missing member reported" "SunburstView.swift:[0-9]+:[0-9]+: error: value of type 'ChartModel<FileNode>.Sector' has no member 'span'"
mv "$T/Sources/SunburstGeometry/ChartModel.swift.bak" "$T/Sources/SunburstGeometry/ChartModel.swift"
# 3) wrong AppKit signature in app code
sed -i.bak 's/addToolTip(r, owner: self, userData: nil)/addToolTip(r, owner: self)/' "$T/Sources/DiskRingsApp/CapacityBarView.swift"
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with a wrong signature"; exit 1; }
expect "wrong AppKit signature reported" "CapacityBarView.swift:[0-9]+:[0-9]+: error: missing argument for parameter 'userData'"
mv "$T/Sources/DiskRingsApp/CapacityBarView.swift.bak" "$T/Sources/DiskRingsApp/CapacityBarView.swift"
# 4) #selector to a method that is not @objc
sed -i.bak 's/@objc private func noticeExpired/private func noticeExpired/' "$T/Sources/DiskRingsApp/CapacityBarView.swift"
grep -q "private func noticeExpired" "$T/Sources/DiskRingsApp/CapacityBarView.swift" || { echo "  FAIL fixture: noticeExpired not found"; exit 1; }
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with a non-@objc selector"; exit 1; }
expect "non-@objc #selector reported" "refers to 'noticeExpired', which is not declared @objc"
mv "$T/Sources/DiskRingsApp/CapacityBarView.swift.bak" "$T/Sources/DiskRingsApp/CapacityBarView.swift"
# 5) toolbar returns a fresh search item (not the wired one) / delegate dropped
sed -i.bak 's/            return searchItem$/            return NSSearchToolbarItem(itemIdentifier: id)/; s/searchItem.searchField.delegate = self/_ = 0/' "$T/Sources/DiskRingsApp/MainWindowController.swift"
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with an unwired search field"; exit 1; }
expect "unwired toolbar search field reported" "error: search wiring: .*(exactly one|return searchItem|delegate = self)"
mv "$T/Sources/DiskRingsApp/MainWindowController.swift.bak" "$T/Sources/DiskRingsApp/MainWindowController.swift"
# 6) Mac build failure of 8d609e17: AppDelegate not @MainActor → nonisolated @objc showAbout
#    calls the main-actor BuildInfo.showAboutPanel (Swift 6.1.2 / SDK 15.5 error, verbatim).
python3 - "$T/Sources/DiskRingsApp/AppDelegate.swift" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
old = "@MainActor\nfinal class AppDelegate:"
assert old in s, "fixture: @MainActor AppDelegate not found"
open(p + ".bak", "w").write(s); open(p, "w").write(s.replace(old, "final class AppDelegate:"))
PY
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  FAIL check passed with a nonisolated AppDelegate"; exit 1; }
expect "nonisolated AppDelegate.showAbout reported" "AppDelegate.swift:[0-9]+:[0-9]+: error: call to main actor-isolated static method 'showAboutPanel\(\)' in a synchronous nonisolated context"
mv "$T/Sources/DiskRingsApp/AppDelegate.swift.bak" "$T/Sources/DiskRingsApp/AppDelegate.swift"
# 7) clean copy passes
(cd "$T" && ./build.sh check) > "$T/out.txt" 2>&1 && { echo "  ok   clean tree passes"; pass=$((pass+1)); } || { echo "  FAIL clean tree"; tail -5 "$T/out.txt"; fail=$((fail+1)); }
echo "gate selftest: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
