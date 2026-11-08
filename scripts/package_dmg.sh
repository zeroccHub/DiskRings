#!/usr/bin/env bash
# DiskRings — one-click DMG packaging (PRD: diskrings-specs/dmg-distribution-prd.md)
#
# Usage:
#   ./scripts/package_dmg.sh [--adhoc|--notarize] [--universal|--arm64] [--dry-run] [--skip-build]
#   ./build.sh dmg   # forwards remaining args here
#
# Defaults:
#   Sign mode: --adhoc (unless --notarize is given)
#   Arch:      --arm64 default (adds -arm64); --universal drops the arch tag
#
# Notarize requires (never touches keychain / Apple ID for you):
#   IDENTITY='Developer ID Application: Your Name (TEAMID)'
#   and one of:
#     NOTARY_PROFILE='NotaryProfile'          # xcrun notarytool store-credentials profile
#     or NOTARY_APPLE_ID + NOTARY_PASSWORD + NOTARY_TEAM_ID
#     or NOTARY_KEY (path) + NOTARY_KEY_ID + NOTARY_ISSUER
#
# Output: dist/DiskRings-<ver>[-adhoc][-arm64].dmg + dist/SHA256SUMS
# Volume name: DiskRings
#
# Linux: real hdiutil/codesign are refused; --dry-run still validates structure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="adhoc"          # adhoc | notarize
ARCH="arm64"          # arm64 (default per milestone) | universal
DRY_RUN=0
SKIP_BUILD=0
OUT_DIR="$ROOT/dist"
VOLNAME="DiskRings"
APP_NAME="DiskRings.app"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

usage() {
  sed -n '2,28p' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc)     MODE=adhoc; shift ;;
    --notarize)  MODE=notarize; shift ;;
    --universal) ARCH=universal; shift ;;
    --arm64)     ARCH=arm64; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help|help) usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

version_from_plist() {
  sed -n 's:.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*:\1:p' \
    "$ROOT/Resources/Info.plist" | head -1
}

VERSION="$(version_from_plist)"
[[ -n "$VERSION" ]] || die "CFBundleShortVersionString missing in Resources/Info.plist"

# Filename: DiskRings-x.y.z[.adhoc tags].dmg
NAME_SUFFIX=""
[[ "$MODE" == adhoc ]] && NAME_SUFFIX="${NAME_SUFFIX}-adhoc"
[[ "$ARCH" == arm64 ]] && NAME_SUFFIX="${NAME_SUFFIX}-arm64"
DMG_BASENAME="DiskRings-${VERSION}${NAME_SUFFIX}.dmg"
DMG_PATH="$OUT_DIR/$DMG_BASENAME"
SUMS_PATH="$OUT_DIR/SHA256SUMS"

require_install_doc() {
  [[ -f "$ROOT/docs/install-adhoc.zh.txt" ]] \
    || die "missing docs/install-adhoc.zh.txt (source for ad-hoc 安装说明.txt)"
}

forbid_bad_guidance() {
  # Only reject copy-pasteable "turn security off" commands. Mentions that *forbid*
  # those actions (不要关闭 / 没有关闭 / Do not disable) are required by the PRD.
  local bad=0 f
  for f in "$ROOT/docs/install-adhoc.zh.txt" "$ROOT/docs/dmg-mac-verify.md" "$ROOT/README.md"; do
    [[ -f "$f" ]] || continue
    if grep -En 'csrutil[[:space:]]+disable|spctl[[:space:]]+--master-disable' "$f" >/dev/null; then
      # Allow if every match sits on a line that clearly prohibits running it
      while IFS= read -r hit; do
        line="${hit#*:}"
        if ! echo "$line" | grep -Eiq '不要|别|禁止|勿|没有|Do not|Don.t|Never|forbid|禁止：'; then
          echo "error: forbidden SIP/Gatekeeper-off command in $f:$hit" >&2
          bad=1
        fi
      done < <(grep -En 'csrutil[[:space:]]+disable|spctl[[:space:]]+--master-disable' "$f" || true)
    fi
  done
  [[ $bad -eq 0 ]] || die "remove SIP/Gatekeeper-off guidance before packaging"
}

print_plan() {
  cat <<EOF
DiskRings DMG plan
  version:     $VERSION  (from Resources/Info.plist CFBundleShortVersionString)
  sign mode:   $MODE
  arch:        $ARCH
  volume:      $VOLNAME
  output:      $DMG_PATH
  sums:        $SUMS_PATH
  ad-hoc doc:  docs/install-adhoc.zh.txt → 安装说明.txt (adhoc only)
  background:  Resources/dmg-background[@2x].png (designer Warm; icons 150,178 / 450,178)
  dry-run:     $DRY_RUN
EOF
}

check_notarize_env() {
  [[ -n "${IDENTITY:-}" ]] || {
    cat >&2 <<'EOF'
error: --notarize requires IDENTITY (Developer ID Application …).

  Example (you set these; this script never opens Keychain or Apple ID):
    export IDENTITY='Developer ID Application: Your Name (TEAMID)'
    # plus one notary auth method:
    export NOTARY_PROFILE='NotaryProfile'
    # or:  NOTARY_APPLE_ID=… NOTARY_PASSWORD=… NOTARY_TEAM_ID=…
    # or:  NOTARY_KEY=/path/to/AuthKey.p8 NOTARY_KEY_ID=… NOTARY_ISSUER=…

  Fall back without a Developer ID:
    ./scripts/package_dmg.sh --adhoc --universal
    # or:  ./build.sh dmg --adhoc --arm64
EOF
    exit 1
  }
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    return 0
  fi
  if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    return 0
  fi
  if [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    return 0
  fi
  cat >&2 <<'EOF'
error: --notarize needs notarytool credentials (NOTARY_PROFILE, or APPLE_ID trio, or API key trio).
  Fall back:  ./scripts/package_dmg.sh --adhoc
EOF
  exit 1
}

dry_run_checks() {
  info "dry-run: structure / naming / docs (no hdiutil, no codesign, no network)"
  require_install_doc
  forbid_bad_guidance
  [[ -f "$ROOT/Resources/dmg-background.png" ]] || die "missing Resources/dmg-background.png"
  [[ -f "$ROOT/Resources/dmg-background@2x.png" ]] || die "missing Resources/dmg-background@2x.png"
  [[ -f "$ROOT/Resources/Info.plist" ]] || die "missing Info.plist"
  [[ -f "$ROOT/scripts/make-app-bundle.sh" ]] || die "missing make-app-bundle.sh"
  [[ -x "$ROOT/build.sh" || -f "$ROOT/build.sh" ]] || die "missing build.sh"
  # Naming expectations
  case "$MODE-$ARCH" in
    notarize-universal) [[ "$DMG_BASENAME" == "DiskRings-${VERSION}.dmg" ]] || die "bad name $DMG_BASENAME" ;;
    notarize-arm64)     [[ "$DMG_BASENAME" == "DiskRings-${VERSION}-arm64.dmg" ]] || die "bad name $DMG_BASENAME" ;;
    adhoc-universal)    [[ "$DMG_BASENAME" == "DiskRings-${VERSION}-adhoc.dmg" ]] || die "bad name $DMG_BASENAME" ;;
    adhoc-arm64)        [[ "$DMG_BASENAME" == "DiskRings-${VERSION}-adhoc-arm64.dmg" ]] || die "bad name $DMG_BASENAME" ;;
    *) die "internal: mode/arch $MODE/$ARCH" ;;
  esac
  # Ad-hoc install doc must mention Sequoia path and forbid bad advice
  grep -q '隐私与安全性' "$ROOT/docs/install-adhoc.zh.txt" || die "install doc missing 隐私与安全性"
  grep -q '仍要打开' "$ROOT/docs/install-adhoc.zh.txt" || die "install doc missing 仍要打开"
  grep -q 'xattr' "$ROOT/docs/install-adhoc.zh.txt" || die "install doc missing optional xattr"
  grep -q '不要关闭 SIP' "$ROOT/docs/install-adhoc.zh.txt" || die "install doc must forbid SIP off"
  grep -q '{150, 178}' "$ROOT/scripts/package_dmg.sh" || die "App icon position must be {150, 178}"
  grep -q '{450, 178}' "$ROOT/scripts/package_dmg.sh" || die "Applications icon position must be {450, 178}"
  if [[ "$MODE" == notarize ]]; then
    info "dry-run notarize: would require IDENTITY + NOTARY_* (not checked unless set)"
    if [[ -n "${IDENTITY:-}" ]]; then
      info "IDENTITY is set (length ${#IDENTITY})"
    else
      warn "IDENTITY unset — a real --notarize run would fail (use --adhoc to fall back)"
    fi
  fi
  print_plan
  info "dry-run OK — on macOS, re-run without --dry-run to produce the DMG"
  echo "    example:  ./scripts/package_dmg.sh --adhoc --arm64"
  echo "    or:       ./build.sh dmg --adhoc --universal"
}

# --- Linux / non-Darwin: only dry-run ---
if [[ "$(uname -s)" != "Darwin" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry_run_checks
    exit 0
  fi
  print_plan
  cat >&2 <<EOF
error: DMG packaging must run on macOS (needs hdiutil, codesign, AppKit build).

  This is a Linux/box host. Scripts and docs are ready; the binary .dmg is only
  produced on a Mac. After copying the tree (e.g. ~/Downloads/DiskRings):

    ./scripts/package_dmg.sh --adhoc --arm64
    ./scripts/package_dmg.sh --adhoc --universal
    ./build.sh dmg --adhoc --arm64

  Validate packaging inputs here anytime:

    ./scripts/package_dmg.sh --dry-run --adhoc --universal

  Notarized builds need IDENTITY + NOTARY_* on the Mac (see script header).
EOF
  exit 1
fi

# --- Darwin path ---
require_install_doc
forbid_bad_guidance
[[ -f "$ROOT/Resources/dmg-background.png" ]] || die "missing Resources/dmg-background.png"
[[ -f "$ROOT/Resources/dmg-background@2x.png" ]] || die "missing Resources/dmg-background@2x.png"

if [[ $DRY_RUN -eq 1 ]]; then
  dry_run_checks
  exit 0
fi

[[ "$MODE" == notarize ]] && check_notarize_env

mkdir -p "$OUT_DIR"
APP_SRC="$ROOT/build/$APP_NAME"

build_app() {
  info "building $APP_NAME (ARCH=$ARCH) via ./build.sh app"
  case "$ARCH" in
    universal) ARCH=universal "$ROOT/build.sh" app ;;
    arm64)     ARCH=arm64 "$ROOT/build.sh" app ;;
    *) die "arch $ARCH" ;;
  esac
  [[ -d "$APP_SRC" ]] || die "expected $APP_SRC after build.sh app"
}

if [[ $SKIP_BUILD -eq 0 ]]; then
  build_app
else
  [[ -d "$APP_SRC" ]] || die "--skip-build but $APP_SRC missing; run ./build.sh app first"
fi

sign_app() {
  if [[ "$MODE" == adhoc ]]; then
    info "ad-hoc codesign (NOT notarized — filename will include -adhoc)"
    codesign --force --deep --sign - "$APP_SRC"
    codesign -dv "$APP_SRC" 2>&1 | sed 's/^/    /' || true
    return 0
  fi
  info "Developer ID codesign (hardened runtime + timestamp)"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_SRC"
  codesign -dv --verbose=2 "$APP_SRC" 2>&1 | sed 's/^/    /' || true
}

notarize_app() {
  local zip="$OUT_DIR/DiskRings-notarize-submit.zip"
  info "zipping app for notarytool"
  rm -f "$zip"
  ditto -c -k --keepParent "$APP_SRC" "$zip"
  local args=(submit "$zip" --wait --progress)
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    args+=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY:-}" ]]; then
    args+=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    args+=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
  fi
  info "notarytool submit (waiting for Accepted)"
  xcrun notarytool "${args[@]}"
  info "stapler staple app"
  xcrun stapler staple "$APP_SRC"
  xcrun stapler validate "$APP_SRC"
  rm -f "$zip"
}

sign_app
[[ "$MODE" == notarize ]] && notarize_app

# --- Stage DMG contents ---
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/diskrings-dmg-XXXXXX")
cleanup() { rm -rf "$STAGE" "$OUT_DIR/.dmg-rw.dmg" "$OUT_DIR/.dmg-mount" 2>/dev/null || true; }
trap cleanup EXIT

info "staging DMG root → $STAGE"
ditto "$APP_SRC" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
# Prefer @2x (1200×800) as Finder background for Retina; 1x kept in Resources for tooling.
if [[ -f "$ROOT/Resources/dmg-background@2x.png" ]]; then
  cp "$ROOT/Resources/dmg-background@2x.png" "$STAGE/.background/background.png"
else
  cp "$ROOT/Resources/dmg-background.png" "$STAGE/.background/background.png"
fi
# Never ship layout-spec@2x.png
if [[ "$MODE" == adhoc ]]; then
  cp "$ROOT/docs/install-adhoc.zh.txt" "$STAGE/安装说明.txt"
fi

# Create RW image, configure Finder window, convert to UDZO
RW="$OUT_DIR/.dmg-rw.dmg"
MOUNT_DIR="$OUT_DIR/.dmg-mount"
rm -f "$RW" "$DMG_PATH"
mkdir -p "$MOUNT_DIR"

info "creating RW disk image"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
  -format UDRW -ov "$RW" >/dev/null

info "mounting to set icon layout (~600×400)"
# Mount privately; detach any prior
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$RW" \
  | awk 'END{print $1}')
[[ -n "$DEVICE" ]] || die "hdiutil attach failed"

# Bless background + icon positions via AppleScript (Finder).
# Window ~600×400; App left, Applications right.
# Failure here is non-fatal: the DMG still contains the app + Applications alias.
READABLE_NOTE=""
if [[ "$MODE" == adhoc ]]; then
  READABLE_NOTE='try
      set position of item "安装说明.txt" of container window to {300, 340}
    end try'
fi
osascript <<EOF || warn "Finder layout AppleScript failed (DMG still usable; drag-install works)"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 700, 500}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    try
      set background picture of opts to file ".background:background.png"
    end try
    -- Designer layout (pt, content origin top-left): App (150,178), Applications (450,178); icon 128.
    set position of item "$APP_NAME" of container window to {150, 178}
    set position of item "Applications" of container window to {450, 178}
    $READABLE_NOTE
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$MOUNT_DIR" -force || true
# Wait a moment if busy
sleep 1
hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true

info "converting to compressed UDZO → $DMG_PATH"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$RW"

if [[ "$MODE" == notarize ]]; then
  info "stapler staple DMG"
  xcrun stapler staple "$DMG_PATH" || warn "stapler on DMG failed (app is stapled; Gatekeeper may still tickle once)"
fi

# Checksums
info "writing $SUMS_PATH"
(
  cd "$OUT_DIR"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$DMG_BASENAME" > SHA256SUMS
  else
    sha256sum "$DMG_BASENAME" > SHA256SUMS
  fi
)

# Architecture report
BIN="$APP_SRC/Contents/MacOS/DiskRings"
if [[ -x "$BIN" ]]; then
  info "lipo -archs:"
  lipo -archs "$BIN" 2>/dev/null | sed 's/^/    /' || file "$BIN" | sed 's/^/    /'
fi

echo
info "DONE"
echo "    dmg:     $DMG_PATH"
echo "    size:    $(wc -c <"$DMG_PATH" | tr -d ' ') bytes"
echo "    sha256:  $(awk '{print $1}' "$SUMS_PATH")"
echo "    mode:    $MODE  (adhoc = NOT notarized; never claim otherwise)"
echo "    version: $VERSION"
echo "    open:    open \"$DMG_PATH\""
