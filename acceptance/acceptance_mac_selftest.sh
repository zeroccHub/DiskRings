#!/usr/bin/env bash
# Offline self-test of acceptance_mac.sh's text parsers + preflight ordering (runs on Linux or macOS;
# touches nothing outside a mktemp dir it removes). Usage: bash acceptance_mac_selftest.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DR_SOURCE_ONLY=1 source "$HERE/acceptance_mac.sh"
set +e
P=0; F=0
t() { if [[ "$2" == "$3" ]]; then P=$((P+1)); else F=$((F+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }

DF_DATA='Filesystem     1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s5    482797652 210123456 250000000    46%    /System/Volumes/Data'
DF_SPACE='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk5s1 20000 1200 18800 7% /Volumes/My Disk 2'
t df_mount   "$(printf '%s\n' "$DF_DATA" | parse_df_mount)" "/System/Volumes/Data"
t df_dev     "$(printf '%s\n' "$DF_DATA" | parse_df_device)" "/dev/disk3s5"
t df_avail   "$(printf '%s\n' "$DF_DATA" | parse_df_avail_kb)" "250000000"
t df_space   "$(printf '%s\n' "$DF_SPACE" | parse_df_mount)" "/Volumes/My Disk 2"

# Sample macOS 15.5 output (abridged), plus variants
DU_SAMPLE='   Device Identifier:         disk3s5
   Mount Point:               /System/Volumes/Data
   File System Personality:   APFS
   Type (Bundle):             apfs
   Name (User Visible):       APFS'
DU_UPPER='   File System Personality:   APFS
   Type (Bundle):             APFS'
DU_NOBUNDLE='   File System Personality:   Case-sensitive APFS'
DU_HFS='   File System Personality:   Journaled HFS+
   Type (Bundle):             hfs'
t du_sample    "$(printf '%s\n' "$DU_SAMPLE" | parse_diskutil_type)" "apfs"
t du_upper    "$(printf '%s\n' "$DU_UPPER" | parse_diskutil_type)" "apfs"
t du_fallback "$(printf '%s\n' "$DU_NOBUNDLE" | parse_diskutil_type)" "apfs"
t du_hfs      "$(printf '%s\n' "$DU_HFS" | parse_diskutil_type)" "hfs"
t du_empty    "$(printf '' | parse_diskutil_type)" ""

MOUNT='/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
devfs on /dev (devfs, local, nobrowse)
/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse, protect, root data)
/dev/disk5s1 on /Volumes/My Disk 2 (msdos, local, nodev, nosuid, noowners)
/dev/disk6s1 on /private/tmp/diskrings-accept/vol/mnt (apfs, local, nodev, nosuid, journaled, noowners, nobrowse, mounted by tester)'
t mo_data  "$(printf '%s\n' "$MOUNT" | parse_mount_type /System/Volumes/Data)" "apfs"
t mo_root  "$(printf '%s\n' "$MOUNT" | parse_mount_type /)" "apfs"
t mo_space "$(printf '%s\n' "$MOUNT" | parse_mount_type "/Volumes/My Disk 2")" "msdos"
t mo_none  "$(printf '%s\n' "$MOUNT" | parse_mount_type /nope)" ""
t mo_upper "$(printf '/dev/x on /V (APFS, local)\n' | parse_mount_type /V)" "apfs"

is_apfs "APFS" && t apfs_upper ok ok || t apfs_upper no ok
is_apfs "apfs" && t apfs_lower ok ok || t apfs_lower no ok
is_apfs "/" && t slash_not_apfs yes no || t slash_not_apfs no no   # the R6 bug: '/' from stat -f %T
is_apfs "" && t empty_not_apfs yes no || t empty_not_apfs no no

# mounted_below with a fake mount(8) on PATH
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/drselftest.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
printf '#!/bin/sh\ncat <<"M"\n%s\nM\n' "$MOUNT" > "$TMPD/mount"; chmod +x "$TMPD/mount"
OLDPATH="$PATH"; PATH="$TMPD:$PATH"
mounted_below /tmp/diskrings-accept /private/tmp/diskrings-accept && t below_real yes yes || t below_real no yes
mounted_below /tmp/diskrings-accept && t below_tmp_only yes no || t below_tmp_only no no   # why realdir is needed
mounted_below /Users && t below_none yes no || t below_none no no
PATH="$OLDPATH"

# toolchain_status with fake xcode-select
printf '#!/bin/sh\necho "xcode-select: error: unable to get active developer directory" >&2; exit 2\n' > "$TMPD/xs-none"
printf '#!/bin/sh\necho /Applications/Gone.app/Contents/Developer\n' > "$TMPD/xs-gone"
printf '#!/bin/sh\necho %s\n' "$TMPD" > "$TMPD/xs-ok"; chmod +x "$TMPD"/xs-*
rc=0; XCODE_SELECT="$TMPD/xs-none" toolchain_status >/dev/null || rc=$?; t tc_none "$rc" 1
rc=0; XCODE_SELECT="$TMPD/xs-gone" toolchain_status >/dev/null || rc=$?; t tc_gone "$rc" 2
rc=0; out="$(XCODE_SELECT="$TMPD/xs-ok" toolchain_status)" || rc=$?; t tc_ok "$rc/$out" "0/$TMPD"

# Static ordering check: no xcrun/swift/swiftc/clang/cc/git command before the preflight block.
pre_line=$(grep -n '^# -* preflight (before ANY xcrun' "$HERE/acceptance_mac.sh" | cut -d: -f1)
bad_lines=$(awk -v n="$pre_line" 'NR < n && !/^[[:space:]]*#/ && /(^|[;&|( `$"])(xcrun|swift|swiftc|clang|cc|git)([[:space:]]|$)/ {print NR": "$0}' "$HERE/acceptance_mac.sh")
t no_tool_before_preflight "$bad_lines" ""
# Every post-preflight use goes through xcrun or $PROJ (no bare /usr/bin/clang etc.)
t no_bare_usr_bin "$(grep -nE '/usr/bin/(clang|cc|swift|git|xcrun)' "$HERE/acceptance_mac.sh" | grep -vE '^[0-9]+:[[:space:]]*#' || true)" ""
# No GNU-only idioms
t no_gnu_idioms "$(grep -nE 'stat -f %T|stat -c|readlink -f|sed -i|date -d|du -b|df -h --|find .* -printf|xargs -r|mktemp --' "$HERE/acceptance_mac.sh" | grep -v '^[0-9]*:[[:space:]]*#' || true)" ""

echo "selftest: $P passed, $F failed"
[[ $F -eq 0 ]]
