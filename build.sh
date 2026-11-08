#!/usr/bin/env bash
# DiskRings — SwiftPM-free build for macOS with only the Command Line Tools.
#
#   ./build.sh            build build/DiskRings (release, host arch)
#   ./build.sh app        build + wrap into build/DiskRings.app (ad-hoc signed)
#   ./build.sh test       build + run the dependency-free self-test (no XCTest needed)
#   ./build.sh doctor     only print toolchain/SDK info and run the sanity checks
#   ./build.sh check      source gate: duplicate type names in the single module (everywhere);
#                         on Linux/box also a type-check of ALL files against AppKit stubs
#   ./build.sh dmg        package dist/DiskRings-*.dmg (macOS; see scripts/package_dmg.sh)
#   ./build.sh clean      remove build/
#
# Environment:
#   ARCH=arm64|x86_64|universal   target architecture (default: host, from `uname -m`)
#   DEBUG=1                       -Onone -g instead of -O
#   SDKROOT=/path/to/MacOSX.sdk   use this SDK instead of `xcrun --sdk macosx` (honoured, never overwritten)
#   DEVELOPER_DIR, TOOLCHAINS     honoured by xcrun as usual (never overwritten)
#   SWIFTC=/path/to/swiftc        developer override: use a plain swiftc with no SDK,
#                                 no -target and no frameworks (used to check the
#                                 single-module build on Linux; `app` is unavailable)
#
# Every source of DiskScanCore + SunburstGeometry + DiskRingsApp is compiled into
# ONE module (-module-name DiskRings -D SINGLE_MODULE). The only entry point is
# Sources/DiskRingsApp/main.swift.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
MIN_MACOS="12.0"
PRODUCT="DiskRings"
CMD="${1:-build}"
# This script never runs sudo and writes only inside ./build. Every command below that is
# meant for the user is PRINTED with an explanation, never executed.
clt_reinstall_note() {
  cat >&2 <<'HINT'
         Last resort: reinstall the Command Line Tools. This script prints no command
         for the removal on purpose; do it by hand only after reading this:
           1. Read-only check: xcode-select -p   (expect /Library/Developer/CommandLineTools;
              if it shows an Xcode.app path, STOP: that is a different toolchain)
           2. Remove the old CLT, recoverably: in Finder choose Go > Go to Folder...,
              enter /Library/Developer, drag "CommandLineTools" to the Trash and confirm
              with your admin password. Do NOT empty the Trash yet.
           3. Reinstall (no sudo; Apple's installer GUI, several GB download):
                xcode-select --install
           what/paths: moves /Library/Developer/CommandLineTools to the Trash, then the
                installer recreates it; nothing else is touched
           sudo:  admin password prompt in Finder (step 2); step 3 asks in its own GUI
           risk:  no compiler until step 3 finishes; manual edits in that folder are lost
           undo:  before emptying the Trash, Finder > Trash > "CommandLineTools" > Put Back
                  (remove any half-installed new folder first). After a good
                  ./build.sh doctor you may empty the Trash.
HINT
}

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

# Commands that need no toolchain are handled first.
case "$CMD" in
  build|app|test|doctor) ;;
  dmg|package)
    # Forward to scripts/package_dmg.sh (macOS produces the DMG; Linux: --dry-run or clear refuse).
    shift || true
    exec bash "$ROOT/scripts/package_dmg.sh" "$@"
    ;;
  check)
    # Read-only except ./build/check (scratch). No sudo, no network, nothing outside ./build.
    echo "==> check 1/2: duplicate top-level type names (single-module view of Sources/)"
    echo "    what: python3 scripts/check/dup-types.py Sources   (reads Sources/ only)"
    python3 scripts/check/dup-types.py Sources || exit 1
    echo "==> check 1b: toolbar search field wiring (installed instance = wired instance)"
    echo "    what: python3 scripts/check/search-wiring.py   (reads one source file)"
    python3 scripts/check/search-wiring.py || exit 1
    echo "    what: python3 scripts/check/row-layout.py      (results rows single-line, fixed height)"
    python3 scripts/check/row-layout.py || exit 1
    echo "    what: python3 scripts/check/search-field.py    (no views inside the search field; build stamp)"
    python3 scripts/check/search-field.py || exit 1
    echo "    what: python3 scripts/check/outline-columns.py (size column never clipped; no autosave)"
    python3 scripts/check/outline-columns.py || exit 1
    echo "    what: python3 scripts/check/basket-menu.py     (menu add-to-basket shares button path)"
    python3 scripts/check/basket-menu.py || exit 1
    echo "    what: python3 scripts/check/basket-drag.py      (drag-to-basket shares protection; no 拖到这里)"
    python3 scripts/check/basket-drag.py || exit 1
    echo "    what: python3 scripts/check/home-appearance.py  (theme refresh: home semantic colours)"
    python3 scripts/check/home-appearance.py || exit 1
    if [[ "$(uname -s)" == Darwin ]]; then
      echo "==> check 2/2 skipped on macOS: the stub type-check is for Linux boxes without the SDK."
      echo "    On a Mac the real type-check is the build itself:  ./build.sh"
      echo "      what: compiles every source into build/DiskRings; paths: writes ./build only;"
      echo "      sudo: no; risk: none (read-only for your files); undo: ./build.sh clean"
      exit 0
    fi
    echo "==> check 2/2: type-check core + app sources against Linux AppKit/Quartz stubs"
    echo "    what: bash scripts/check/typecheck-appkit.sh   (writes build/check/ only; no sudo)"
    echo "    limits: stubs approximate the macOS SDK; passing is necessary, not sufficient"
    bash scripts/check/typecheck-appkit.sh || exit 1
    echo "==> check: passed"
    exit 0 ;;
  clean) rm -rf "$BUILD_DIR"; info "removed $BUILD_DIR (only ./build is deleted)"; exit 0 ;;
  -h|--help|help) sed -n '2,24p' "$0"; exit 0 ;;
  *) die "unknown command '$CMD' (use: build | app | test | doctor | check | dmg | clean)" ;;
esac

# ---------------------------------------------------------------- sources
collect_sources() { # dirs... -> prints sorted *.swift paths, one per line
  find "$@" -type f -name '*.swift' | LC_ALL=C sort
}

CORE_SOURCES=()
while IFS= read -r f; do CORE_SOURCES+=("$f"); done < <(collect_sources Sources/DiskScanCore Sources/SunburstGeometry)
APP_SOURCES=()
while IFS= read -r f; do APP_SOURCES+=("$f"); done < <(collect_sources Sources/DiskRingsApp)
[[ ${#CORE_SOURCES[@]} -gt 0 && ${#APP_SOURCES[@]} -gt 0 ]] || die "sources not found under $ROOT/Sources"

# ------------------------------------------------------------ diagnostics
# version_lt A B: true if dotted version A < B (numeric, component-wise; bash 3.2 safe)
version_lt() {
  local IFS=.
  # shellcheck disable=SC2206
  local a=($1) b=($2) i n
  n=${#a[@]}; (( ${#b[@]} > n )) && n=${#b[@]}
  for (( i = 0; i < n; i++ )); do
    local x=${a[i]:-0} y=${b[i]:-0}
    (( 10#$x < 10#$y )) && return 0
    (( 10#$x > 10#$y )) && return 1
  done
  return 1
}

mismatch_hint() {
  cat >&2 <<HINT
         The Swift compiler and the macOS SDK come from different Command Line Tools
         builds. This typically fails with "this SDK is not supported by the compiler"
         or "failed to build module 'Swift'".
         Read-only checks first:  xcrun swiftc --version ; xcrun --show-sdk-path ;
                                  xcode-select -p ; ls /Library/Developer/CommandLineTools/SDKs
         Non-destructive option (no sudo, changes nothing on disk, only this shell):
             SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX<matching>.sdk ./build.sh
           undo: just omit SDKROOT next time.
HINT
  clt_reinstall_note
}

# Compare swiftlang build of the compiler with the one that produced the SDK's
# Swift.swiftinterface (its "// swift-compiler-version:" header line).
check_sdk_compiler_match() {
  local compiler_line="$1" sdk="$2"
  local compiler_ver sdk_ver iface
  compiler_ver="$(printf '%s\n' "$compiler_line" | grep -oE 'swiftlang-[0-9][0-9.]*' | head -n 1 | sed 's/swiftlang-//')" || true
  iface="$(find "$sdk/usr/lib/swift/Swift.swiftmodule" -name '*.swiftinterface' ! -name '*.private.swiftinterface' 2>/dev/null | LC_ALL=C sort | head -n 1)" || true
  if [[ -z "$iface" ]]; then
    warn "could not find Swift.swiftinterface in the SDK ($sdk/usr/lib/swift/Swift.swiftmodule); skipping compiler/SDK check"
    return 0
  fi
  sdk_ver="$(grep -m 1 'swift-compiler-version' "$iface" | grep -oE 'swiftlang-[0-9][0-9.]*' | head -n 1 | sed 's/swiftlang-//')" || true
  echo "    SDK Swift interface built by: swiftlang-${sdk_ver:-unknown}  ($iface)"
  echo "    compiler:                     swiftlang-${compiler_ver:-unknown}"
  if [[ -z "$compiler_ver" || -z "$sdk_ver" ]]; then
    warn "could not determine both swiftlang versions; skipping compiler/SDK check"
  elif [[ "$compiler_ver" != "$sdk_ver" ]]; then
    if version_lt "$compiler_ver" "$sdk_ver"; then
      warn "compiler swiftlang-$compiler_ver is OLDER than the SDK's swiftlang-$sdk_ver."
    else
      warn "compiler swiftlang-$compiler_ver differs from the SDK's swiftlang-$sdk_ver."
    fi
    mismatch_hint
  fi
}

swiftbridging_hint() {
  cat >&2 <<HINT
         Two module maps both define 'module SwiftBridging' (a known broken Command Line
         Tools install). Clang aborts with "redefinition of module 'SwiftBridging'".
         Manual fix, run it yourself (system file, needs sudo; this script never edits it):
           0. Inspect (read-only): grep -n SwiftBridging <module.modulemap> <bridging.modulemap>
           1. Back up (sudo, writes <module.modulemap>.bak next to it):
                sudo cp <module.modulemap> <module.modulemap>.bak
           2. Edit (sudo, MODIFIES the system file):  sudo nano <module.modulemap>
                delete only the 'module SwiftBridging { ... }' block; keep bridging.modulemap
           3. Rebuild (no sudo, writes ./build only):  ./build.sh
           risk:  a bad edit breaks C/Swift interop for every CLT build on this Mac
           undo:  sudo cp <module.modulemap>.bak <module.modulemap>
HINT
  clt_reinstall_note
}

SWIFTBRIDGING_FILES=()
find_swiftbridging_duplicates() {
  local sdk="$1" swiftc_path="$2" dev
  dev="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  local dirs=("$sdk/usr/include/swift" "$sdk/usr/include")
  if [[ -n "$dev" ]]; then
    dirs+=("$dev/usr/include/swift" "$dev/usr/lib/swift" "$dev/Toolchains/XcodeDefault.xctoolchain/usr/include/swift")
  fi
  if [[ -n "$swiftc_path" ]]; then
    dirs+=("$(dirname "$(dirname "$swiftc_path")")/include/swift")
  fi
  SWIFTBRIDGING_FILES=()
  local d f real seen
  for d in "${dirs[@]}"; do
    for f in "$d/module.modulemap" "$d/bridging.modulemap"; do
      [[ -f "$f" ]] || continue
      grep -qE '^[[:space:]]*(explicit[[:space:]]+)?module[[:space:]]+SwiftBridging([[:space:]]|[{]|$)' "$f" || continue
      real="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
      seen=0
      for x in ${SWIFTBRIDGING_FILES[@]+"${SWIFTBRIDGING_FILES[@]}"}; do [[ "$x" == "$real" ]] && seen=1; done
      [[ $seen -eq 1 ]] || SWIFTBRIDGING_FILES+=("$real")
    done
  done
}

check_swiftbridging() {
  find_swiftbridging_duplicates "$@"
  if [[ ${#SWIFTBRIDGING_FILES[@]} -ge 2 ]]; then
    warn "duplicate 'module SwiftBridging' definitions found in:"
    local f
    for f in "${SWIFTBRIDGING_FILES[@]}"; do echo "           $f" >&2; done
    swiftbridging_hint
  fi
}

# --------------------------------------------------------------- toolchain
PLAIN=0
SDK_PATH=""
XCRUN=()
SWIFTC_PATH=""
if [[ -n "${SWIFTC:-}" ]]; then
  PLAIN=1
  [[ -x "$SWIFTC" ]] || command -v "$SWIFTC" >/dev/null 2>&1 || die "SWIFTC=$SWIFTC is not executable"
  info "toolchain (SWIFTC override, plain build without SDK/frameworks)"
  "$SWIFTC" --version 2>&1 | sed 's/^/    /'
else
  [[ "$(uname -s)" == "Darwin" ]] || die "build.sh builds the macOS app and must run on macOS (set SWIFTC=... for a plain, non-AppKit build)."
  command -v xcrun >/dev/null 2>&1 || die "xcrun not found. Install the Command Line Tools yourself with:  xcode-select --install
       (no sudo; opens Apple's installer, writes /Library/Developer/CommandLineTools; undo: delete that folder)"
  if [[ -n "${SDKROOT:-}" ]]; then
    [[ -d "$SDKROOT" ]] || die "SDKROOT=$SDKROOT does not exist"
    XCRUN=(xcrun --sdk "$SDKROOT")
    SDK_PATH="$SDKROOT"
  else
    XCRUN=(xcrun --sdk macosx)
    SDK_PATH="$("${XCRUN[@]}" --show-sdk-path 2>/dev/null)" || SDK_PATH=""
  fi
  [[ -n "$SDK_PATH" && -d "$SDK_PATH" ]] || die "macOS SDK not found (xcrun --sdk macosx --show-sdk-path failed).
       Install the Command Line Tools yourself:  xcode-select --install   (no sudo; opens Apple's installer)
       If installed but broken, see README 'Known issues' (reinstall deletes /Library/Developer/CommandLineTools)."
  SWIFTC_PATH="$("${XCRUN[@]}" --find swiftc 2>/dev/null)" || die "swiftc not found in the active developer directory ($(xcode-select -p 2>/dev/null || echo '?')). Install yourself: xcode-select --install (no sudo; opens Apple's installer)"

  info "toolchain"
  echo "    developer dir: ${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo '?')}${DEVELOPER_DIR:+  (from DEVELOPER_DIR)}"
  [[ -n "${TOOLCHAINS:-}" ]] && echo "    TOOLCHAINS:    $TOOLCHAINS"
  [[ -n "${SDKROOT:-}" ]] && echo "    SDKROOT:       $SDKROOT  (from environment)"
  echo "    swiftc:        $SWIFTC_PATH"
  SWIFTC_VERSION="$("${XCRUN[@]}" swiftc --version 2>&1)" || SWIFTC_VERSION="(swiftc --version failed)"
  printf '%s\n' "$SWIFTC_VERSION" | sed 's/^/    /'
  echo "    SDK version:   $("${XCRUN[@]}" --show-sdk-version 2>/dev/null || echo '?')"
  echo "    SDK path:      $SDK_PATH"
  check_sdk_compiler_match "$SWIFTC_VERSION" "$SDK_PATH"
  check_swiftbridging "$SDK_PATH" "$SWIFTC_PATH"
fi

# check_icon: read-only structural check of Resources/AppIcon.icns (magic,
# header length == file size, all 10 OSType chunk ids present). Writes nothing.
check_icon() {
  local f="$ROOT/Resources/AppIcon.icns" magic size hdr t missing=""
  [[ -f "$f" ]] || { warn "Resources/AppIcon.icns missing (regenerate: python3 scripts/make-icns.py)"; return 1; }
  magic="$(head -c 4 "$f")"
  size="$(wc -c < "$f" | tr -d ' ')"
  # BSD od may print an extra (offset-only/blank) line and pads columns differently than GNU od:
  # squeeze all whitespace (incl. newlines) into single spaces first, then take the first 4 fields.
  hdr="$(od -An -N4 -j4 -tu1 "$f" | tr -s '[:space:]' ' ' | awk 'NF>=4{print ($1*16777216)+($2*65536)+($3*256)+$4; exit}')"
  for t in icp4 icp5 ic11 ic12 ic07 ic13 ic08 ic14 ic09 ic10; do
    LC_ALL=C grep -qa "$t" "$f" || missing="$missing $t"
  done
  if [[ "$magic" == icns && "$hdr" == "$size" && -z "$missing" ]]; then
    info "AppIcon.icns ok ($size bytes, 16-1024 px incl. @2x)"
  else
    warn "AppIcon.icns looks broken (magic=$magic header=$hdr size=$size missing:${missing:- none})"
    return 1
  fi
}

# check_strings: read-only check of Resources/{en,zh-Hans}.lproj/Localizable.strings:
# same key set, no empty values, same format specifiers per key (pure awk; writes nothing).
strings_table() { # file -> "key<TAB>sorted specifiers" per line, sorted by key; "EMPTY" marks empty values
  awk '
    /^"/ {
      line = $0
      if (!match(line, /^"([^"\\]|\\.)*"/)) next
      key = substr(line, 2, RLENGTH - 2); rest = substr(line, RLENGTH + 1)
      sub(/^[ \t]*=[ \t]*"/, "", rest); sub(/";[ \t]*$/, "", rest)
      specs = ""; v = rest; n = 0
      gsub(/%%/, "", v)
      while (match(v, /%([0-9]+\$)?[-+ 0#]*[0-9]*(\.[0-9]+)?(l|ll|h)?[@dDiuUxXoOfeEgGcCsSp]/)) {
        s = substr(v, RSTART, RLENGTH); v = substr(v, RSTART + RLENGTH)
        if (s !~ /\$/) { n++; s = "%" n "$" substr(s, 2) }
        sub(/\.[0-9]+/, "", s); specs = specs s " "
      }
      if (rest == "") specs = "EMPTY"
      print key "\t" specs
    }' "$1" | LC_ALL=C sort
}
check_strings() {
  local en="$ROOT/Resources/en.lproj/Localizable.strings" zh="$ROOT/Resources/zh-Hans.lproj/Localizable.strings" d
  [[ -f "$en" && -f "$zh" ]] || { warn "Localizable.strings missing in Resources/en.lproj or zh-Hans.lproj"; return 1; }
  d="$(diff <(strings_table "$en" | while IFS=$'\t' read -r k s; do printf '%s\t%s\n' "$k" "$(tr ' ' '\n' <<<"$s" | LC_ALL=C sort | tr '\n' ' ')"; done) \
            <(strings_table "$zh" | while IFS=$'\t' read -r k s; do printf '%s\t%s\n' "$k" "$(tr ' ' '\n' <<<"$s" | LC_ALL=C sort | tr '\n' ' ')"; done))" || true
  if [[ -n "$d" ]] || strings_table "$en" | grep -q $'\tEMPTY' || strings_table "$zh" | grep -q $'\tEMPTY'; then
    warn "Localizable.strings mismatch (keys, empty values or format specifiers):"; printf '%s\n' "$d" | head -20 >&2
    return 1
  fi
  info "Localizable.strings ok ($(strings_table "$en" | wc -l | tr -d ' ') keys, en + zh-Hans)"
}
[[ "$CMD" == "doctor" ]] && { check_icon || true; check_strings || true; }
[[ "$CMD" == "doctor" ]] && { info "doctor: done (read-only: nothing was written, no sudo used)"; exit 0; }

# ------------------------------------------------------------------ flags
if [[ "${DEBUG:-0}" == "1" ]]; then
  OPT_FLAGS=(-Onone -g -D DEBUG)
else
  OPT_FLAGS=(-O -whole-module-optimization)
fi

HOST_ARCH="$(uname -m)"
ARCH="${ARCH:-$HOST_ARCH}"
case "$ARCH" in
  arm64|x86_64) ARCHES=("$ARCH") ;;
  universal) ARCHES=(arm64 x86_64) ;;
  aarch64) ARCHES=(arm64) ;;
  *) die "unsupported ARCH=$ARCH (use arm64, x86_64 or universal)" ;;
esac

print_cmd() { printf '   '; printf '%q ' "$@"; printf '\n'; }

# compile <module-name> <output> <link-appkit:0|1> <arch> sources...
compile() {
  local module="$1" out="$2" appkit="$3" arch="$4"; shift 4
  local cmd
  if [[ $PLAIN -eq 1 ]]; then
    cmd=("$SWIFTC")
  else
    cmd=("${XCRUN[@]}" swiftc -sdk "$SDK_PATH" -target "${arch}-apple-macos${MIN_MACOS}")
  fi
  cmd+=(-module-name "$module" -D SINGLE_MODULE -swift-version 5 "${OPT_FLAGS[@]}"
        -module-cache-path "$BUILD_DIR/ModuleCache")
  if [[ $PLAIN -eq 0 && "$appkit" == "1" ]]; then
    cmd+=(-framework AppKit -framework QuartzCore -framework Quartz)
  fi
  cmd+=("$@" -o "$out")
  local label="$arch-apple-macos$MIN_MACOS"
  [[ $PLAIN -eq 0 ]] || label="plain swiftc, host target"
  info "swiftc ($module, $label)"
  print_cmd "${cmd[@]}"

  local log="$BUILD_DIR/last-compile.log" status
  set +e
  "${cmd[@]}" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    if grep -q "redefinition of module 'SwiftBridging'" "$log"; then
      echo >&2
      warn "the compile failed on the duplicate SwiftBridging module map."
      [[ $PLAIN -eq 0 ]] && find_swiftbridging_duplicates "$SDK_PATH" "$SWIFTC_PATH"
      local f
      for f in ${SWIFTBRIDGING_FILES[@]+"${SWIFTBRIDGING_FILES[@]}"}; do echo "           $f" >&2; done
      swiftbridging_hint
    fi
    if grep -qE "SDK is not supported by the compiler|failed to build module 'Swift'|compiled with a newer version|module compiled with Swift" "$log"; then
      echo >&2
      warn "the compile failed with a compiler/SDK mismatch."
      mismatch_hint
    fi
    die "compile failed (exit $status); full output in $log"
  fi
}

# build_exe <module> <final-output> <appkit> sources...  (handles universal + lipo)
build_exe() {
  local module="$1" final="$2" appkit="$3"; shift 3
  mkdir -p "$BUILD_DIR"
  if [[ $PLAIN -eq 1 || ${#ARCHES[@]} -eq 1 ]]; then
    compile "$module" "$final" "$appkit" "${ARCHES[0]}" "$@"
  else
    local slices=() a
    for a in "${ARCHES[@]}"; do
      compile "$module" "$BUILD_DIR/$module-$a" "$appkit" "$a" "$@"
      slices+=("$BUILD_DIR/$module-$a")
    done
    info "lipo -> $final"
    xcrun lipo -create "${slices[@]}" -output "$final"
    rm -f "${slices[@]}"
  fi
}

build_main() {
  build_exe "$PRODUCT" "$BUILD_DIR/$PRODUCT" 1 "${CORE_SOURCES[@]}" "${APP_SOURCES[@]}"
  info "built $BUILD_DIR/$PRODUCT"
  echo "    run the app:   $BUILD_DIR/$PRODUCT"
  echo "    text report:   $BUILD_DIR/$PRODUCT --cli <path>"
}

# Build stamp → Info.plist DiskRingsBuildID (also printed). Source hash = scripts/source-hash.sh.
build_id() {
  local ver bld src git when
  ver=$(sed -n 's:.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*:\1:p' "$ROOT/Resources/Info.plist")
  bld=$(sed -n 's:.*<key>CFBundleVersion</key><string>\(.*\)</string>.*:\1:p' "$ROOT/Resources/Info.plist")
  src=$("$ROOT/scripts/source-hash.sh")
  git=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo none)
  when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$ver ($bld) src:${src:0:12} git:$git $when"
}
stamp_build() {
  local plist="$1" id; id=$(build_id)
  if [[ -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c "Delete :DiskRingsBuildID" "$plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :DiskRingsBuildID string $id" "$plist"
  else   # portable fallback: insert before the closing </dict>
    python3 - "$plist" "$id" <<'PY'
import sys; p, i = sys.argv[1], sys.argv[2]; s = open(p).read()
k = s.rfind("</dict>"); s = s[:k] + "    <key>DiskRingsBuildID</key><string>%s</string>\n" % i + s[k:]; open(p, "w").write(s)
PY
  fi
  info "build stamp: $id"
  echo "    check it (read-only, no sudo, nothing to undo):"
  echo "      defaults read \"$app/Contents/Info\" DiskRingsBuildID"
}

build_app() {
  [[ $PLAIN -eq 0 ]] || die "'app' needs the macOS SDK (unset SWIFTC)."
  build_main
  local app="$BUILD_DIR/$PRODUCT.app"
  info "bundling $app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$BUILD_DIR/$PRODUCT" "$app/Contents/MacOS/$PRODUCT"
  cp "$ROOT/Resources/Info.plist" "$app/Contents/Info.plist"
  stamp_build "$app/Contents/Info.plist"
  check_icon || die "icon check failed"
  cp "$ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"   # CFBundleIconFile=AppIcon
  check_strings || die "localization check failed"
  cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/zh-Hans.lproj" "$app/Contents/Resources/"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$app"
    info "ad-hoc signed ($(codesign -dv "$app" 2>&1 | grep -E '^Signature' || echo 'signature ok'))"
  else
    warn "codesign not found; the bundle is unsigned"
  fi
  echo "    open it with:  open \"$app\"   (no sudo; only launches the app)"
  echo "    if Gatekeeper refuses it (only needed for a copied/downloaded bundle):"
  echo "      xattr -dr com.apple.quarantine \"$app\""
  echo "      no sudo; removes the quarantine flag from this .app bundle only; undo: rebuild or re-copy it"
  echo "    Full Disk Access: System Settings > Privacy & Security > Full Disk Access, add the app"
  echo "      (GUI only, no sudo; undo: remove it from that list)"
}

run_selftest() {
  check_icon || die "icon check failed"
  check_strings || die "localization check failed"
  local exe="$BUILD_DIR/${PRODUCT}SelfTest"
  build_exe "${PRODUCT}SelfTest" "$exe" 0 "${CORE_SOURCES[@]}" "$ROOT/SelfTest/main.swift"
  info "running self-test"
  "$exe"
}

case "$CMD" in
  build) build_main ;;
  app)   build_app ;;
  test)  run_selftest ;;
esac
