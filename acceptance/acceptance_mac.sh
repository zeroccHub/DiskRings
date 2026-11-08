#!/usr/bin/env bash
# DiskRings R6 — manual acceptance on a Mac.
# Usage:  bash acceptance_mac.sh [/path/to/DiskRings]     (default: ./DiskRings next to this script)
#         AUTO=1 bash acceptance_mac.sh                    (no pauses)
# Scope : writes ONLY to /tmp/diskrings-accept/ and <project>/build/. NEVER uses sudo.
#         System paths (/System, /usr, ...) are only passed to DeletionGuard.check() — never deleted.
# Recover from anything: rm -rf /tmp/diskrings-accept  and  <project>/build.sh clean
set -euo pipefail

# ================================================================ helper library
# Pure text parsers (no side effects) — unit-tested on Linux by acceptance_mac_selftest.sh
# with captured macOS output. Source with DR_SOURCE_ONLY=1 to load only these functions.

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }   # bash 3.2 has no ${x,,}

# parse_df_mount: stdin = `df -P -k <dir>` output -> prints the mount point (may contain spaces)
parse_df_mount() {
  awk 'NR==2 { sub(/^[^ ]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+% +/, ""); print; exit }'
}
# parse_df_device: stdin = `df -P -k <dir>` output -> prints the device (first column)
parse_df_device() { awk 'NR==2 { print $1; exit }'; }
# parse_df_avail_kb: stdin = `df -P -k <dir>` output -> available KB (4th column)
parse_df_avail_kb() { awk 'NR==2 { print $4; exit }'; }

# parse_diskutil_type: stdin = `diskutil info <mountpoint>` -> lower-case fs type, e.g. "apfs".
# Uses "Type (Bundle):"; falls back to "File System Personality:" ("APFS", "Case-sensitive APFS" -> apfs).
parse_diskutil_type() {
  awk -F: '
    /^[[:space:]]*Type \(Bundle\):/ { v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); if (v != "") { b=v } }
    /^[[:space:]]*File System Personality:/ { v=tolower($2); gsub(/^[[:space:]]+/, "", v)
        if (v ~ /(^|[^a-z])apfs([^a-z]|$)/) { p="apfs" } else { split(v, w, /[[:space:]]+/); if (w[1] != "") { p=w[1] } } }
    END { if (b != "") print tolower(b); else if (p != "") print tolower(p) }'
}

# parse_mount_type <mountpoint>: stdin = `mount` output -> lower-case type for exactly that mount point.
# macOS line format: "/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse)"
parse_mount_type() {
  awk -v mp="$1" '{
    i = index($0, " on " mp " (");
    if (i > 0) { t = substr($0, i + length(" on " mp " (")); sub(/[,)].*/, "", t); print tolower(t); exit }
  }'
}

# is_apfs <type>: case-insensitive compare
is_apfs() { [[ "$(lower "$1")" == "apfs" ]]; }

# fs_type_of <dir>: diskutil first, mount(8) as fallback. Prints type or nothing.
fs_type_of() {
  local dir="$1" mp t=""
  mp="$(df -P -k "$dir" 2>/dev/null | parse_df_mount)" || true
  [[ -n "$mp" ]] || return 0
  t="$(diskutil info "$mp" 2>/dev/null | parse_diskutil_type)" || true
  [[ -n "$t" ]] || t="$(mount 2>/dev/null | parse_mount_type "$mp")" || true
  printf '%s' "$t"
}

# realdir <dir>: physical path without GNU `readlink -f` (/tmp -> /private/tmp on macOS)
realdir() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# mounted_below <dir...>: true if any mount point lies strictly below one of the given dirs
mounted_below() {
  local d m
  m="$(mount 2>/dev/null)" || return 1
  for d in "$@"; do
    [[ -n "$d" ]] || continue
    printf '%s\n' "$m" | grep -qF " on $d/" && return 0
  done
  return 1
}

# toolchain_status: decides WITHOUT invoking any /usr/bin shim (xcrun/swift/clang/cc/git would pop up
# the Command Line Tools installer on a Mac without CLT). Only xcode-select -p is called here; it never
# triggers the installer. Prints the developer dir on success; returns 1 (no dev dir) / 2 (dir missing).
toolchain_status() {
  local dev
  dev="$("${XCODE_SELECT:-/usr/bin/xcode-select}" -p 2>/dev/null)" || return 1
  [[ -n "$dev" ]] || return 1
  [[ -d "$dev" ]] || { printf '%s' "$dev"; return 2; }
  printf '%s' "$dev"
}

if [[ "${DR_SOURCE_ONLY:-0}" == 1 ]]; then return 0 2>/dev/null || exit 0; fi
# ================================================================ end of helper library


HERE="$(cd "$(dirname "$0")" && pwd)"
_DEF="$HERE/DiskRings"; [[ -d "$_DEF" ]] || _DEF="$HERE/.."   # in-package copy: acceptance/ lives inside the project
PROJ="$(cd "${1:-$_DEF}" && pwd)"   # pass the R6 project dir explicitly
W=/tmp/diskrings-accept
SIZE_MB="${SIZE_MB:-256}"
PASS=0; FAIL=0; NOTES=()

[[ "$(uname -s)" == "Darwin" ]] || { echo "This script is for macOS only."; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Do not run as root / with sudo."; exit 1; }
[[ -x "$PROJ/build.sh" ]] || { echo "build.sh not found in $PROJ"; exit 1; }

# ---------------------------------------------------------------- preflight (before ANY xcrun/swift/clang)
# What: checks that Xcode or the Command Line Tools are installed, WITHOUT touching /usr/bin/xcrun, swift,
#       clang, cc or git first (on a Mac without CLT those shims open Apple's installer dialog).
# Reads: `xcode-select -p` (prints the active developer dir; never opens the installer), then — only if that
#        dir exists — `xcrun --sdk macosx --show-sdk-path` and `xcrun -f swift` / `xcrun -f clang`.
# Writes: nothing. sudo: no. Risk: none. If it fails the script exits; nothing was created yet.
# Recovery / install (YOUR decision, the script never runs it):  xcode-select --install
#   (no sudo; opens Apple's GUI installer, writes /Library/Developer/CommandLineTools; several GB)
DEV_DIR="" ; tc_rc=0
DEV_DIR="$(toolchain_status)" || tc_rc=$?
if [[ $tc_rc -ne 0 ]]; then
  echo "PREFLIGHT FAILED: no usable developer tools."
  if [[ $tc_rc -eq 2 ]]; then echo "  xcode-select -p points to '$DEV_DIR', which does not exist."
  else echo "  xcode-select -p reports no active developer directory (Command Line Tools not installed)."; fi
  cat <<'HINT'
  To install them yourself (no sudo; opens Apple's installer window; needs network, several GB):
      xcode-select --install
  If xcode-select points to a deleted Xcode, choose the CLT instead (needs admin password, your decision):
      sudo xcode-select --switch /Library/Developer/CommandLineTools
  Then run this script again. Nothing was created or changed by this run.
HINT
  exit 3
fi
echo "preflight: developer dir = $DEV_DIR"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || SDK_PATH=""
SWIFT_BIN="$(xcrun -f swift 2>/dev/null)" || SWIFT_BIN=""
CLANG_BIN="$(xcrun -f clang 2>/dev/null)" || CLANG_BIN=""
echo "preflight: SDK = ${SDK_PATH:-?}  swift = ${SWIFT_BIN:-?}  clang = ${CLANG_BIN:-?}"
if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" || -z "$SWIFT_BIN" || -z "$CLANG_BIN" ]]; then
  echo "PREFLIGHT FAILED: developer dir exists but the macOS SDK, swift or clang is missing."
  echo "  Run './build.sh doctor' in $PROJ for details; reinstalling the CLT is your decision: xcode-select --install"
  exit 3
fi

step() { # step "<title>" "<what it reads/writes/deletes; sudo; risk; recovery>"
  echo; echo "================================================================"
  echo "STEP: $1"; echo "$2" | sed 's/^/  /'
  if [[ "${AUTO:-0}" != 1 ]]; then
    read -r -p "Press Enter to run, 's' to skip, 'q' to quit: " a </dev/tty
    case "$a" in s) echo "skipped"; return 1;; q) exit 0;; esac
  fi
  return 0
}
ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $*"; FAIL=$((FAIL+1)); NOTES+=("$*"); }
# unlock <dir>: ALWAYS in this order — clear user flags (-R nouchg, nouappnd), drop ACLs, then chmod u+w.
# Only ever called with paths below $W (checked). No sudo.
unlock() {
  local d="$1"
  case "$d" in /tmp/diskrings-accept/*|/tmp/diskrings-accept) ;; *) echo "unlock: refusing $d"; return 1;; esac
  [[ -e "$d" ]] || return 0
  chflags -R nouchg "$d" 2>/dev/null || true
  chflags -R nouappnd "$d" 2>/dev/null || true
  chmod -R -N "$d" 2>/dev/null || true
  chmod -R u+rwx "$d" 2>/dev/null || true
}
snapshot() { (cd "$1" && { find . -print 2>/dev/null || true; } | LC_ALL=C sort); }

# ---------------------------------------------------------------- 0
if step "0. Environment info (read-only)" \
"Reads: sw_vers, uname, xcrun, mount table. Writes: nothing. sudo: no. Risk: none."; then
  sw_vers; uname -m; xcrun swiftc --version 2>&1 | head -2 || true
  (cd "$PROJ" && ./build.sh doctor) || bad "build.sh doctor failed"
fi

# ---------------------------------------------------------------- 1
if step "1. Build + tests" \
"Runs: ./build.sh test, ./build.sh (and 'swift test' only if SwiftPM+XCTest are available).
Writes: $PROJ/build/ and $PROJ/.build/ only. sudo: no.
Risk: CPU time. Recovery: ./build.sh clean ; rm -rf $PROJ/.build"; then
  (cd "$PROJ" && ./build.sh test) && ok "build.sh test" || bad "build.sh test"
  (cd "$PROJ" && ./build.sh) && ok "build.sh (app binary)" || bad "build.sh build"
  if (cd "$PROJ" && swift --version >/dev/null 2>&1 && swift test 2>&1 | tail -15); then
    ok "swift test (note: tests named R6: all tests expected to pass (116 on Linux incl. R3-R6 review tests); build.sh test 22/22)"
  else
    echo "  swift test failed or unavailable (CLT-only Macs lack XCTest). See output above; R6 expects no failures."
  fi
fi
BIN="$PROJ/build/DiskRings"

# ---------------------------------------------------------------- 2
if step "2. Create test area and verify it is on APFS" \
"Creates: $W (mkdir). Reads (read-only): 'df -P -k $W' (device + mount point; /tmp is a symlink to
/private/tmp, the mount point is usually /System/Volumes/Data), then 'diskutil info <mount point>'
('Type (Bundle)', fallback 'File System Personality'), fallback 'mount' (type in parentheses). Case-insensitive.
sudo: no. Risk: none. Recovery: rm -rf $W"; then
  mkdir -p "$W"
  df -P -k "$W" | sed 's/^/  /'
  MP="$(df -P -k "$W" | parse_df_mount)"
  T_DU="$(diskutil info "$MP" 2>/dev/null | parse_diskutil_type)" || T_DU=""
  T_MO="$(mount | parse_mount_type "$MP")" || T_MO=""
  echo "  real path: $(realdir "$W")   mount point: $MP   diskutil: ${T_DU:-?}   mount: ${T_MO:-?}"
  FSTYPE="${T_DU:-$T_MO}"
  if is_apfs "$FSTYPE"; then ok "APFS ($FSTYPE on $MP)"
  else bad "$W is not on APFS (type '${FSTYPE:-unknown}' on '$MP'); clone steps will be meaningless"; fi
fi

# ---------------------------------------------------------------- 3
if step "3. Make big file, APFS clones, hard link" \
"Writes: $W/data/big.bin (${SIZE_MB} MB random, from /dev/urandom via dd), $W/data/clone1.bin + sub/clone2.bin (cp -c = APFS clone),
$W/data/hard.bin (hard link to big.bin), $W/data/modclone.bin (clone then 1 MB overwritten).
Needs ~${SIZE_MB}+ MB free disk. sudo: no. Risk: disk space only. Recovery: rm -rf $W/data"; then
  rm -rf "$W/data"; mkdir -p "$W/data/sub"
  echo "  free before: $(df -P -k "$W" | parse_df_avail_kb) KB"
  dd if=/dev/urandom of="$W/data/big.bin" bs=1048576 count="$SIZE_MB" 2>/dev/null
  cp -c "$W/data/big.bin" "$W/data/clone1.bin"
  cp -c "$W/data/big.bin" "$W/data/sub/clone2.bin"
  ln "$W/data/big.bin" "$W/data/hard.bin"
  cp -c "$W/data/big.bin" "$W/data/modclone.bin"
  dd if=/dev/urandom of="$W/data/modclone.bin" bs=1048576 count=1 conv=notrunc 2>/dev/null
  sync; echo "  free after:  $(df -P -k "$W" | parse_df_avail_kb) KB (should drop by ~$SIZE_MB MB + ~1 MB, not 4x)"
  ls -li "$W/data" "$W/data/sub"
fi

# ---------------------------------------------------------------- 4
if step "4. Probe raw clone attributes with getattrlist (independent C helper)" \
"Compiles $W/cloneprobe (clang, writes only $W). Reads ATTR_CMNEXT_CLONEID / PRIVATESIZE / EXT_FLAGS of the test files.
Purpose: verify on a REAL file the buffer order the parser assumes, and whether pure clones share a clone id.
sudo: no. Risk: none. Recovery: rm $W/cloneprobe*"; then
  cat > "$W/cloneprobe.c" <<'C'
#include <sys/attr.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    struct attrlist al = {0};
    al.bitmapcount = ATTR_BIT_MAP_COUNT;
    al.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_FILEID;
    al.fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE;
    al.forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS;
    char buf[512]; memset(buf, 0, sizeof buf);
    if (getattrlist(argv[i], &al, buf, sizeof buf, FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0) { perror(argv[i]); continue; }
    char *p = buf + 4; attribute_set_t rs; memcpy(&rs, p, sizeof rs); p += sizeof rs;
    uint64_t fid = 0, cid = 0, fl = 0; uint32_t lc = 0; int64_t alloc = 0, priv = -1;
    if (rs.commonattr & ATTR_CMN_FILEID) { memcpy(&fid, p, 8); p += 8; }
    if (rs.fileattr & ATTR_FILE_LINKCOUNT) { memcpy(&lc, p, 4); p += 4; }
    if (rs.fileattr & ATTR_FILE_ALLOCSIZE) { memcpy(&alloc, p, 8); p += 8; }
    if (rs.forkattr & ATTR_CMNEXT_PRIVATESIZE) { memcpy(&priv, p, 8); p += 8; }
    if (rs.forkattr & ATTR_CMNEXT_CLONEID) { memcpy(&cid, p, 8); p += 8; }
    if (rs.forkattr & ATTR_CMNEXT_EXT_FLAGS) { memcpy(&fl, p, 8); p += 8; }
    printf("%-28s ino=%llu links=%u alloc=%lld private=%lld cloneid=%llu extflags=0x%llx returned_ext=0x%x\n",
      strrchr(argv[i], '/') + 1, fid, lc, alloc, priv, cid, fl, rs.forkattr);
  }
  return 0;
}
C
  xcrun clang -Wall -o "$W/cloneprobe" "$W/cloneprobe.c"
  "$W/cloneprobe" "$W/data/big.bin" "$W/data/clone1.bin" "$W/data/sub/clone2.bin" "$W/data/hard.bin" "$W/data/modclone.bin" | tee "$W/cloneprobe.out"
  echo "  EXPECT: big/clone1/clone2 share one cloneid (else DiskRings clone dedup never triggers -> P1);"
  echo "          extflags has 0x1 (EF_MAY_SHARE_BLOCKS); modclone shows private ~1 MB (or a new cloneid)."
  ids=$(awk '/^(big|clone1|clone2)\.bin/{for(i=1;i<=NF;i++) if($i ~ /^cloneid=/) print $i}' "$W/cloneprobe.out" | sort -u | wc -l | tr -d ' ')
  [[ "$ids" == 1 ]] && ok "pure clones share clone id" || bad "pure clones have $ids different clone ids (dedup by cloneid will not work)"
fi

# ---------------------------------------------------------------- 5
if step "5. Compare DiskRings --cli with du -sk" \
"Runs: $BIN --cli $W/data (read-only scan), du -sk (read-only). Writes: $W/*.txt only. sudo: no. Risk: none.
du counts every clone in full (it does not know APFS sharing) but counts hard links once."; then
  [[ -x "$BIN" ]] || { bad "binary missing; run step 1"; }
  "$BIN" --cli "$W/data" | tee "$W/cli.txt"
  du -sk "$W/data" | tee "$W/du.txt"; du -sk "$W/data"/* "$W/data/sub"/* 2>/dev/null
  echo
  echo "  EXPECT (SIZE_MB=$SIZE_MB): du -sk ≈ 4 x $SIZE_MB MB (big + clone1 + clone2 + modclone; hard.bin once)."
  echo "          DiskRings ACTUAL ≈ 1 x $SIZE_MB MB + ~1 MB (if clone ids match), LOGICAL ≈ 4 x $SIZE_MB MB;"
  echo "          report shows 1 hard-link duplicate and ≥2 clone duplicates."
  grep -Eq "1 hard-link duplicates" "$W/cli.txt" && ok "hard link counted once" || bad "hard-link duplicate count != 1"
  grep -Eq "[2-9][0-9]* clone duplicates|[1-9][0-9]+ clone duplicates" "$W/cli.txt" && ok "clone duplicates detected" || bad "no clone duplicates detected by DiskRings"
  echo "  Judge the ACTUAL vs du numbers above by eye and note them in the report."
fi

# ---------------------------------------------------------------- 6
if step "6. DeletionGuard probe: CHECK ONLY for system paths (never deletes)" \
"Compiles $W/guardprobe from the project's DiskScanCore sources (writes $W only).
Modes 'check'/'preflight' only evaluate; 'delete' runs the app's real DeletionList.deleteAll +
PosixRecursiveDeleter but is hard-limited in code to realpath under /private/tmp/diskrings-accept/.
This step: check only (/System, /usr, case variants, '..', ~, /Volumes/*, caution paths). sudo: no. Risk: none."; then
  mkdir -p "$W/guardprobe-src"
  cat > "$W/guardprobe-src/main.swift" <<'SW'
import Foundation
// guardprobe — modes:
//   check <paths...>      : DeletionGuard.live().evaluate(path) only (NEVER deletes)
//   preflight <paths...>  : evaluate(path, preflight: true) only (NEVER deletes)
//   delete <path>         : real DeletionList.deleteAll(PosixRecursiveDeleter) — path must
//                           realpath to /private/tmp/diskrings-accept/ (hard-coded), else refused.
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: check|preflight|delete <path>..."); exit(64) }
let g = DeletionGuard.live()
func show(_ v: DeletionGuard.Verdict, _ p: String) {
    let s = v.reason.map { "BLOCKED  " + $0.description } ?? (v.caution.map { "CAUTION  " + $0.description } ?? "ALLOWED ")
    print("\(s)  \(p)  [canonical: \(v.canonicalPath)]")
}
switch args[1] {
case "check", "preflight":
    for p in args.dropFirst(2) { show(g.evaluate(p, preflight: args[1] == "preflight"), p) }
    exit(0)
case "delete":
    let target = args[2]
    guard let rp = realpath(target, nil) else { print("no such path"); exit(2) }
    let real = String(cString: rp); free(rp)
    let area = "/private/tmp/diskrings-accept/"
    guard real.hasPrefix(area), real.count > area.count else { print("REFUSED: outside test area: \(real)"); exit(3) }
    let parent = (real as NSString).deletingLastPathComponent
    let name = (real as NSString).lastPathComponent
    Task { @MainActor in
        do {
            let r = try ScanEngine().scanBlocking(path: parent)
            guard let node = r.root.children.first(where: { $0.name == name }) else { print("not found in scan"); exit(2) }
            let list = DeletionList(deletionGuard: g)
            guard list.add(node) else { print("BLOCKED at add: \(String(describing: list.blockedReason(for: node)))"); exit(4) }
            let out = await list.deleteAll(using: PosixRecursiveDeleter(), confirmedCautions: false)
            for f in out.failed { print("FAILED  \(f.node.path): \(f.error)") }
            for d in out.deleted { print("DELETED \(d.path)") }
            exit(out.failed.isEmpty ? 0 : 5)
        } catch { print("scan error: \(error)"); exit(6) }
    }
    dispatchMain()
default:
    print("unknown mode"); exit(64)
}
SW
  ( cd "$PROJ" && xcrun swiftc -O -module-name GuardProbe Sources/DiskScanCore/*.swift "$W/guardprobe-src/main.swift" -o "$W/guardprobe" )
  H="$HOME"
  MUST_BLOCK=( / /System /System/Library /usr /usr/bin /bin /sbin /Library /Applications /Users /Volumes /private /private/var
    /private/var/db /etc /etc/hosts /var /var/db /tmp /System/Volumes/Data /System/Volumes/Data/usr "$H" "$(dirname "$H")"
    /USR /SYSTEM /system/library /Library/APPLE /users "$(echo "$H" | tr '[:lower:]' '[:upper:]')" /system/volumes/data
    /tmp/../usr /usr/local/../bin "$H/../.." "$W/../../usr" )
  for v in /Volumes/*; do MUST_BLOCK+=("$v"); done
  "$W/guardprobe" check "${MUST_BLOCK[@]}" | tee "$W/guard.txt"
  n=$(grep -vc '^BLOCKED' "$W/guard.txt" || true)
  [[ "$n" == 0 ]] && ok "all protected paths / case variants / '..' paths blocked" || bad "$n protected path(s) not BLOCKED (see guard.txt)"
  grep -q "unsafe path" "$W/guard.txt" && ok "'..' refused as unsafe path" || bad "'..' not refused"
  echo "  Spelling check (canonical should show on-disk case via F_GETPATH, e.g. /usr -> /usr):"
  "$W/guardprobe" check /USR/LOCAL /usr/LOCAL "$W" | tee "$W/spelling.txt"
  echo "  Caution paths (check only; expect CAUTION, nothing is touched):"
  "$W/guardprobe" check /Library/LaunchDaemons/com.example.none.plist /Applications/Safari.app /private/var/folders | tee "$W/caution.txt"
  [[ $(grep -c '^CAUTION\|^BLOCKED' "$W/caution.txt") == 3 ]] && ok "caution paths flagged" || bad "caution paths not all flagged"
  echo "  Policy (expected ALLOWED):"; "$W/guardprobe" check /usr/local/share "$H/Downloads"
fi

# ---------------------------------------------------------------- 6b
if step "6b. Preflight on temp data: mounted disk image inside a folder (must be refused as a whole)" \
"Creates $W/img.dmg (20 MB APFS image, hdiutil create, no sudo) and attaches it at $W/vol/mnt (hdiutil attach
-nobrowse -mountpoint, no sudo; Finder won't show it). Puts files in $W/vol and in the image.
Then guardprobe preflight + delete on $W/vol: expected BLOCKED 'contains another volume', NOTHING deleted.
Writes: $W only. sudo: no. Risk: an attached image until detached. Recovery: hdiutil detach $W/vol/mnt"; then
  rm -rf "$W/vol"; mkdir -p "$W/vol/mnt"; for i in 1 2 3; do echo x > "$W/vol/f$i"; done
  hdiutil create -quiet -size 20m -fs APFS -volname DRACC -ov "$W/img.dmg"
  hdiutil attach -quiet -nobrowse -mountpoint "$W/vol/mnt" "$W/img.dmg"
  echo inside > "$W/vol/mnt/inside.txt"
  "$W/guardprobe" preflight "$W/vol" | tee "$W/pf-mount.txt"
  grep -q "^BLOCKED" "$W/pf-mount.txt" && ok "preflight refuses folder containing a mount" || bad "preflight allowed folder containing a mount"
  "$W/guardprobe" delete "$W/vol" || true
  [[ -f "$W/vol/f1" && -f "$W/vol/f2" && -f "$W/vol/f3" && -f "$W/vol/mnt/inside.txt" ]] && ok "nothing deleted (no half-delete)" || bad "files were deleted around/inside a mount!"
  hdiutil detach -quiet "$W/vol/mnt" && ok "image detached" || bad "detach failed: run hdiutil detach $W/vol/mnt"
fi

# ---------------------------------------------------------------- 6c
if step "6c. Real deletes inside $W: normal + symlinks, then ALL-OR-NOTHING refusal (nothing may change)" \
"All under $W only. (a) normal folder with nested dirs + symlinks to $W/keep and to /usr -> deleted, targets survive.
(b) folders that must be REFUSED AS A WHOLE, compared by full file listing before/after:
    ro    = read-only (chmod 555) subfolder 2 levels deep        uchg  = 'chflags uchg' file (user flag, no sudo)
    uappnd= 'chflags uappnd' file                                 dirlk = 'chflags uchg' on a non-empty subfolder
    acl   = file with ACL 'everyone deny delete' (chmod +a, own file, no sudo)      R6: must be refused (acl_get_link_np)
    aclch = folder with ACL 'everyone deny delete_child'                          R6: must be refused
    aclinh= INHERITED deny: 'everyone deny delete,file_inherit' on a folder, then a new file is created in it
    unrd  = unreadable (chmod 000) subfolder
(schg/sappnd/SF_* need root and are covered by unit tests + step 6 only.)
Writes/deletes: $W/del-* only. sudo: no. Risk: none outside $W.
Recovery (this order!): chflags -R nouchg $W; chflags -R nouappnd $W; chmod -R -N $W; chmod -R u+w $W"; then
  rm -rf "$W/del-ok" "$W/keep"; mkdir -p "$W/del-ok/a/b" "$W/keep"; echo keep > "$W/keep/precious.txt"
  echo x > "$W/del-ok/a/b/f.txt"; ln -s "$W/keep" "$W/del-ok/link-to-keep"; ln -s /usr "$W/del-ok/link-to-usr"
  "$W/guardprobe" delete "$W/del-ok" && [[ ! -e "$W/del-ok" ]] && ok "normal delete in /tmp works" || bad "delete of $W/del-ok failed"
  [[ -f "$W/keep/precious.txt" ]] && ok "symlink target in $W survived" || bad "symlink was followed!"
  [[ -d /usr/bin ]] && ok "/usr untouched" || bad "/usr missing?!"
  "$W/guardprobe" delete /usr/bin >/dev/null 2>&1 && bad "probe would delete outside test area" || ok "probe refuses outside test area"
  for kind in ro uchg uappnd dirlk acl aclch aclinh unrd; do
    d="$W/del-$kind"; unlock "$d"; rm -rf "$d"
    mkdir -p "$d/a/sub"; for i in $(seq 1 30); do echo x > "$d/f$i"; done
    for i in 1 2 3; do echo x > "$d/a/g$i"; echo x > "$d/a/sub/h$i"; done
    case $kind in
      ro)     chmod 555 "$d/a/sub" ;;
      uchg)   chflags uchg "$d/a/sub/h2" ;;
      uappnd) chflags uappnd "$d/a/sub/h2" ;;
      dirlk)  chflags uchg "$d/a/sub" ;;
      acl)    chmod +a "everyone deny delete" "$d/a/sub/h2" ;;
      aclch)  chmod +a "everyone deny delete_child" "$d/a/sub" ;;
      aclinh) chmod +a "everyone deny delete,file_inherit" "$d/a/sub"; echo x > "$d/a/sub/inherited"
              ls -le "$d/a/sub/inherited" | sed 's/^/    /' ;;  # should show 'inherited' deny entry
      unrd)   chmod 000 "$d/a/sub" ;;
    esac
    snapshot "$d" > "$W/before-$kind.txt"
    "$W/guardprobe" preflight "$d" | tee "$W/pf-$kind.txt"
    "$W/guardprobe" delete "$d" | tee "$W/del-$kind.txt" || true
    snapshot "$d" > "$W/after-$kind.txt"
    if cmp -s "$W/before-$kind.txt" "$W/after-$kind.txt"; then
      grep -q '^BLOCKED' "$W/pf-$kind.txt" && ok "$kind: refused as a whole, file listing unchanged ($(wc -l < "$W/before-$kind.txt" | tr -d ' ') entries)" \
        || bad "$kind: listing unchanged but preflight did not report BLOCKED (check del-$kind.txt)"
    else
      bad "$kind: FILES CHANGED — diff $W/before-$kind.txt $W/after-$kind.txt ($(diff "$W/before-$kind.txt" "$W/after-$kind.txt" | grep -c '^<') entries removed)"
    fi
    unlock "$d"
  done
fi

# ---------------------------------------------------------------- 7
if step "7. GUI: confirm defaults, progress sheet, Cancel, Quit (⌘Q) during deletion, disabled menus (manual)" \
"Builds/opens build/DiskRings.app (writes $PROJ/build only). Creates under $W/gui:
  small/ (1 file), big1/ and big2/ (~${GUI_FILES:-200000} empty files each in 200 subfolders), keep/ (never staged).
Stage ONLY items under $W/gui. Do NOT use 'Move to Trash' (it writes ~/.Trash).
The script checks every staged folder afterwards: it must be either COMPLETELY gone or its file listing UNCHANGED
(anything in between = half-deleted = FAIL). keep/ must be untouched.
sudo: no. Risk: deletes only $W/gui/* items you stage. Recovery: quit the app (or Force Quit); rm -rf $W/gui; ./build.sh clean"; then
  rm -rf "$W/gui"; mkdir -p "$W/gui/small" "$W/gui/keep"; echo x > "$W/gui/small/x"; echo y > "$W/gui/keep/y"
  n="${GUI_FILES:-200000}"; per=$(( n / 200 ))
  for big in big1 big2; do
    echo "  creating $n files under $W/gui/$big …"
    for i in $(seq 1 200); do mkdir -p "$W/gui/$big/d$i"; (cd "$W/gui/$big/d$i" && seq 1 "$per" | xargs touch); done
    snapshot "$W/gui/$big" > "$W/gui-$big-before.txt"
  done
  snapshot "$W/gui/keep" > "$W/gui-keep-before.txt"
  check_whole() { # <dir> <label>: gone entirely, or listing identical
    local d="$1" l="$2"
    if [[ ! -e "$d" ]]; then ok "$l: completely deleted"; return; fi
    snapshot "$d" > "$W/gui-$l-after.txt"
    if cmp -s "$W/gui-$l-before.txt" "$W/gui-$l-after.txt"; then ok "$l: untouched (listing identical)"
    else bad "$l: HALF-DELETED ($(diff "$W/gui-$l-before.txt" "$W/gui-$l-after.txt" | grep -c '^<') entries removed)"; fi
  }
  app_running() { pgrep -f "$PROJ/build/DiskRings.app/Contents/MacOS/DiskRings" >/dev/null 2>&1; }
  (cd "$PROJ" && ./build.sh app) || bad "app build failed"

  echo; echo "  --- 7A/7B: defaults, progress, disabled menus, Cancel ---"
  open "$PROJ/build/DiskRings.app"
  cat <<'TXT'
  A. Scan Folder… -> /tmp/diskrings-accept/gui. Add 'small'. Delete Permanently…: press RETURN -> must CANCEL;
     press Esc -> nothing; then click 'Delete' -> small is gone.
  B. Add 'big1'. Delete Permanently… -> Delete. While the progress sheet is up, open the File menu:
     'Scan Folder or Volume…' (⌘O) and 'Rescan' (⌘R) must be GREYED; pressing ⌘O / ⌘R must do nothing (beep).
     Also the Delete menu items must be greyed. Then press Cancel while it says 'Checking…' or 'Verifying…'.
     Expect: report says cancelled / not attempted; big1 untouched.
  C. Now press ⌘Q (no deletion running): the app must quit immediately.
TXT
  read -r -p "  A-C done? Return=Cancel default, ⌘O/⌘R greyed during deletion, quit after cancel immediate? (y/n) " a </dev/tty || true
  [[ "$a" == y ]] && ok "GUI 7A-C: user confirms" || bad "GUI 7A-C: user reported a problem"
  sleep 2; app_running && bad "7C: app still running after ⌘Q" || ok "7C: app exited"
  [[ ! -e "$W/gui/small" ]] && ok "A: small deleted after explicit Delete" || bad "A: small still present"
  check_whole "$W/gui/big1" big1

  echo; echo "  --- 7D: ⌘Q DURING deletion (must finish current item, then quit; nothing half-deleted) ---"
  open "$PROJ/build/DiskRings.app"
  cat <<'TXT'
  D. Scan /tmp/diskrings-accept/gui. Add 'big1' AND 'big2'. Delete Permanently… -> Delete.
     As soon as the sheet says 'Deleting item 1 of 2' press ⌘Q (press it 2-3 times, that must be harmless).
     Expect: sheet shows 'Quitting…', the app quits by itself after item 1 is finished (may take seconds);
     big2 is not attempted. Do NOT Force Quit unless it hangs > 2 minutes (that would be a FAIL to report).
TXT
  read -r -p "  Press Enter once the app has quit by itself (or type 'hang' if it did not quit): " a </dev/tty || true
  # R6 7D (P2, fixed in R7): Cmd-Q used to beep and the sheet kept showing progress text.
  read -r -p "  7D-feedback: did EVERY ⌘Q press stay silent (no beep) AND did 'Quitting…' appear within ~1 s? [y/n] " fb </dev/tty || true
  [[ "$fb" == y ]] && ok "7D: no beep, immediate 'Quitting…'" || bad "7D: beep or delayed 'Quitting…' feedback (R6 P2 regression)"
  [[ "$a" == hang ]] && bad "7D: app did not quit after ⌘Q during deletion (terminateLater never replied)"
  for _ in 1 2 3 4 5; do app_running || break; sleep 1; done
  app_running && bad "7D: app still running" || ok "7D: app quit"
  check_whole "$W/gui/big1" big1
  check_whole "$W/gui/big2" big2
  [[ -e "$W/gui/big2" ]] && ok "7D: big2 (not attempted) still present" || bad "7D: big2 was deleted although quit was requested during item 1"
  check_whole "$W/gui/keep" keep
fi

# ---------------------------------------------------------------- 8
if step "8. Cleanup" \
"Detaches the test disk image if still attached; then for $W: chflags -R nouchg, chflags -R nouappnd, chmod -R -N (ACLs),
chmod -R u+w — in that order — and only then rm -rf $W. Refuses to rm if anything is still mounted below $W.
Project build/ kept (./build.sh clean yourself). sudo: no. Risk: loses test files/logs (copy $W/*.txt first)."; then
  WREAL="$(realdir "$W")" || WREAL=""   # mount(8) shows /private/tmp/..., not /tmp/...
  if mounted_below "$W" "$WREAL"; then hdiutil detach -quiet "$W/vol/mnt" || true; fi
  if mounted_below "$W" "$WREAL"; then bad "still mounted below $W — not deleting; run: hdiutil detach $W/vol/mnt"; else
    unlock "$W"
    if [[ "$W" == /tmp/diskrings-accept && -d "$W" && ! -L "$W" ]]; then rm -rf -- "$W" && ok "cleaned $W" || true; fi
    if [[ -e "$W" ]]; then bad "$W still exists (locked entries?) — run the Recovery commands of step 6c, then rm -rf $W"; fi
  fi
fi

echo; echo "================ SUMMARY: $PASS passed, $FAIL failed"
for n in ${NOTES[@]+"${NOTES[@]}"}; do echo " - $n"; done
