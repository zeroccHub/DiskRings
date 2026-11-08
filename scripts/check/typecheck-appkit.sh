#!/usr/bin/env bash
# Box-only gate: type-check EVERY source file (core + app) as the single module that
# build.sh compiles on the Mac, against Linux AppKit/Quartz stubs (scripts/check/shim).
# The stubs approximate the macOS SDK; passing this gate is necessary, not sufficient.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
OUT="$ROOT/build/check"
SWIFTC="${SWIFTC:-swiftc}"
MOD="$OUT/modules"; SRC="$OUT/src"
rm -rf "$MOD"; mkdir -p "$MOD"
# Shim copy without protocol-level @MainActor inference (see shim-noinfer.py): matches the
# Mac's stricter behaviour for nonisolated helpers on delegate classes.
S="$OUT/shim"; rm -rf "$S"; python3 scripts/check/shim-noinfer.py scripts/check/shim "$S"
emit() { # name files...
  local name="$1"; shift
  "$SWIFTC" -parse-as-library -swift-version 5 -emit-module -module-name "$name" -I "$MOD" -o "$MOD/$name.swiftmodule" "$@" 2>&1 \
    | grep -v '^$' || true
  [[ -f "$MOD/$name.swiftmodule" ]] || { echo "error: shim module $name failed to build" >&2; exit 1; }
}
emit os $S/os.swift
emit QuartzCore $S/QuartzCore.swift
emit UniformTypeIdentifiers $S/UniformTypeIdentifiers.swift
emit AppKit $S/AppKit.swift $S/AppKit2.swift $S/AppKit3.swift $S/AppKit4.swift $S/AppKit5.swift
emit Quartz $S/Quartz.swift
python3 scripts/check/prep.py Sources "$SRC"
mapfile -t FILES < <(find "$SRC" -name '*.swift' | LC_ALL=C sort)
set +e
"$SWIFTC" -typecheck -swift-version 5 -module-name DiskRings -D SINGLE_MODULE -I "$MOD" "${FILES[@]}" > "$OUT/typecheck.log" 2>&1
rc=$?
set -e
# Map build/check/src/... back to Sources/... so diagnostics point at the real files.
sed -i "s#$SRC/#Sources/#g" "$OUT/typecheck.log"
errs=$(grep -c ': error:' "$OUT/typecheck.log" || true)
warns=$(grep -c ': warning:' "$OUT/typecheck.log" || true)
grep -E ': (error|warning):' "$OUT/typecheck.log" || true
echo "typecheck-appkit: ${#FILES[@]} files, $errs error(s), $warns warning(s) (log: build/check/typecheck.log)"
[[ $rc -eq 0 && $errs -eq 0 && $warns -eq 0 ]] || exit 1
# Second pass: complete concurrency checking (what Swift 6 mode would reject), so main-actor
# misuse of AppKit is caught even though build.sh compiles in Swift 5 mode.
"$SWIFTC" -typecheck -swift-version 5 -strict-concurrency=complete -module-name DiskRings -D SINGLE_MODULE -I "$MOD" "${FILES[@]}" > "$OUT/typecheck-strict.log" 2>&1 || true
sed -i "s#$SRC/#Sources/#g" "$OUT/typecheck-strict.log"
n=$(grep -cE ': (error|warning):' "$OUT/typecheck-strict.log" || true)
grep -E ': (error|warning):' "$OUT/typecheck-strict.log" || true
echo "typecheck-appkit (strict-concurrency=complete): $n diagnostic(s) (log: build/check/typecheck-strict.log)"
[[ $n -eq 0 ]] || exit 1
# Third pass: Swift 6 language mode (isolation violations are hard errors). Our box compiler is
# 6.0.3; the Mac uses 6.1.2, whose rules differ in places (see README "Gate vs Swift 6.1").
"$SWIFTC" -typecheck -swift-version 6 -module-name DiskRings -D SINGLE_MODULE -I "$MOD" "${FILES[@]}" > "$OUT/typecheck-swift6.log" 2>&1 || true
sed -i "s#$SRC/#Sources/#g" "$OUT/typecheck-swift6.log"
python3 scripts/check/filter-selector-artifacts.py "$OUT/typecheck-swift6.log" "$SRC"
n6=$(grep -cE ': (error|warning):' "$OUT/typecheck-swift6.log" || true)
grep -E ': (error|warning):' "$OUT/typecheck-swift6.log" || true
echo "typecheck-appkit (-swift-version 6): $n6 diagnostic(s) (log: build/check/typecheck-swift6.log)"
[[ $n6 -eq 0 ]]
