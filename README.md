# DiskRings

> **Repository note (public-form / private GitHub):** This tree is the application source + packaging scripts only. Design/product comparison docs and any third-party binaries are intentionally excluded. Folder name is `DiskRings` (not a competitor codename).


DiskRings is a small native macOS disk usage analyzer written in Swift and AppKit. You pick a
folder or volume, it scans it in parallel, and it shows the result as an interactive sunburst
(ring) chart next to a sortable list. You can put items on a **deletion list** and then move
them to the Trash or delete them permanently.

> **Status: prototype.** The code is written on a Linux box with no AppKit or Darwin SDK, where
> only the portable parts are compiled and unit-tested (see
> [Verification](#verification-what-was-actually-built-and-tested)). Earlier on,
> `./build.sh test` (12/12) and `./build.sh app` were run on a real Mac (CLT 16.4, Swift 6.1.2, SDK 15.5,
> arm64). The one compile error that turned up has been fixed. The **features added since
> then** have **not** been compiled on a Mac yet: APFS clone accounting in the `getattrlistbulk`
> enumerator, the protection list UI, the volume sidebar and Quick Look.

## 普通用户：安装 DMG（无需编译）

终端用户**不需要**安装 Xcode、Command Line Tools，也**不需要**运行 `./build.sh`。

当前里程碑以**私发**为主（网盘 / 本机拷贝），当前默认私发 DMG；本仓库为私有备份，不默认公开 Release。文件名形如 `DiskRings-x.y.z-adhoc-arm64.dmg`（ad-hoc = 未 Apple 公证；arm64 = Apple Silicon）。

1. 拿到 DMG 后可用附带的 `SHA256SUMS` 校验：`shasum -a 256 DiskRings-….dmg`。
2. 双击打开 DMG → 将 **DiskRings** 拖到右侧 **Applications**。
3. 在「应用程序」中打开 DiskRings。若被 Gatekeeper 拦截：到 **系统设置 → 隐私与安全性 → 仍要打开**（详见盘内「安装说明.txt」）。**不要**关闭 SIP / 全局关闭 Gatekeeper。
4. 进入首页即可扫描使用。

开发者在本机打 DMG：见 [Package a DMG](#package-a-dmg-macos)。验收：`docs/dmg-mac-verify.md`。

---

## Clean-room statement

This is an independent implementation. The only input was a written architecture summary
of how a commercial disk analyzer is built in general: a bulk-attribute directory scan, a
bounded-concurrency traversal, an inode table for hard links, a layer-based sunburst, and a
staging list before deletion. No code, strings, images, icons, nibs, resources, binaries,
names or branding were copied from that product or from any reverse-engineering output.
All identifiers, UI text and visuals here are original. Syscall constants come from Apple's
public `<sys/attr.h>` / `<sys/vnode.h>` headers. There is no licensing, activation,
registration, update or telemetry code of any kind.

## Features

- **Volume sidebar.** It lists mounted volumes from
  `FileManager.mountedVolumeURLs(…, options: [.skipHiddenVolumes])` with name, available space
  (`volumeAvailableCapacityForImportantUsage`, or `volumeAvailableCapacity` as a fallback) and
  total capacity. It refreshes every 5 s and whenever a volume is mounted, unmounted or renamed
  (`NSWorkspace` notifications). One click scans a volume. Clicking the startup disk (`/`)
  scans **`/System/Volumes/Data`**, because the System volume is read-only and sealed and user
  data lives on the Data volume. **Scan Folder…** (`NSOpenPanel`) is still there. Scans show live
  progress and can be stopped.
- Fast scanning on macOS. `getattrlistbulk(2)` returns name, type, device, file id, link
  count, logical size and allocated size for a whole batch of entries in one syscall.
- Parallel traversal with a fixed number of worker threads. Sizes are added up from the
  bottom of the tree after the scan.
- Each hard link is counted once, keyed by `(device, inode)`. Extra links show as "hard link".
- **APFS clones are counted once (estimate).** The bulk scan also asks for
  `ATTR_CMNEXT_PRIVATESIZE`, `ATTR_CMNEXT_CLONEID` and `ATTR_CMNEXT_EXT_FLAGS`. In each clone
  family the lowest-inode member is charged in full and the others only their private bytes,
  and only when flags and private size are known. Every view shows **logical size** and
  **estimated on-disk usage**.
- **Protection (`DeletionGuard`).** It is case-insensitive, refuses `..`, and checks the same
  canonical path it then deletes. System locations, volume roots, folders containing a volume,
  the home folder and SIP-flagged items can't be deleted. Right before deleting, the whole
  subtree is pre-scanned, and the delete runs fd-relative with a `(dev, inode)` check. launchd
  jobs, `/Applications/*.app` and `/private/var/folders` need an extra confirmation.
- **Background deletion** with a progress sheet (phase, counts, current path, Cancel).
  Deletion is all-or-nothing per item: folders that are read-only, locked (uchg/schg) or
  append-only, and sticky-bit conflicts, are found *before* anything is removed. Paths on the
  startup disk are shown as `/Users/…`, not `/System/Volumes/Data/Users/…`; that's display
  only, and the real path is still used internally.
- **Quick Look.** Select a file in the list, or click it in the sunburst, then press **Space**
  or ⌘Y to open `QLPreviewPanel`.
- The scan stays on one filesystem by default. It compares device ids and checks the
  mount-point flag. Symlinks are never followed.
- Folders that can't be read are marked and the scan keeps going.
- Sunburst view:
  - Rings by depth, with angle proportional to actual on-disk size, or to logical size via
    View › Size Rings by Logical Size
  - The center label and tooltips show both measures
  - Small slices merged into one grey "N smaller items" slice
  - Highlight and tooltip on hover
  - Click a folder to drill in; click the center to go up
  - Short zoom/fade transitions
  - Right-click to add an item to the deletion list
- Side list of the current folder's children with **Logical** and **On Disk** columns and a
  percentage. Double-click a folder to drill in.
- Deletion list with a total size:
  - **Move to Trash…** uses `FileManager.trashItem` and is the default.
  - **Delete Permanently…** uses recursive `unlink`/`rmdir`, never follows symlinks and never
    crosses devices.
  - Both ask for confirmation first, and the tree's sizes update after deletion.
- Menus: Scan ⌘O, Rescan ⌘R, Stop ⌘., Go to Enclosing Folder ⌘↑, Reveal in Finder, Quick Look
  ⌘Y, Size Rings by Logical Size, Refresh Volumes, deletion list actions, Open Full Disk Access
  Settings.
- `DiskRings --cli <path>` prints a text report with **LOGICAL** and **ACTUAL** columns plus
  hard-link and clone statistics. It works on macOS and Linux and uses the same engine.

## Architecture

```
Package.swift
├─ Sources/DiskScanCore        (library, portable; Foundation only)
│   ├─ FileNode.swift                 tree node: name, kind, dev, inode, links, logical/allocated
│   │                                 size, children, weak parent, flags; aggregate(), removeFromTree()
│   ├─ DirectoryEnumerator.swift      protocol DirectoryEnumerator + DirectoryEntry (syscall seam)
│   ├─ BulkAttributeParser.swift      portable parser for getattrlistbulk records (unit-tested)
│   ├─ BulkAttributeEnumerator.swift  #if canImport(Darwin): open(O_NOFOLLOW) + getattrlistbulk loop
│   ├─ PosixDirectoryEnumerator.swift opendir/readdir + lstat fallback (Linux & macOS)
│   ├─ InMemoryDirectoryEnumerator.swift  fake filesystem for tests/previews
│   ├─ HardLinkRegistry.swift         thread-safe (dev, inode) first-sighting set + CloneRegistry
│   │                                 (dev, clone id) for APFS clone dedup
│   ├─ DeletionGuard.swift            protection rules (pure, injectable) + VolumeScanTarget
│   ├─ ScanEngine.swift               N worker threads + shared LIFO work list (NSCondition),
│   │                                 progress callback (throttled), cancellation, async wrapper
│   ├─ Deletion.swift                 ItemDeleting (TrashDeleter, PosixRecursiveDeleter),
│   │                                 PrivilegedDeleting protocol + UnimplementedPrivilegedDeleter,
│   │                                 DeletionList (staging list, @MainActor)
│   └─ SizeFormatter.swift            deterministic base-1000 size text
├─ Sources/SunburstGeometry    (library, pure Swift, no UI imports)
│   └─ SunburstLayout.swift           SunburstNode protocol, ring/angle layout, small-slice
│                                     merging, point→segment hit-testing (binary search per ring),
│                                     outline polygons, label anchors, colour palette
├─ Sources/DiskRingsApp        (executable)
│   ├─ main.swift                     AppKit bootstrap on macOS; CLI-only stub elsewhere
│   ├─ AppDelegate.swift              app delegate + programmatic main menu (no nibs)
│   ├─ MainWindowController.swift     window, volume sidebar, picker, progress, tables,
│   │                                 protection greying, deletion flow, Quick Look controller
│   ├─ SunburstView.swift             NSView + CAShapeLayer/CATextLayer rendering, tracking, clicks
│   ├─ FileNode+Sunburst.swift        bridges FileNode → SunburstNode
│   └─ CLIReport.swift                text report (portable)
├─ Tests/DiskScanCoreTests       engine, hard links, mounts, symlinks, cancellation,
│                                async API, deletion list, real-FS scan + delete, parser
├─ Tests/SunburstGeometryTests   angles, nesting, depth limit, "other" merging, hit-testing
├─ SelfTest/main.swift           XCTest-free self-test (17 checks) for `./build.sh test`
├─ Resources/Info.plist          bundle metadata for the .app wrapper
├─ build.sh                      SwiftPM-free single-module build (Command Line Tools only)
└─ scripts/                      make-app-bundle.sh (SwiftPM-based), linux-verify.sh
```

### Scan engine

1. `ScanEngine.scanBlocking(path:)` reads the root with `lstat` and creates the root
   `FileNode`. It then starts `maxConcurrency` worker threads, 2–8 by default depending on
   the CPU count. The workers use plain threads so blocking syscalls stay off the Swift
   cooperative thread pool.
2. Each worker repeatedly does the following:
   1. Take a directory job from a shared LIFO stack.
   2. Call `enumerator.entries(inDirectoryAt:)`.
   3. Build child nodes.
   4. Attach them to the directory with `setChildren`.
   5. Push sub-directories as new jobs.

   Children are always attached before any sub-job is published, so no worker ever sees a
   half-built directory. A directory's `children` array is written only by the worker that
   enumerated it.
3. Hard links: for a regular file with `linkCount > 1`, `HardLinkRegistry` records
   `(dev, inode)`. The first sighting keeps the bytes. Later ones get `isHardLinkDuplicate`
   and add 0 to their parents. With parallel traversal, *which* path counts first depends on
   scheduling, but the total is always correct.
4. Filesystem boundary: a directory is not entered (it gets `isOtherFilesystem`) if its device
   differs from the root's or `getattrlistbulk` reports `DIR_MNTSTATUS_MNTPOINT`. To change
   this, set `ScanOptions(crossFilesystems: true)`.
5. The scan ends when the stack is empty and no job is still running. `aggregate()` then makes
   one iterative post-order pass that adds up logical size, allocated size and item count, and
   sorts children by size. It is safe for very deep trees.
6. Progress: counters update under the work-list lock. The callback runs at most every
   `progressInterval` seconds and once more when the scan finishes.
7. Cancellation: `ScanCancellation` is checked whenever a worker takes the next job, and idle
   workers wake every 50 ms. `async scan(path:)` connects Swift `Task` cancellation to this
   flag and throws `ScanError.cancelled`.

Darwin enumerator: `open(path, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`, then a
`getattrlistbulk` loop into a reused 128 KiB buffer. It requests:

- `ATTR_CMN_RETURNED_ATTRS | NAME | ERROR | DEVID | OBJTYPE | FILEID`
- `ATTR_DIR_MOUNTSTATUS`
- `ATTR_FILE_LINKCOUNT | TOTALSIZE | ALLOCSIZE`

Records are decoded by `BulkAttributeParser`, which reads each field only if its bit is set in
the record's returned-attributes set and uses unaligned loads.

### Sunburst

`SunburstLayout(root:config:)` does a breadth-first pass over the focused node:

- Each child gets `parentSpan × childSize / parentSize` radians, clockwise from 12 o'clock, so
  a parent whose children don't add up to its size leaves a visible gap.
- Slices narrower than `minSliceAngle` are combined into one `.other(count:size:)` segment per
  parent.
- Ring `d` covers radii `[center + (d−1)·w, center + d·w)`.

`hitTest(Point2D)` works like this:

1. Use the radius to pick the center disc or a ring.
2. Convert the point to a layout angle with `atan2(x, y)`.
3. Binary-search the ring's segments, which are sorted by start angle.

`outline(of:)` returns polygon points that the view turns into `CGPath`s for `CAShapeLayer`s. As
a result, `SunburstView` has no trigonometry of its own. Everything is covered by Linux tests.

### APFS clone accounting (estimates)

Each `FileNode` keeps three sizes:

- `logicalSize`: the file length.
- `allocatedSize`: raw allocated blocks.
- `actualSize`: an **estimate** of on-disk usage after dedup. The UI labels it "On Disk
  (est.)" or "≈ … (estimate)", and the CLI column is `ACTUAL~`.

How `actualSize` is worked out for regular files:

1. An extra hard link of an already-seen `(dev, inode)` contributes **0** and is never
   considered a clone, so nothing is subtracted twice.
2. Files with a clone id are collected during the scan. Nothing is decided while worker threads
   run. Afterwards, each `(dev, clone id)` family is resolved **deterministically**: the member
   with the **lowest inode, then the lowest path** is the primary and is charged its full
   allocated size. Each other member is charged `min(allocated, PRIVATESIZE)`, but **only if**
   its `EXT_FLAGS` are known and contain `EF_MAY_SHARE_BLOCKS`/`EF_SHARES_ALL_BLOCKS` **and**
   its `PRIVATESIZE` is known.
3. Anything else (no clone attributes, unknown flags, unknown private size, flags saying "not
   shared") is charged its full allocated size. This is conservative: it never under-counts.

`dev_t` is converted the same way everywhere (`DeviceID.key`). A 32-bit signed `dev_t` is
reinterpreted as `UInt32(bitPattern:)`, not sign-extended, so `getattrlistbulk` and `lstat`
produce identical keys.

Why it's still an estimate:

- APFS has no per-file "unique bytes" number for whole families. Blocks shared only among
  non-primary members, and blocks held by snapshots, aren't seen.
- **A clone that was modified may get a new clone id.** It then forms its own family and is
  counted in full even though most of its blocks are still shared, so it's **over-counted**.
- Deleting one clone frees only about its private bytes. Deleting the primary frees almost
  nothing while other members remain. The confirmation dialog says this.

Fallback: if the volume doesn't return the extended attributes, or the kernel rejects
`FSOPT_ATTR_CMN_EXTENDED` with `EINVAL` (the scan then retries without them), all files are
charged their allocated size, as in round 2.

### Deletion protection (`DeletionGuard`)

**One canonical path for both the decision and the delete.**

- Any path with a `..` component is **refused** (`unsafePath`). The kernel resolves `a/lnk/..`
  relative to the symlink's target, so collapsing it as text could check one path and delete
  another.
- Otherwise `.` and `//` are dropped. The parent directory is resolved with `realpath`. The last
  component is resolved to its on-disk spelling (Darwin `F_GETPATH`, else `realpath`) unless it
  is a symlink; a symlink itself is what gets deleted, never its target.
- `Verdict.canonicalPath` is exactly the path that `DeletionList.deleteAll` hands to the deleter.
- For rule matching only, `/etc`, `/var` and `/tmp` map to `/private/...` and
  `/System/Volumes/Data/<x>` maps to `/<x>`.
- **All comparisons are case-insensitive** (APFS default; also applied to case-sensitive volumes
  to be safe). So `/USR`, `/system`, `/users/tester` and `/System/Volumes/data` are all caught.

**Blocked (hard refusal):**

| Rule | Paths |
|---|---|
| Filesystem root, volume roots | `/`, any mount point (macOS: `mountedVolumeURLs`; Linux: `/proc/self/mounts`), `/System/Volumes/Data` |
| **Contains a volume** | any folder that has a mount point somewhere below it |
| Home | the home folder itself and any ancestor of it (contents are fine) |
| Protected prefixes (path and everything below) | `/System`, `/usr` (**except `/usr/local` and below**), `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`, `/private/etc`. Additions: `/private/var/vm`, `/private/var/root`, `/dev`, `/Library/Developer/CommandLineTools` |
| Ancestors of protected prefixes | e.g. `/private`, `/Library`, `/System/Volumes` |
| Essential folders (the folder only) | `/Applications`, `/Library`, `/Users`, `/Volumes`, `/private`, `/private/var`, `/private/tmp`, `/opt`, `/cores` |
| SIP / immutable item | `lstat` `st_flags` has `SF_RESTRICTED` or `SF_NOUNLINK` |
| **Subtree pre-scan** (right before deleting) | the item is refused **as a whole** if anything below it is a directory on another device (mount), carries `SF_RESTRICTED`/`SF_NOUNLINK`, or can't be read or stat'ed. The walk uses `lstat` only, never follows symlinks, and stops at 2 million entries (over the limit counts as "not verifiable") |

**P2-4 decision: allowed, but only after an extra, explicit confirmation.** A second alert lists
each item with its warning. The default button is "Skip These Items"; "Include Them" is a
separate choice.

| Caution | Paths | Warning shown |
|---|---|---|
| launchd jobs | at or below `/Library/LaunchDaemons`, `/Library/LaunchAgents` | removing them can break or disable VPNs, drivers, updaters and security tools; takes effect at next login/boot |
| App bundles | `/Applications/<X>.app` and anything inside it | deleting an app leaves its helpers and data behind; some apps need a vendor uninstaller |
| System temp/caches | at or below `/private/var/folders` (`/var/folders`) | running apps may crash or lose state; macOS recreates what it needs after a restart |

Why caution instead of blocking: none of these is protected by SIP, and removing a stale launch
daemon or an unwanted app is a normal cleanup task. QA's policy test
`testPolicy_systemLaunchDaemonsAreDeletable` also expects `check()` to allow
`/Library/LaunchDaemons` and `/private/var/folders`. Per-user folders such as
`~/Library/LaunchAgents` are not flagged.

**Executing a delete (all-or-nothing, in the background, cancellable):**

1. The user confirms. For Delete Permanently, **Cancel is the first, default button (Return)**,
   and Delete is a non-default button with `hasDestructiveAction`. Caution items then get the
   extra confirmation.
2. A progress sheet appears. It shows the phase (checking / deleting item *n* of *m*), the
   number done, the current path (display form), a progress bar and **Cancel** (Esc).
   `DeletionList.deleteAll` does the checking and deleting **off the main actor**. Progress
   comes back through a `@Sendable` callback, and tree/list updates happen on the main actor.
3. For each top-level item:
   1. **Guard evaluation plus an all-or-nothing pre-pass** (`DeletabilityChecker`). The item's
      parent, and for a permanent delete **every** non-empty folder inside it, must be writable
      and searchable for the effective user (`faccessat(W_OK|X_OK, AT_EACCESS)`) and readable.
      In sticky folders, entries must belong to you (or to the folder's owner, or you are root).
      No entry or folder may carry `UF_IMMUTABLE` (uchg), `UF_APPEND`, `SF_IMMUTABLE` (schg),
      `SF_APPEND`, `SF_RESTRICTED` or `SF_NOUNLINK`. No folder may be on another device. Any
      failure refuses the **whole item**, untouched, with the path and reason, e.g. "Refused:
      can't be deleted completely — folder is read-only for you (…/sub)". For Move to Trash
      (a single rename) only the top level is checked.
   2. The `(dev, inode)` captured during the check must still match. Move to Trash re-checks it
      right before `trashItem`. Delete Permanently runs the same pre-pass again itself, then
      deletes fd-relative (`openat` with `O_NOFOLLOW|O_DIRECTORY`, `fstatat`/`unlinkat`).
4. **Cancel** takes effect during an item's pre-scan (checked every 512 entries) or between
   top-level items, **never in the middle of removing an item**. When the run ends, a summary
   lists **Deleted**, **Not deleted** (with reasons), **Partially deleted** (if any) and **Not
   attempted (cancelled, untouched)**. Items that weren't deleted stay on the deletion list.
   Closing the window cancels the same way.

**What is still not atomic, and how it's reported.** The pre-pass and the delete are separate
steps, so a few things can still interrupt a delete once removal has started:

- another process changing the tree in between (e.g. adding a locked file or chmod-ing a folder);
- I/O errors;
- a full or ejected disk;
- ACL rules that are added after the pre-pass.

In that case the deleter stops at the first error and reports
`partiallyDeleted(path, removedEntries, cause)`. The UI shows these items under "Partially
deleted — rescan these folders", and their nodes stay in the tree until the next rescan.

**ACLs and privacy protection (round 5).** The pre-pass reads each item's extended ACL with
`acl_get_link_np` (Darwin; symlinks are not followed). It refuses the whole item when the entry
has an `ACL_EXTENDED_DENY` with `ACL_DELETE`, or any folder whose entries would be removed (the
item's parent included) has a deny with `ACL_DELETE_CHILD`. Any qualifier counts; group
membership isn't resolved, which errs on the side of refusing. `EPERM` from `lstat`/`opendir`
(macOS privacy protection without Full Disk Access) is classified as "can't be deleted" with
the hint "grant DiskRings Full Disk Access in System Settings > Privacy & Security > Full Disk
Access". A deleter `EPERM` error carries the same hint. Folder-level checks (flags,
delete_child ACL, write+search access) are computed once per folder. When `readdir` returns
NULL, `errno` (cleared before every call) separates end-of-folder from a read error. A read
error refuses the delete and makes the scan mark the folder unreadable. The ACL check, flags,
access test and directory listing are all injectable, so the rules are unit-tested on Linux.

**Progress, cancellation, threading (round 5).**

- Every progress event carries a monotonic `sequence` from `ProgressStamper`, delivered in call
  order. The app passes the background callback into a single `AsyncStream`. One main-actor
  consumer applies events in order, and `ProgressSequencer` drops anything stale.
- Phases are *checking* (guard pre-scan), *verifying* (the deleter's own all-or-nothing re-check,
  with entry counts) and *deleting*. The re-check is cancellable too.
- Each item runs in `Task.detached`, which never inherits the main actor in any Swift version or
  language mode, and an `assert(!Thread.isMainThread)` guards it. `@concurrent` isn't used: it
  needs the Swift 6.2 compiler, and the Mac toolchain in use is 6.1.2. A plain `nonisolated async` function would
  start inheriting the caller's actor under Swift 6.2's NonisolatedNonsendingByDefault.

**Quit and command gating (round 5).** `AppActivity` (core, unit-tested) holds the scanning and
deleting state.

- While a delete runs, the menus (`NSMenuItemValidation`), the buttons and the volume list block
  scan, rescan, open, deletion-list edits and a second delete. Every scan request goes through
  one choke point.
- Cmd-Q returns `.terminateLater`. The sheet shows "Quitting…" and the run is cancelled; it
  stops after the current top-level item, never mid-item. Then
  `NSApp.reply(toApplicationShouldTerminate: true)` is called.

Renaming into a same-volume staging folder first wasn't adopted. It would only make the
*rename* atomic, not the recursive removal, and it adds a hidden folder that needs its own
recovery handling. The pre-pass already catches every condition the reviewers reproduced.

In the UI, protected items show 🔒, greyed text and the reason. Caution items show "⚠︎ Needs
extra confirmation". The confirmation dialog stays, and Move to Trash remains the default.

### Deletion and privileges

`DeletionList` holds the staged nodes. Adding a folder replaces any of its descendants that are
already on the list, and adding a descendant of a listed folder is ignored. A scan root can't be
added. `deleteAll(using:privileged:)` runs the chosen `ItemDeleting` on each item:

- On success, `FileNode.removeFromTree()` detaches the node and subtracts its size from every
  ancestor, and the item leaves the list.
- On failure, the item stays on the list and the error is reported.
- On `EACCES`/`EPERM`, it would hand off to a `PrivilegedDeleting` implementation. The only
  one in this repo is `UnimplementedPrivilegedDeleter`, which reports itself unavailable and
  throws. **No privileged helper, SMJobBless, SMAppService or XPC code is included.**

## Package a DMG (macOS)

End-user installers are `.dmg` files. **The binary DMG is only produced on macOS**
(`hdiutil` / `codesign`). On Linux you can still validate scripts and docs:

```bash
./scripts/package_dmg.sh --dry-run --adhoc --universal
# or:
./build.sh dmg --dry-run --adhoc --arm64
```

On a Mac (example — ad-hoc, Apple Silicon only):

```bash
./scripts/package_dmg.sh --adhoc --arm64
# → dist/DiskRings-0.1.0-adhoc-arm64.dmg + dist/SHA256SUMS
```

Universal ad-hoc:

```bash
./scripts/package_dmg.sh --adhoc --universal
# → dist/DiskRings-0.1.0-adhoc.dmg
```

Notarized (Developer ID — **you** must set credentials; the script never opens Keychain/Apple ID):

```bash
export IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='NotaryProfile'   # or NOTARY_APPLE_ID/PASSWORD/TEAM_ID, or API key trio
./scripts/package_dmg.sh --notarize --universal
# → dist/DiskRings-0.1.0.dmg
```

If `IDENTITY` / notary env is missing, `--notarize` fails with a clear fallback to `--adhoc`.
Never treat an ad-hoc build as notarized (filenames include `-adhoc` on purpose).

Layout: volume `DiskRings`, App left + Applications alias right, soft-teal background,
ad-hoc builds also ship `安装说明.txt` (from `docs/install-adhoc.zh.txt`).
QA checklist: `docs/dmg-mac-verify.md`.

| Command | Writes | sudo | Notes |
|---|---|---|---|
| `./scripts/package_dmg.sh --dry-run …` | nothing meaningful | no | Linux OK |
| `./scripts/package_dmg.sh --adhoc …` | `./build`, `./dist` | no | macOS only for real DMG |
| `./build.sh dmg …` | same (forwards) | no | same |

---

## Build with Command Line Tools only (no Xcode) — recommended

`build.sh` doesn't use SwiftPM. It runs `xcrun --sdk macosx swiftc` directly and compiles
**all** sources (DiskScanCore + SunburstGeometry + DiskRingsApp) into **one** module and one
executable, so it works on a Mac that has only the Command Line Tools installed.

### Before you run anything: command safety reference

No assistant runs commands on your Mac. Read the row, then run the command yourself. Start with
the read-only ones.

**`build.sh` guarantees:** it never calls `sudo`, and it writes, deletes or overwrites only
inside `./build`. That covers the binaries, the `.app`, `ModuleCache` and `last-compile.log`.
`doctor` writes nothing at all. One exception: the self-test that `./build.sh test` runs creates a `diskrings-selftest-<UUID>` folder under `$TMPDIR` and deletes it again. The system-level fixes below are only *printed* as hints and
never executed. (`xcrun`/`swiftc` may refresh their own per-user caches under
`$TMPDIR`/`~/Library/Caches`, as any compile does.)

| Command | What it does | Reads / writes / deletes | sudo | Risk | Undo / recover |
|---|---|---|---|---|---|
| `xcode-select -p`, `xcrun swiftc --version`, `xcrun --show-sdk-path`, `ls /Library/Developer/CommandLineTools/SDKs` | **Read-only** diagnostics | reads only | no | none | – |
| `./build.sh doctor` | Prints toolchain/SDK info, mismatch and SwiftBridging checks | **reads only** (SDK, CLT include dirs) | no | none | – |
| `grep -n SwiftBridging <path printed by build.sh>` | **Read-only** look at the conflicting module maps | reads only | no | none | – |
| `./build.sh`, `./build.sh app`, `./build.sh test` | Compiles; `app` also bundles and ad-hoc signs; `test` runs the self-test | writes `./build/` only; the self-test makes and deletes its own temp folder under `$TMPDIR` | no | none outside `./build` | `./build.sh clean` |
| `./build.sh clean` | Deletes the build output | deletes **only `./build`** | no | rebuild needed | `./build.sh` |
| `build/DiskRings --cli <dir>` | Read-only scan report | reads `<dir>` | no | none (it never deletes) | – |
| `open build/DiskRings.app` | Launches the GUI. Deleting files happens only after you confirm a dialog, and goes to the Trash by default | reads what you scan | no | items you choose to delete | restore from Trash (not after "Delete Permanently") |
| `xcode-select --install` | Opens Apple's CLT installer (GUI, download) | writes `/Library/Developer/CommandLineTools` | no (asks for your password in the GUI) | download time | remove that folder |
| `SDKROOT=<sdk path> ./build.sh` | Uses a specific SDK for this one run | reads the SDK, writes `./build` | no | none | leave out `SDKROOT` next time |
| ⚠️ `sudo cp <modulemap> <modulemap>.bak` | Backs up the system module map | writes `<modulemap>.bak` next to it | **yes** | low | `sudo rm <modulemap>.bak` |
| ⚠️ `sudo nano <modulemap>` (SwiftBridging fix) | **Modifies a system file** | edits `…/usr/include/swift/module.modulemap` | **yes** | a bad edit breaks every CLT C/Swift build | `sudo cp <modulemap>.bak <modulemap>` |
| ⚠️ CLT reinstall (manual, see [Reinstalling the CLT](#reinstalling-the-command-line-tools-last-resort)): Finder › move `/Library/Developer/CommandLineTools` to the Trash, then `xcode-select --install` | **Destructive-ish** last resort | moves `/Library/Developer/CommandLineTools` to the Trash; the installer recreates it | admin password (Finder prompt) | no compiler until the multi-GB download finishes; manual edits there are lost | Finder › Trash › Put Back, as long as the Trash hasn't been emptied |
| ⚠️ `sudo xcode-select -s /Library/Developer/CommandLineTools` | Changes the system-wide active developer dir | writes the global xcode-select setting | **yes** | other tools (e.g. Xcode builds) switch toolchains | `sudo xcode-select -s <old path from xcode-select -p>`, or `sudo xcode-select -r` |
| `xattr -dr com.apple.quarantine DiskRings.app` | Removes Gatekeeper's quarantine flag | changes **that .app bundle only** | no | you vouch for that bundle | re-copy/rebuild the bundle (or right-click › Open instead) |
| System Settings › Privacy & Security › Full Disk Access | Lets the app read protected folders | system privacy database (via the GUI) | no (password prompt) | the app can read all user data | remove it from the list |
| `cp -c big.file clone.file` (clone test) | Makes an APFS clone (instant, shares blocks) | writes `clone.file` | no | none (uses almost no space) | `rm clone.file` |

**Prerequisites:** macOS 12 or later, and the Command Line Tools:

```bash
xcode-select --install          # once; provides xcrun, swiftc, the macOS SDK, codesign, lipo
```

**Commands** (run them in the folder that contains `build.sh`):

```bash
./build.sh                      # release build → build/DiskRings (host arch: arm64 or x86_64)
./build.sh app                  # same, plus build/DiskRings.app (Info.plist + ad-hoc codesign)
./build.sh test                 # builds and runs build/DiskRingsSelfTest (no XCTest needed)
./build.sh doctor               # only prints toolchain/SDK info and runs the sanity checks
./build.sh clean                # deletes ./build only
./build.sh dmg --adhoc --arm64  # → dist/DiskRings-*-adhoc-arm64.dmg (macOS)
ARCH=universal ./build.sh app   # arm64 + x86_64, merged with lipo
ARCH=x86_64 ./build.sh          # pick an architecture explicitly
DEBUG=1 ./build.sh              # -Onone -g instead of -O -whole-module-optimization
```

On Apple Silicon, the compile step is exactly:

```bash
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos12.0 -module-name DiskRings -D SINGLE_MODULE -swift-version 5 \
  -O -whole-module-optimization -module-cache-path build/ModuleCache \
  -framework AppKit -framework QuartzCore -framework Quartz \
  Sources/DiskScanCore/*.swift Sources/SunburstGeometry/*.swift Sources/DiskRingsApp/*.swift \
  -o build/DiskRings
```

The script prints the full command before running it. If `xcrun` or the macOS SDK is
missing, it stops with a message that suggests `xcode-select --install`.

**Running:**

```bash
open build/DiskRings.app        # the GUI app (needs `./build.sh app`)
build/DiskRings                 # GUI without a bundle: works, but the Dock/menu name is generic
build/DiskRings --cli ~/Downloads   # text report only, no window
```

**How the single-module build works.** The SwiftPM build keeps three separate modules, so the
app sources normally say `import DiskScanCore` / `import SunburstGeometry`. Those imports are
wrapped in `#if !SINGLE_MODULE`, and `build.sh` passes `-D SINGLE_MODULE`. The only entry point
is `Sources/DiskRingsApp/main.swift`. No other file has top-level code, there is no `@main`,
and type names are unique across the three targets.

**Gatekeeper and signing.** `./build.sh app` signs the bundle ad hoc (`codesign --force --sign -`).
That is enough to run software you built yourself, including on Apple Silicon. Locally built
files aren't quarantined, so Gatekeeper won't block them. If you copy the `.app` to another Mac
through a browser or AirDrop, it will be quarantined. In that case, right-click › Open, or run
`xattr -dr com.apple.quarantine DiskRings.app`. That needs no sudo, affects only that bundle,
and is undone by re-copying it. To distribute it properly you would need a
Developer ID signature and notarization, which aren't part of this project.

**Full Disk Access and rebuilds.** The ad-hoc signature changes every time you rebuild, so macOS
may stop applying an earlier Full Disk Access grant to the new build. If that happens, remove
DiskRings from the list and add `build/DiskRings.app` again. When you launch the bare
`build/DiskRings` binary from Terminal, macOS uses **Terminal's** Full Disk Access instead.

### Known issue: compiler / SDK version mismatch

**Symptom:** the compile fails early with a message like `failed to build module 'Swift'; this SDK
is not supported by the compiler (the SDK is built with 'swiftlang-6.1.0.110.5', while this
compiler is 'swiftlang-6.1.0.110.21')`, or with errors about modules compiled by a different
Swift.

**Diagnosis:** `./build.sh doctor` (and every build) prints `swiftc --version`, the SDK version and
path, and the `swiftlang-…` build recorded in the SDK's
`usr/lib/swift/Swift.swiftmodule/*.swiftinterface` header (`// swift-compiler-version:`). It
warns when the two differ, and says so explicitly when the compiler is older.

**Fix, least invasive first:**

1. Read-only: `xcrun swiftc --version`, `ls /Library/Developer/CommandLineTools/SDKs`.
2. No sudo, nothing written outside `./build`: if a matching SDK exists, run
   `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX<ver>.sdk ./build.sh`. To undo, just
   leave out `SDKROOT` next time.
3. ⚠️ Last resort: reinstall the CLT. Follow [Reinstalling the CLT](#reinstalling-the-command-line-tools-last-resort).

`build.sh` honours `SDKROOT`, `DEVELOPER_DIR` and `TOOLCHAINS` and never overwrites them.

### Known issue: "redefinition of module 'SwiftBridging'"

**Symptom:** clang aborts with `error: redefinition of module 'SwiftBridging'`. Some CLT installs
ship both `…/usr/include/swift/module.modulemap` and `…/usr/include/swift/bridging.modulemap`,
and both define `module SwiftBridging`.

**Diagnosis:** before compiling, `build.sh` looks in `$SDK/usr/include{,/swift}`,
`$(xcode-select -p)/usr/include/swift` (or `$DEVELOPER_DIR/...`), the Xcode default toolchain and
the directory next to `swiftc`. If two or more module maps define `module SwiftBridging`, it
prints their exact paths. If a compile still fails with that error, it prints the same hint.

**Fix (manual; build.sh never edits system files):**

```bash
F=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap   # use the path build.sh printed
grep -n SwiftBridging "$F"        # 0. read-only check, no sudo
sudo cp "$F" "$F.bak"             # 1. ⚠️ sudo: backup, writes $F.bak only
sudo nano "$F"                    # 2. ⚠️ sudo, MODIFIES a system file: delete only the
                                  #    `module SwiftBridging { ... }` block; leave bridging.modulemap alone
./build.sh                        # 3. no sudo, writes ./build only
```

- **Risk:** a bad edit breaks C/Swift interop for every CLT build on this Mac.
- **Undo:** `sudo cp "$F.bak" "$F"`. Reinstalling the CLT (destructive, see above) also restores
  the original file.

### Reinstalling the Command Line Tools (last resort)

Neither this README nor `build.sh` gives a copy-paste removal command, on purpose. Do each step
by hand:

1. **Read-only check:** `xcode-select -p`. It should print `/Library/Developer/CommandLineTools`.
   If it prints an `Xcode.app` path, stop; that's a different toolchain.
2. **Remove recoverably:** in Finder, choose Go › Go to Folder…, enter `/Library/Developer`, and
   drag `CommandLineTools` to the Trash. Finder asks for your admin password. **Don't empty the
   Trash yet.**
3. **Reinstall:** `xcode-select --install`. It needs no sudo, opens Apple's installer and
   downloads several GB.
4. **Check:** `./build.sh doctor` (read-only). Empty the Trash only after it looks good.

| | |
|---|---|
| Paths | moves `/Library/Developer/CommandLineTools` to the Trash; the installer recreates it. Nothing else is touched |
| sudo | admin password in Finder (step 2) and in the installer |
| Risk | no compiler until step 3 completes; any manual edits in that folder (e.g. the SwiftBridging fix) are lost |
| Undo | before emptying the Trash: remove any half-installed new folder the same way, then Finder › Trash › `CommandLineTools` › **Put Back** |

### Known issue: SwiftPM with Command Line Tools only

On some CLT-only Macs, `swift build` fails before compiling any code. The error says the
package manifest fails to link, with undefined symbols such as
`PackageDescription.Package.__allocating_init`. This happens when the CLT's SwiftPM, its
`PackageDescription` library and the SDK don't match. Typical causes are a partly updated CLT, a
`DEVELOPER_DIR` / `xcode-select -p` pointing at a different toolchain, or a second `swift`
earlier on `PATH`. Some things that may help:

- Check first (read-only): `xcode-select -p`, `which -a swift`.
- ⚠️ Point at the CLT system-wide: `sudo xcode-select -s /Library/Developer/CommandLineTools`.
  This needs sudo and changes the global setting. Undo with `sudo xcode-select -s <previous -p
  output>` or `sudo xcode-select -r`.
- ⚠️ Reinstall the CLT: see [Reinstalling the CLT](#reinstalling-the-command-line-tools-last-resort).
- Install full Xcode.

`build.sh` doesn't depend on any of this.

## Build with SwiftPM / Xcode (secondary)

For Macs with full Xcode 15+ (or a working Swift 5.9+ SwiftPM). `Package.swift` is the same as
before.

```bash
swift build                          # debug build of all three modules
swift run DiskRings                  # launches the AppKit app (unbundled executable)
swift run DiskRings --cli ~/Downloads   # text report, no UI
swift test                           # full XCTest suite (29 tests)
scripts/make-app-bundle.sh           # release build via SwiftPM → dist/DiskRings.app (ad-hoc signed)
scripts/make-app-bundle.sh --universal
```

**Xcode:** open `Package.swift` with `open Package.swift` or `xed .`. Choose the `DiskRings`
scheme and *My Mac*, then Run (⌘R). Run tests with ⌘U. No `.xcodeproj` is checked in; Xcode
generates one from the package.

### Permissions (Full Disk Access)

The app is not sandboxed and doesn't need any entitlements to scan folders you can read.
macOS privacy protection (TCC) still hides some places: Mail, Messages, Safari data, other apps'
containers, Time Machine and parts of `~/Library`. Folders it can't read are marked
*unreadable* and drawn in grey, and the count appears as a capacity-bar notice and in the 「重新扫描」 tooltip. To include them:

1. Open **DiskRings › Open Full Disk Access Settings…** (System Settings › Privacy &
   Security › Full Disk Access).
2. Add `build/DiskRings.app` (or `dist/DiskRings.app` from the SwiftPM script). If you launch the unbundled binary instead, add the app you launch it
   from, such as Terminal or Xcode.
3. Restart DiskRings and scan again.

Files owned by other users or by root may still fail to delete. That would need the
unimplemented privileged helper.

Scanning `/` stays on the read-only System volume because the boundary check compares
devices. To analyze user data, scan `/System/Volumes/Data` or your home folder.

## Verification (what was actually built and tested)

Environment: Debian 13 (trixie) x86_64 box, Swift 6.0.3 Linux toolchain from swift.org
(`swift-6.0.3-RELEASE-debian12`). The package uses `swift-tools-version:5.9`, so it compiles in
Swift 5 language mode.

| Step | Result |
|---|---|
| **Real Mac:** `./build.sh test` / `./build.sh app`, before this round's features | ✅ 12/12 / one error (`shouldEdit` delegate name), now fixed. A broken CLT (duplicate SwiftBridging, compiler/SDK mismatch) needed manual fixes, and `build.sh` now detects both |
| `swift build` (Linux) | ✅ 0 warnings |
| `swift build -Xswiftc -strict-concurrency=complete` | ✅ 0 warnings / 0 errors |
| Swift 6 language mode, portable code: `swiftc -swift-version 6 -typecheck` of DiskScanCore + SunburstGeometry + the CLI parts of DiskRingsApp, and of the self-test | ✅ 0 errors / 0 warnings. (`swift build --build-tests -Xswiftc -swift-version -Xswiftc 6` fails only in the XCTest discovery file SwiftPM generates on Linux, "implicit capture of 'self' requires … Sendable", which is outside our sources.) Swift 5 stays the default |
| `swift test`: **157** XCTests (1 opt-in skipped) in 32 suites: ScanEngine 10, TreeAndDeletion 6, BulkAttributeParser 4, CloneAccounting 8, DeletionGuard 10, R3Fix 9, AllOrNothing 5, DeletionCancellation 4, DisplayPath 1, AppActivity 1, ACLAndTCC 6, ProgressOrdering 3, OffMain 1, QuitDuringDelete 3, SunburstLayout 10, ThemeTokens 4, Localization 7, LocalizationLayoutBudget 2, AppearancePreference 2, plus QA's R3ReviewGuard 7, R3ReviewClone 3, R4Guard 4, R4DeletionList 1, R4PosixDeleter 3, R4CloneDeterminism 1, R5AllOrNothing 7, R5Outcome 3 | ✅ **156 pass + 1 opt-in skip** (0 skipped, non-root) |
| `swift test --sanitize=thread` | ✅ 157 (1 skipped), no ThreadSanitizer reports |
| `SWIFTC=… ./build.sh` (single module, all 38 sources; AppKit files drop out through `#if canImport(AppKit)`) | ✅ 0 warnings. `build/DiskRings --cli /usr` shows LOGICAL/ACTUAL~ columns: 4.4 GB logical / ≈4.6 GB actual (estimate), 11.5k dirs, 74.6k files |
| `SWIFTC=… ./build.sh test` (XCTest-free self-test) | ✅ **24/24** checks pass, 0 warnings |
| `swiftc -parse -D SINGLE_MODULE` (Swift 5 and 6 modes) of all 38 sources with the macOS branches (`canImport(AppKit/Darwin)`, `os(macOS)`) forced on | ✅ syntax only |
| `build.sh` macOS path with fake `uname`/`xcrun`/`xcode-select`/`codesign` | ✅ mismatch warning (differs / OLDER), duplicate SwiftBridging paths found, failure hint on "redefinition of module 'SwiftBridging'", `SDKROOT`/`DEVELOPER_DIR`/`TOOLCHAINS` passed through untouched, `-framework Quartz` linked, universal + lipo, `.app` + codesign |
| `bash -n build.sh`, `shellcheck build.sh scripts/*.sh` | ✅ clean |
| AppKit, QuickLook (`QLPreviewPanel`) and volume-sidebar code type-check / run | ❌ **not done** here (no macOS SDK). API names were checked against Apple's documentation (`tableView(_:shouldEdit:row:)`, `tableView(_:toolTipFor:rect:tableColumn:row:mouseLocation:)`, `tableView(_:willDisplayCell:for:row:)`, `numberOfPreviewItems(in:)`, `previewPanel(_:previewItemAt:)`, `QLPreviewPanel.shared()`, `MainActor.assumeIsolated` (back-deployed, macOS 10.15+), `volumeAvailableCapacityForImportantUsage: Int64?`, `NSWorkspace.didRenameVolumeNotification`, `mountedVolumeURLs(includingResourceValuesForKeys:options:)`) |
| `BulkAttributeEnumerator` with the extended (clone) attributes, compiled / run | ❌ **not done**; its parser is unit-tested with hand-built buffers, including the commonext group |

On Linux, everything under `#if canImport(AppKit)` / `#if canImport(Darwin)` is left out, and the
executable becomes a CLI-only stub.

## Known gaps / TODO

- **Round-3 QA test conflict: resolved.** QA updated the test in round 4. It is now
  `testUnknownFlagsAndPrivateChargedInFull` and expects 16384, which matches P3. It passes.
- The progress sheet, the Cancel-first alert (`hasDestructiveAction`, macOS 11+) and the Quick
  Look `Thread.isMainThread` guards have been reviewed against Apple's documentation but **not
  compiled on macOS**.
- The Darwin ACL reader (`acl_get_link_np`, `acl_get_entry`, `acl_get_tag_type`,
  `acl_get_perm_np`), `applicationShouldTerminate`/`reply(toApplicationShouldTerminate:)`, the
  `NSMenuItemValidation` conformance and the AsyncStream progress consumer are **not compiled on
  macOS** yet. The ACL rules are only exercised with an injected ACL provider on Linux.
- All-or-nothing limits: TCC is detected only through `EPERM`. Changes made by other processes between the pre-pass and the delete, and I/O
  errors, can still leave an item partially deleted; this is reported explicitly. On Linux,
  `st_flags` doesn't exist, so the flag rules are only exercised with injected flags.
- Swift 6 mode for the AppKit code has only been reviewed by hand. `SunburstViewDelegate` is now
  `@MainActor`, and the Quick Look data-source witnesses are `nonisolated` +
  `MainActor.assumeIsolated`. Not compiled against the macOS 15 SDK here.
- Subtree pre-scan cost: deleting a huge folder walks it once before deleting (2 million entry
  cap). Restricted flags are only read on Darwin; on Linux `st_flags` doesn't exist.
- Case-insensitive matching is ASCII-oriented (`lowercased()`); unusual Unicode case pairs in
  system paths aren't a concern for the fixed protected list.
- **This round's features have not been compiled on macOS yet.** The first Mac build may need small fixes to API spellings,
  actor isolation (main actor) annotations or Auto Layout constraints in the UI code.
- `getattrlistbulk` record layout: the parser assumes `ATTR_CMN_ERROR` comes right after the
  returned-attributes set, as in the man-page example. Check this on a real volume, for example
  by comparing `--cli` totals with `du -sk`.
- Privileged deletion helper: interface only (`PrivilegedDeleting`), with no implementation.
- No DiskArbitration integration, and no APFS purgeable or snapshot accounting. Clone
  accounting is an estimate (see "APFS clone accounting").
- Directories' own metadata blocks aren't counted, only their contents.
- Deletion, including the subtree pre-scan, runs on the main actor, so deleting large folders blocks the UI briefly.
- No drag-and-drop onto the deletion list, and no app icon.
- The extended-attribute buffer order (commonext after the file group) and the meaning of
  `ATTR_CMNEXT_PRIVATESIZE` come from the headers and man page. Neither has been checked on real
  APFS clones yet. To test (no sudo; it writes only `clone.file`, and `rm clone.file` undoes it), run
  `cp -c big.file clone.file` in a scratch folder, then the read-only `build/DiskRings --cli <dir>`;
  you should see one "clone" row.
- The sunburst rebuilds all of its layers when navigating. That's fine for the default 5 rings,
  but very wide folders would benefit from reusing layers.

## R6 real-Mac finding 7D (P2): Cmd-Q beep during a delete — fixed in R7

**Symptom (real Mac, R6).** While the delete progress sheet was showing, Cmd-Q beeped and the
sheet showed no "Quitting…". The quit itself already worked: the app quit after the current item
and nothing was left half-deleted. So `.terminateLater` and the reply were fine, and the bug is
P2: wrong feedback plus a beep.

**Cause, from code inspection (not reproduced on a Mac).**

1. `DeletionProgressSheet.update()` rewrote the phase label and the Cancel title on every progress
   event. That erased "Quitting…" within milliseconds, so the first Cmd-Q seemed to do nothing.
2. The user then pressed Cmd-Q again. That second `terminate:` arrived while AppKit was already
   waiting on `.terminateLater`, and it went through the key sheet's responder chain for
   validation. AppKit answers it with a beep.

The sheet was already window-modal (`beginSheet`; no `runModal`/`beginModalSession` anywhere), so
the terminateLater flow was left as is.

**Fix.**

- **Sticky feedback.** Once quitting, the sheet keeps "Quitting after the current item…" and only
  updates counts and path. After Cancel it keeps "Cancelling…".
- **Cmd-Q handled in the sheet window.** `QuitForwardingSheetWindow.performKeyEquivalent` handles
  Cmd-Q directly. The first press calls `NSApp.terminate(nil)`. Later presses are swallowed (no
  beep, no second request), as decided by core `AppActivity.quitKeyAction()`.
- **Quit always enabled.** The Quit item targets `NSApp` explicitly. Validation in both the
  AppDelegate and the window controller returns true for `NSApplication.terminate(_:)`.
  `AppActivity.validate(.quit)` is always true. While a delete runs, everything else is false:
  scan, rescan, stop, deletion-list edits and delete.
- **Reply exactly once.** `requestTermination()` is idempotent, and `endDeletion()` replies once,
  also when the user pressed Cancel before Cmd-Q.

**Tests (Linux, core).**

- `QuitDuringDeleteTests.testMenuPolicy…` checks the validation policy.
- `testQuitMidRun…` and `testQuitAfterUserCancelAlsoReplies` check the state machine. With Cmd-Q
  during item b of a–d: a and b are deleted, c and d are not attempted, and exactly one reply is
  sent.

**Re-verify on the Mac.** Run `bash acceptance/acceptance_mac.sh`. The script is
QA's fixed R6 script, copied into the package; its default project is the package itself. Step 7D
now also asks whether every Cmd-Q was silent and whether "Quitting…" appeared within about 1 s.

| | |
|---|---|
| What it does | Builds into `./build` and runs the guided acceptance steps. 7D deletes `big1` from the test folder, then quits. |
| Paths | Writes only `/tmp/diskrings-accept/` and `<project>/build/`. Reads `/usr` and the mount table. Deletes only items staged under `/tmp/diskrings-accept/`. |
| sudo | Never (the script refuses to run as root). |
| Risks | Disk space for test files; a Finder window or app opening. Nothing outside `/tmp/diskrings-accept` is deleted. |
| Undo / recover | `rm -rf /tmp/diskrings-accept` (test data only) and `./build.sh clean` (deletes only `./build`). If the app hangs over 2 min, Force Quit it (⌥⌘⎋) and report a FAIL. |

To re-check only 7D, set the other steps to manual skip, or run the GUI by hand. Open
`build/DiskRings.app`, scan `/tmp/diskrings-accept/gui`, add `big1` and `big2`, choose Delete
Permanently, and press Cmd-Q 2–3 times during "Deleting item 1 of 2".

Expected: no beep; "Quitting…" appears at once; the app quits after item 1; `big2` still exists.

## Look & feel: icon direction A and design tokens (R8)

**App icon.** `Resources/AppIcon.icns` uses direction A, "lifted piece"
(抬起的一块): a deep-teal plate, a warm double ring, and a white sector with a check mark popping
out. The masters are in `Resources/icon-master/`.

- The icns holds 10 PNG chunks, `icon_16x16` through `icon_512x512@2x`:

  | OSType | Size | | OSType | Size |
  |---|---|---|---|---|
  | `icp4` | 16 | | `ic12` | 64 (32@2x) |
  | `ic11` | 32 (16@2x) | | `ic07` | 128 |
  | `icp5` | 32 | | `ic13` | 256 (128@2x) |
  | `ic08` | 256 | | `ic14` | 512 (256@2x) |
  | `ic09` | 512 | | `ic10` | 1024 (512@2x) |

- Pixel sizes up to 32 use the simplified master, which stays legible at 16 and 32 px.
- `Info.plist` sets `CFBundleIconFile=AppIcon`. `./build.sh app` and
  `scripts/make-app-bundle.sh` copy the icns into `DiskRings.app/Contents/Resources/`.
- **Checks:** `./build.sh test`, `./build.sh app` and `./build.sh doctor` all run a read-only
  structure check: magic, header length equal to file size, and all 10 chunk ids.

**Regenerating the icon (box or dev machine only, optional).**

| | |
|---|---|
| Command | `python3 scripts/make-icns.py` |
| What it does | Renders the SVG masters with `rsvg-convert`, packs the icns by hand and verifies it. |
| Paths | Reads `Resources/icon-master/*.svg`. Writes only `Resources/AppIcon.icns` and a temp folder. |
| sudo | No. |
| Risks | Needs `rsvg-convert` (librsvg). Overwrites the committed icns. |
| Undo | Restore the icns from the zip or git. |

To check an existing icns read-only, run `python3 scripts/make-icns.py --verify Resources/AppIcon.icns`.

**Colours.** `Sources/SunburstGeometry/Theme.swift` is portable and has no AppKit.

- It holds the light and dark tokens, generated from `Resources/DesignTokens.json` (a copy of the
  design team's `tokens.json`).
- It also has `RGB` hex parsing and the sunburst palette: top-level slices take the categorical
  colours apps → dev in order, deeper rings mix toward the surface colour, the aggregated "other"
  slice uses `chart.other`, and protected/other-volume items use `protected`.
- `Sources/DiskRingsApp/Theme+AppKit.swift` wraps the tokens in dynamic
  `NSColor(name:dynamicProvider:)` colours, with no asset catalog.

Where they're applied:

| State | Tokens used |
|---|---|
| Whole window | `windowBg` |
| Sidebar | `sidebarBg` |
| Tables | `surface` |
| Text | `textPrimary` and `textSecondary`; protected rows use `protected` |
| Scan Folder… button | `accent` |
| Empty state | Chart title in `accent` |
| Scanning | Status text in `accent` |
| Results | Sunburst palette; centre disc in `surface` and `separator`; segment strokes in `windowBg` |

Layer colours are re-resolved on `viewDidChangeEffectiveAppearance`, so switching light/dark
updates the chart.

**Tests.** `ThemeTokensTests` (4) checks:

- every one of the 22 tokens in each mode against the JSON;
- `parse` round-trips;
- malformed hex values are rejected;
- contrast: primary text ≥ 7:1, secondary text ≥ 4.5:1 in both modes;
- palette assignment.

**Previews.** These are box-rendered approximations, not AppKit screenshots. `scripts/preview/`
renders SVG mocks with the real `SunburstLayout`, `ThemePalette` and tokens, then rasterises them
with rsvg. The raster output is not part of this repo:

- `window-{light,dark}-{empty,scanning,results}.png`
- `icon-sizes.png`

## Localization: English + Simplified Chinese (R9)

The app UI is fully localized: menus, buttons, alerts, the progress sheet, the empty state,
status text, tooltips and the delete refusal reasons. `--cli` output stays English.

- **App strings.** Every user-visible string goes through `tr("key", args…)`
  (`Sources/DiskRingsApp/Localization.swift`), a thin wrapper around `NSLocalizedString` with
  stable dotted keys such as `confirm.permanent.title`. Numbers use `%ld`, text uses `%@`, and
  `%1$@`-style positions are used where Chinese word order differs.
- **Core reasons.** The core keeps its enum codes and English `description`s, so tests and the CLI
  are unchanged. `Sources/DiskScanCore/ReasonText.swift` maps every `DeletionGuard.Reason`,
  `Caution`, checker detail (flags, ACL, read-only, sticky, Full Disk Access, read errors) and
  `DeletionError` to a key plus arguments. The app renders them through `NSLocalizedString`; on
  Linux, or when a key is missing, the English template is used.
- **Files.** `Resources/en.lproj/Localizable.strings` and
  `Resources/zh-Hans.lproj/Localizable.strings`, **217 keys each**. Both are generated by
  `scripts/gen-strings.py` from `scripts/l10n_table.py` plus the core templates; the committed
  files are what the app uses. `Info.plist` sets `CFBundleDevelopmentRegion=en` and
  `CFBundleLocalizations=[en, zh-Hans]`.
- **Bundling.** `./build.sh app` and `scripts/make-app-bundle.sh` copy both `.lproj` folders into
  `DiskRings.app/Contents/Resources/`. The single-module `swiftc` build makes `Bundle.main` the
  `.app`, so the lookups work.
- **Language choice.** `AppLanguage.pick` (core, unit-tested) maps any Chinese system language to
  zh-Hans and everything else to English:
  - zh-Hans, zh-CN and zh-SG;
  - zh-Hant, zh-TW, zh-HK and zh-MO too, because only Simplified Chinese ships and it is more
    readable to those users than English.

  The app reads strings from that `.lproj` bundle directly and never writes the `AppleLanguages`
  preference.
- **Tests.** `LocalizationTests` (7):
  - both files parse with the test's own `.strings` parser;
  - both have the same key set with no empty values;
  - format specifiers match per key, with positional and sequential forms normalized;
  - every `tr("…")`/`NSLocalizedString("…")` key in `Sources/DiskRingsApp` exists in en, and no
    key is unused;
  - every Reason, Caution and DeletionError code has a key;
  - rendering through `en.lproj` reproduces the English `description` exactly, while zh-Hans
    differs and leaves no stray `%`;
  - checker details and flag lists are localized, and unknown text stays English;
  - the permanent-delete and Trash wording are distinct;
  - language picking.
- **Build check.** `./build.sh test`, `./build.sh app` and `./build.sh doctor` run
  `check_strings`, a read-only pure-awk check: same keys, no empty values, same specifiers.
- **Preview.** `l10n-zh-Hans-delete.png` is a box-rendered mock, not a screenshot, and is not part of this repo.

**Re-checking the language on the Mac (optional).** This launches the app once in
Chinese without changing any system setting.

| | |
|---|---|
| Command | `open build/DiskRings.app --args -AppleLanguages '(zh-Hans)'` |
| What it does | Starts the app with a one-off language argument. |
| Paths | Writes nothing; the argument applies to this launch only. |
| sudo | No. |
| Risks | None. |
| Undo | Quit the app; the next normal launch follows System Settings again. |

Use `'(en)'` for English. The app picks the language from the preferred-languages list, which this
argument overrides for that launch only.

### 简体中文说明

DiskRings 已完整支持简体中文。系统语言为中文（简体或繁体）时显示简体中文，其他语言显示英文；命令行（`--cli`）输出仍为英文。

- **永久删除（无法撤销）：**确认框默认按钮是“取消”。
- **移到废纸篓（可在清倒前恢复）：**确认框中有单独的说明。
- **拒绝原因：**删除被拒绝时，原因（例如“已锁定（uchg）”或“没有完全磁盘访问权限”）会以中文显示，并提示前往“系统设置 > 隐私与安全性 > 完全磁盘访问权限”。

如需临时以中文或英文启动（不修改任何系统设置），运行 `open build/DiskRings.app --args -AppleLanguages '(zh-Hans)'`。

## R10: Chinese UI fixes, appearance option, BSD tool portability

Base version: the CEO-patched zip (SHA256 `bff858e9…`, `build.sh` line 230 `awk 'NF{…; exit}'`).
It was diffed against the working tree (that line was the only difference) and adopted.

**Real-Mac Chinese UI fixes.**

- **Sidebar overlap.** The volume table had collapsed and its header sat under the hint text.
  Cause: the R8 `NSBox` sidebar sized its content view by frame, not Auto Layout. Now a plain
  `SidebarView` draws the sidebar colour and the stack is pinned to it by constraints:
  - the table takes the flexible height, at least 96 pt, with low hugging and compression
    resistance;
  - the hint wraps (word wrap, unlimited lines, required vertical compression resistance and
    hugging), and its `preferredMaxLayoutWidth` follows its real width;
  - the sidebar is at least 240 pt wide.
- **Empty state.** The centre now shows "选择一个磁盘或文件夹开始扫描" plus a secondary line,
  "点按左侧的磁盘，或使用“扫描文件夹…”（⌘O）。". It uses its own wrapping layout up to 420 pt
  wide, so it's no longer truncated.
- **Column headers.** "占用空间（估算）" became **占用空间** (en "On Disk"); the estimate note moved
  to the header tooltip. Every column's `minWidth` and `width` is at least the header's measured
  `cellSize` plus padding, in both languages.
- **Progress sheet.** The phase text wraps up to 3 lines and the sheet is 180 pt tall. Buttons
  keep their intrinsic sizes (no fixed widths) and the status bar truncates in the middle by
  design.
- **Length budgets.** `LocalizationLayoutBudgetTests` sets display-width limits (CJK counts 2) on
  column headers, buttons, menus, titles, the empty state and the hint. It also enforces the
  terminology.

**Terminology: Volume = 磁盘.** Apple's Disk Utility uses 宗卷, but most users think in
disks. The Chinese UI uses **磁盘** everywhere: 磁盘 / 可用空间,
点按磁盘即可扫描, 启动磁盘, 其他磁盘, and refusal reasons such as 磁盘根目录. A test fails if
宗卷 appears in zh-Hans.

**Appearance: View > Appearance (显示 > 外观).** Choices are Follow System / Light / Dark
(跟随系统 / 浅色 / 深色).

- Radio-style checkmarks are set in `validateMenuItem`, and the items stay enabled during a
  delete.
- The choice maps to `NSApp.appearance` (nil / `.aqua` / `.darkAqua`).
- It's stored in `UserDefaults` under `DiskRingsAppearance` and applied in
  `applicationDidFinishLaunching` before the window is created.
- Dynamic token colours and `viewDidChangeEffectiveAppearance` redraw the theme on change.
- Portable `AppearancePreference` (core) and its tests: raw-value round-trip; unknown or
  wrong-type values fall back to system; persistence through an injected `UserDefaults` suite;
  menu keys present in both languages.
- To reset it on the Mac (optional):

  | | |
  |---|---|
  | Command | `defaults delete app.diskrings.DiskRings DiskRingsAppearance` |
  | What it does | Removes that one preference, so the app follows the system again. |
  | Paths | The app's own preferences domain only. |
  | sudo | No. |
  | Risks | None. |
  | Undo | Choose the appearance again in the menu. |

**BSD vs GNU audit (build.sh and scripts).**

- **`od` header read (`check_icon`).** BSD `od` can print an extra line and pads columns
  differently. The output is now squeezed with `tr -s '[:space:]' ' '` and the first line with at
  least 4 fields is used (`awk 'NF>=4{…; exit}'`). Verified against a simulated BSD output with an
  extra blank line.
- **`sort`.** Every sort is `LC_ALL=C` (5 places), so key order is locale-independent between
  the two `check_strings` passes.
- **The `check_strings` awk program.** It produces identical output under GNU awk, mawk and the
  BWK one-true-awk (`nawk`, the base of macOS awk).
- **Already portable:**
  - `wc -c`/`wc -l` padding is stripped with `tr -d ' '`;
  - `head -c`, `grep -o/-m/-q/-a`, `find !` and `sed -n` are POSIX/BSD-safe;
  - `build.sh` uses no `stat`, `readlink -f`, `sed -i`, `date -d` or `mktemp` flags.
- **QA's acceptance scripts.** Unchanged. They are macOS-native (`chflags`, `chmod +a`, `ls -le`,
  BSD `seq`/`xargs`), and their self-test already rejects GNU idioms (`stat -c`, `readlink -f`,
  `sed -i`, …).

**Previews.** These are box-rendered mocks, not screenshots, and are not part of this repo:
- `window-zh-Hans-light.png`
- `window-zh-Hans-dark.png`
- `l10n-zh-Hans-delete.png` (re-rendered with 磁盘 terminology)


## Batch 1: Layout skeleton (direction 1) + dashboard + delete zone

Confirmed direction: **sunburst A + window layout 1**. This batch builds the page structure and
wiring; sunburst A polish and the full delete-confirm sheet are Batches 2–3.

**Tokens.** `Resources/DesignTokens.json` synced from the design team's `tokens.json` (34 keys /
mode). Portable `ThemeTokens` gained canvas / glass / neon / danger / warning / chart.mixed /
chart.merged (glass carries alpha via `RGBA`). `Theme+AppKit` exposes matching dynamic
`NSColor`s and `NSFont.drStatNumber` / `drBodyNumber`.

**Home page.** Title “看看你的 Mac 被什么占满了” / “See what's filling up your Mac”; glass cards
for the internal disk (capacity bar + free text), first external disk if any, and a dashed
“Scan Folder…” card; FDA tip bar. Card clicks call the existing volume / folder scan entry
points. `‹ Disks` / ⌘1 returns home (View menu + toolbar).

**Results page.** Toolbar (breadcrumb-ish path, Content | Reclaimable segment, search) →
5 `StatTileView`s (Total / Used / Free / Reclaimable-with-neon / Largest) → `NSSplitView`
(glass sunburst panel | largest-items list + ✓ Reclaimable stub card) → `DangerZoneView`
(14 pt gap, danger fill/border/hatch; empty = dashed separator hint).

- Window default **1280×800**, min **960×640**, `setFrameAutosaveName`, `.fullSizeContentView`,
  canvas background.
- Width < 1100 hides Total and Free tiles.
- Largest item = largest **child of the current focus** (not whole-disk max file).
- Reclaimable mode segment only toggles a flag (Batch 2).
- Search filters the largest-items list by name.

**Danger zone.** Chips from `BasketSnapshot` (⚠ via `BasketRisk`); red-outline permanent button +
primary “Move to Trash (Recommended)” (Return). Wired to the existing confirm → caution →
`DeletionList.deleteAll` flow (confirm UI unchanged this batch). Protected items still refuse
add. Chip click removes from the basket. Drag-and-drop onto the zone is TODO (existing add-to-
list / sunburst collect still feed the same model).

**High-risk (chips only; does not change DeletionGuard):**
- `Library/Caches` (and under it) → **not** high-risk (cleanable).
- Other `~/Library` or `/Library` paths, hidden names, `.app` bundles → high-risk.
- Item > 50 GB actual → ⚠.

**Reclaimable heuristic (Batch 1, documented TODO for a real rule engine):** sum actual size of
directories named like Caches/Cache/tmp/Logs/…, paths under `…/Library/Caches`, `/tmp`, and a
couple of `private/var/folders` temp patterns; skip `.app` and hidden names; when a folder
matches, take its whole subtree and do not double-count children.

**Stubbed for later batches:**
- Batch 2: sunburst A (labels, type colours, glow arcs, rank badges); Reclaimable mode filtering;
  suggestion-card data from the rule engine; smart-start hint as real guidance (still no auto-drill).
- Batch 3: full delete-confirm sheet (type-to-confirm when high-risk, hold-to-confirm otherwise).

**Tests added (portable):** `BasketRiskTests` (5), `DashboardStatsTests` (3). DeletionGuard /
DeletabilityChecker / all-or-nothing delete core untouched.


## Batch 2: Sunburst direction A «霓虹环直标»

Implements sunburst redesign direction A on top of
Batch 1 layout. `DeletionGuard` / `DeletabilityChecker` unchanged.

**Geometry (`SunburstConfig.neonA`).** Centre hole + neon ring; 3 rings with radial gaps
(design 100–164 / 168–224 / 228–276, scaled by `D/600`); sector gap 1.5 pt; max depth 3;
composition bar on mixed dirs; reclaimable glow arc outside; tick ring; hover expands via
neon stroke + path dimming; external labels when chart width ≥ 820.

**Merge (§4.2).** Arc length &lt; 6 pt at mid-ring, rank &gt; 10 among siblings, 0-byte, or
unreadable → “其他 N 项”. Path compression when a child is ≥97% of its parent (label
`Users › tester`).

**Type colours (§4.3).** Batch-2 heuristic `FileCategory.classify` by folder name / extension
(Applications→apps, Photos/Movies→media, Music→audio, Documents→docs, .zip/.dmg/.pkg→archives,
src/.git/node_modules→dev, Library/Caches/System→system, else other). Mixed folders use
`chart.mixed` + composition bar; merged use `chart.merged` + dash stipple; protected = grey +
lock (no context-menu delete). Neon only on strokes/arcs. Danger colour never in the sunburst
(except the Batch-1 basket hatch elsewhere). Warning ⚠ only as icon + “谨慎” text.

**Markers (§4.4).** Ranks ①–⑤ on leaf-ish sectors; glow when `ReclaimableHeuristic` safe-byte
ratio ≥50%; ⚠ for Library / hidden / .app / Library paths; lock when protected ratio ≥50%.

**Toolbar [内容|可释放].** Same geometry; Reclaimable mode dims non-safe and neon-tints safe
(view C). Smart-start tip under centre (no auto-drill): if one child ≥60%, show
“Name › … 占 N%，直接进入 →” and drill on click.

**Tests.** `FileCategoryTests`, `NeonALayoutTests`, `LabelFitTests` (portable).

## Batch 3: Delete-confirm sheet (§4.6)

Final redesign batch. Spec: `layout-redesign.md` §4.6 + `delete-confirm-*.png/.svg`.
`DeletionGuard` / `DeletabilityChecker` / all-or-nothing delete core **unchanged**.

**Policy (`DeleteConfirmPolicy`, portable).** Method = trash | permanent. Secondary confirm:
- Trash → none (one-click primary on the sheet; still goes through existing caution → `DeletionList.deleteAll` → DeletionGuard).
- Permanent + any checked high-risk → type-to-confirm exact phrase “删除 N 项” / “Delete N items” (N = checked count).
- Permanent + no high-risk → hold 1.5s.
- Return/Enter triggers primary only for Trash; Permanent clears `keyEquivalent`. Esc cancels.
- Library/Caches not high-risk; Library other / hidden / `.app` are; >50 GB gets ⚠ (`BasketRisk` from Batch 1).

**UI (`DeleteConfirmSheet`, ~640 pt `beginSheet`).** Summary tiles (items / size / high-risk / auto-excluded);
high-risk group with yellow leading bar + consequence copy; normal group with ✓; per-item checkboxes;
method radios (Trash default; Permanent in red attributed title); type field or hold progress;
primary wired to trash / permanent pipelines. Protected items never enter the basket (already refused
at add-time); if present they list under “已自动排除”.

**Undo toast.** Trash success → 8s toast with Undo using `trashItem` `resultingItemURL` via
`TrashUndoLog` / `TrashDeleter(undoLog:)`. Permanent has no undo.

**L10n.** New confirm.* / toast.* keys; en + zh-Hans via `gen-strings.py`. Volume stays 磁盘.
Obsolete NSAlert confirm keys removed (sheet replaces them).

**Tests.** `DeleteConfirmPolicyTests` (7): phrase, matrix, Return-key policy, primaryEnabled,
checkbox filtering, high-risk grouping/build, empty-checked. SelfTest +1 check.

**Left as stubs / known gaps.** DangerZone `registerForDraggedTypes` drop target (no sunburst/table
drag source yet). Scan animation §4.7. Full reclaimable rule engine (Batch 1 heuristic remains).
Mac AppKit compile of the new sheet not run here.

## P1 fix: hang after scanning a 5M-item volume (Oct 2026)

**Symptom (macOS 15.3, `/System/Volumes/Data`, 5,079,372 files):** progress froze on the last
path, dashboard showed —/0 bytes, sunburst still in the empty state; Stop did not respond.

**Root cause (confirmed by `sample`, 7486/7486 main-thread samples):** after the scan finished,
`currentChanged()` → `SunburstView.rebuild` → `SegmentMarkers.annotate` called, **per visible
sector**, `FileNode.dominantCategory()/categoryMix()` (recursive walk of the whole subtree,
`FileCategory.classify` with full `FileNode.path` + Foundation `String.contains` per node) and
`reclaimableSafeRatio()` (`ReclaimableHeuristic.sum`, again `FileNode.path` per node), plus the
dashboard's full-tree `ReclaimableHeuristic.sum` twice — all on the main thread, no cache.
Measured with the old code: one root rebuild over a 100k-node tree = 4.2 s; at 5M it does not finish.
The scanner itself was fine (aggregate already off-main; progress already ≤10 Hz).

**Fix.**
- `TreeAnalysis` (SunburstGeometry): one iterative, background, O(n) pass after the scan computing
  per-directory category mix (8 inline buckets) and reclaimable bytes; side table keyed by node.
  Path facts come from `PathTraitsTracker` (parent's traits + lower-cased name bytes; no full paths,
  no Foundation `contains`), identical results to the old rules (tests compare against the old code).
- `SunburstView` / dashboard only read cached values; while the analysis is missing they use O(1)
  fallbacks (never a subtree walk). Rebuilt in the background after deletions / metric toggle.
- Scan flow: scan → status “正在整理结果…（可随时停止）” → background analysis (Stop cancels within
  ~4096 nodes; results are shown without hints) → results. Progress coalesced (`ProgressCoalescer`, at
  most one pending main hop, O(1) per tick).
- `ReclaimableHeuristic.sum` is iterative (no recursion, no `path` per node).
- Package: `SunburstGeometry` now depends on `DiskScanCore` (single-module `build.sh` unchanged).

**Timings (box, Linux x86_64, release):** 5M-node synthetic tree: precompute 5.4–5.7 s (off-main);
root rebuild+annotate afterwards 4.9 ms (256 segments). Debug: 100k 0.08 s / 500k 0.43 s (ratio 5.4).

**Tests:** `PostScanPipelineTests` (7; the 5M budget test is opt-in:
`DISKRINGS_HEAVY=1 swift test -c release -Xswiftc -enable-testing --filter PostScanPipelineTests`).

Mac diagnostics: `docs/DIAGNOSE_HANG.md`.

## Simplify v2: variant 1 «Finder-style» + top capacity bar (Oct 2026)

Spec: `diskrings-design/simplify-v2/README.md` (+ `simplify/simplify-plan.md` §1 for
performance) and `simplify-v2/capacity-bar/README.md` (approved scope addition).

**Removed.** Neon/glow/glass, tick ring, external labels, rank badges, the
content/reclaimable toggle, dashboard tiles, animations, HoldToConfirm, the bottom status
bar, and their dead code (FileCategory, SegmentMarkers, LabelFit, PathTraits,
DashboardStats, LayoutChrome, CategoryMix/PostScanPipeline, StatusBarView). Net l10n:
217 → 203 keys per language (61 removed for the redesign + 2 status-line keys removed with
the status bar; 36 + 13 added).

**Added.**
- Native controls, system font, README §4.1 tokens (`Resources/DesignTokens.json`).
- `ChartModel` (SunburstGeometry): ≤150 segments, 3 rings, README §4.5 OKLCH colouring
  (container rule, sibling hue spread, fixed container/other/protected colours, hatch+lock).
- `NSOutlineView` mirroring the sunburst 1:1 (selection + hover synced both ways), hidden-items
  footer, bottom delete bar (tokens, risk summary, 永久删除… / 移到废纸篓… ↩), never "drag here".
- Permanent delete always requires typing 「永久删除」/"Delete Permanently"; badge 「高风险」;
  ⌘⌫ opens the confirm sheet. Trash stays the default with the 8 s undo.
- **Top capacity bar** (`CapacityBarModel` + `CapacityBarView`): segments = the sunburst's
  root-level branch roots in the same order and colours (a ≥50% ring-1 container expands into
  its children); `~/Library` vs `/Library`; protected = grey hatch 「系统保护」; 其他 = neutral
  grey; used > scanned adds a grey 「系统与快照」 segment; free track has a 0.5 pt stroke.
  Legend is one line: branches < 3% of the disk fold into 「+N 项」, then the smallest shown
  branch folds until it fits. Drilled down, the bar still shows the whole disk: out-of-scope
  segments go grey at 0.55, a 1.5 pt bracket marks the scope, and the legend row reads
  「当前：… · 占已使用的 N%」. Click a segment/legend entry to enter that branch; hover = opacity
  + tooltip; each segment is an accessibility button. Content height < 720 → 36 pt compact
  single line, no legend; chart scale floor 0.75. The bar reads only the cached root-level
  chart model and the volume capacity read once per scan. Scan time moved to the
  「重新扫描」 tooltip; transient status (refused adds, deletion summary, scan notes) shows as
  an 8–12 s notice in the bar's legend row; scan progress + Stop live in the bar's title row.

**Performance (box, release, 5M-node synthetic tree).** Analysis 2.01 s; chart rebuild
worst 2.81 ms (< 16 ms); hover worst 0.094 ms (< 2 ms); capacity-bar build 0.037 ms, drill
scope 0.008 ms. Resizes change frames/transforms only (no rebuild).

**Previews.** `scripts/preview/main.swift` (compiled with the real core sources) dumps
layout/colours/outline/basket/sheet/capacity bar; `scripts/preview/render.py` renders them with
the zh-Hans strings and tokens via headless Chrome. Box-rendered, not macOS screenshots.

**Known deviations.** Sunburst click = select, double-click = enter; search filters direct
children; the hidden-items footer has no 「显示」 link; sheet group 2 says 「普通」 unless all
items are caches (「可重建」). AppKit code is syntax-parsed on the box but not type-checked.

## UI review v1-impl fixes (Oct 2026)

Fixes for `review/ui-review-v1impl.md` (4 × P1, 12 × P2):

- **Shortcuts (P1-1):** the delete-bar buttons have no ↩. Only ⌘⌫ opens the confirm sheet, and ↩ works only inside the sheet (trash mode; permanent mode has no default key). ⌘↓ enters the selected folder. The keys come from `ShortcutPolicy`, which `ShortcutPolicyTests` covers (including a source scan for a literal ↩).
- **Filled buttons (P1-2):** the white title follows `isEnabled` and whether the window is key (`FilledButtonStyle.usesWhiteTitle`).
- **Protection display (P1-3/4):** `ProtectionMap` is computed in the background `TreeAnalysis` pass. Only SIP/system locations (`systemLocation`, `sipProtected`, `containsRestricted`) mark a whole subtree. Essential folders such as ~ and /private are marked on that row only. Chart and outline rebuilds do no filesystem work: the 100k drill benchmark takes ≤ 8 ms (about 3.6 ms in debug). The live `DeletionGuard` check still runs, unchanged, before adding to the delete zone and before deleting.
- **P2:** search is now "筛选此文件夹" (Filter This Folder) with match and no-results messages. The hidden-items footer has a "显示" (Show) link and no-access badges. Stop is regular size. Notices last clamp(8 + n/10, 8, 15) s and pause on hover. The legend refits with a cache. The container-remainder segment keeps the bar complete. Dark secondary text is #AEAEB2. The free dot has a 0.5 pt stroke. Keyboard navigation works in the sunburst. Skipped items stay reachable from the undo toast.
- **Previews:** `scripts/preview/render.py` now matches the source, and every image carries a **仅供参考 · reference only** label.

## Mac build failure of b8f45c6b and the `./build.sh check` gate (Oct 2026)

**What broke on the Mac:**
1. Two internal `final class CapacityBarView` existed in the single module: the new top capacity bar, and the small home-page bar in HomePageView.swift. The home-page one is now `VolumeUsageBarView`.
2. `SunburstView` used `Sector.span`, which did not exist. `ChartModel.Sector.span` (= endAngle − startAngle) is now added.
3. A `var` that was never mutated is now a `let`.

**Why the box missed it:** every AppKit file is wrapped in `#if canImport(AppKit)`, so on Linux both SwiftPM and `SWIFTC=… ./build.sh` compile those files to nothing. The extra "forced parse" step only ran `swiftc -parse`, which checks syntax and never resolves names, types or members. SwiftPM also builds DiskScanCore and SunburstGeometry as separate modules, so a cross-file name clash only exists in build.sh's single module, and only with the AppKit files present.

**The gate.** `./build.sh check` is box-only, writes only `build/check`, needs no sudo, and runs:
1. `scripts/check/dup-types.py`: duplicate top-level type names across all of Sources/. It runs on every OS. `SourceGateTests` performs the same check inside `swift test`.
2. On Linux only, `scripts/check/typecheck-appkit.sh`:
   - builds stub modules `AppKit`, `Quartz`, `QuartzCore` and `UniformTypeIdentifiers` from `scripts/check/shim/`;
   - copies Sources through `prep.py`, which strips `@objc`, turns `#selector(x)` into a closure naming `x` (so `x` must exist), and checks textually that each selector target is `@objc` or an override, and that files using QL\*/UTType import Quartz / UniformTypeIdentifiers;
   - runs `swiftc -typecheck -D SINGLE_MODULE` over all 40 files, once in Swift 5 mode and once with `-strict-concurrency=complete`. Both passes must report 0 errors and 0 warnings.
3. `scripts/check/selftest-gate.sh` re-injects the failure defects (the duplicate name and the missing `span`) plus a wrong AppKit signature and a non-@objc selector into a temp copy. It proves `check` fails on each one and passes on the clean tree.

**Limits:** the stubs are hand-written approximations of the macOS SDK.
- A wrong stub signature can hide a real error or report a false one.
- Optional delegate methods have default implementations, so a misspelt delegate method is not caught.
- macOS 13+ availability is caught only for the few APIs marked deprecated in the stubs.
- `#if canImport(Darwin)` branches in the core are still not compiled on Linux.
- swiftc may stop after the first failing file, so several broken files show up one run at a time.

Passing the gate is necessary but not sufficient. The Mac build is still the authority.

## Fix: list pane missing at ~1024 pt (Oct 2026)

- **Likely cause** (not reproducible on the box): the split view's delegate implemented `splitView(_:shouldAdjustSizeOfSubview:)`. With that delegate method NSSplitView falls back to frame-based resizing and only resized the chart. The list pane started with a zero frame because the results page is hidden at launch, so it stayed at 0 width despite its ≥ 360 constraint. That constraint then gets broken by AppKit, which normally logs "Unable to simultaneously satisfy constraints".
- **Fix:**
  - The delegate is removed, so panes cannot collapse and width constraints and holding priorities apply.
  - Both panes get non-zero starting frames.
  - On first display the divider is placed at the spec ratio (`SplitLayout`: chart ≥ 520; list 436, range 360–480; window ≥ 960×640, which is more than 881).
  - The window autosave name changed to `DiskRings.MainWindow.v4`, so frames saved by the old build are ignored.
- **'«' at the bottom left:** nothing in the source draws that glyph; the only custom chevrons are the toolbar ‹ ›. The startup log records the class chain of the view under window point (12,12), so the next run identifies it.
- **In-ring labels:** `ChartModel.fitLabel` tries the full name, then the last path component, then the last component cut at the end ("Containe…"). If none of those fit, the sector gets no label; names are never cut in the middle.

**Reading the startup layout log on the Mac:**

    log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "layout"'

- **What:** prints DiskRings' layout lines from the last 10 minutes: window size, chart and list frames, collapsed state, and the view under the bottom-left point. A line starting with `PROBLEM` means the list was narrower than 360.
- **Paths:** reads the system log only; writes nothing.
- **sudo:** none.
- **Risk:** none (read-only).
- **Undo:** nothing to undo.

Open a scan first so the results page is shown. For a live view, use `log stream` with the same `--predicate`.

## Sunburst labels (tiered) — designer spec 2026-10-13

Labels are placed by `LabelLayout.place` (Sources/SunburstGeometry/LabelLayout.swift), per scale tier,
and cached in `ChartModel.labelCache` (≤ 6 layouts); drawing, hover and appearance changes never re-measure.

Order (default `.rotatedNameFirst`): name + size (horizontal; mid angle, most-horizontal point, 1/3, 2/3)
→ rotated name (along the arc, then radial; always reads left→right) → size only → rotated size → hidden
(hover tooltip: name / path / size · share). Largest sectors first; every box is collision-checked (SAT).
`.spec` (size before rotated name) remains available.

Screen sizes (pt), k = chart scale (floor 0.75, cap 1.15):

| item | screen value | k 1.15 | k 1.0 | k 0.87 | k 0.76 |
|---|---|---|---|---|---|
| name font (medium) | max(10, 11k) | 12.65 | 11 | 10 | 10 |
| size font (regular) | max(10, 10k) | 11.5 | 10 | 10 | 10 |
| name line | max(13, 14k) | 16.1 | 14 | 13 | 13 |
| size line | max(12, 12k) | 13.8 | 12 | 12 | 12 |
| padding | max(2, 2.5k) | 2.9 | 2.5 | 2.2 | 2.0 |
| box inset | 1.5k | | | | |
| ink opacity | 1.0 for every line | | | | |

Scale tiers: k ≥ 1 → one tier (metrics scale with k); k < 1 → k_b = max(0.75, ⌊k/0.05⌋·0.05), i.e.
0.75/0.80/0.85/0.90/0.95. Chart units = screen value / k_b, so text is ≥ 10 pt (≤ 10.6 pt within a tier).
Re-layout happens only when the tier changes: immediately for a non-live resize, otherwise in
`viewDidEndLiveResize` (no relayout during a live drag; the old labels just scale with the transform).

Truncation: full name → last path component → reverse-domain name without its root
(com/org/net/io/cn/me/dev, ≥ 3 segments: `com.tencent.xinWeChat` → `tencent.xinWeChat`) → tail truncation
keeping ≥ 4 Latin letters or ≥ 2 CJK characters. “其他 N 项” is never truncated (falls back to size / hidden).
Ink: #1D1D1F or #FFFFFF, whichever has the higher WCAG contrast on the fill (worst 5.06:1 per the review).

Coverage, preview drill sample (52 sectors), text / with name / size-only / hidden:
k 1.0 → 46 / 39 / 7 / 6 · k 0.87 → 43 / 36 / 7 / 9 · k 0.76 → 36 / 33 / 3 / 16
(spec order, same metrics: names 34 / 30 / 22). Previous build (fixed 11/10 units): 44 / 40 at every k.
Reference renders (仅供参考): `diskrings-preview/drill-labels-k{100,087,076}-zh-{light,dark}.png`.

## Search (toolbar 「搜索文件和文件夹」)

Whole-tree, case-insensitive name search (`TreeSearch`, Sources/SunburstGeometry/TreeSearch.swift), run on a
background queue 200 ms after typing stops; a new query cancels the running one (token polled every 4096
nodes) and stale results are discarded by generation. ASCII queries use an allocation-free UTF-8 scan with ASCII
case folding (no lowercase index exists in the scan/TreeAnalysis); other queries use Foundation's
case-insensitive search. Results: the 500 largest matches, size descending (ties by name), each with its
parent path relative to the scan root, plus 「显示最大的 500 项，共 N 项匹配」 when truncated.
Clicking a result drills the chart to its parent and selects it; the list keeps the results.
Adding results to the delete zone goes through the normal path (DeletionGuard live check).
Esc (in the field or anywhere in the window, no sheet open) clears and restores the folder that was shown
when the search started; a new scan clears it; a deletion re-runs the query.
Diagnostics: `log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "filter"'`
(events start/done/discard/locate/escape/rescan/refresh + a wiring check at startup; query text is not logged).
Gate: `scripts/check/search-wiring.py` (part of `./build.sh check`, covered by the gate selftest).

### Regex search (opt-in)
Default mode is 包含 / Contains. The magnifier menu has a checkable 「正则表达式 / Regular Expression」 item and
「匹配相对路径 / Match Relative Path」; both are per session only (every launch starts in Contains / names; nothing
is written to UserDefaults). Typing `/pattern/` uses regex for that query only. While regex is on, a `.*`
badge shows inside the field. Matching is case-insensitive; the pattern is compiled once (NSRegularExpression);
an invalid pattern gives a red field border + 「正则表达式无效：…」 in the list area and runs nothing.
Guard: a search is aborted after 10 s (notice shown). The deadline/cancel flag is checked before every node in
regex mode, but one pathological match cannot be interrupted mid-call, so each subject is capped at 1024 UTF-16
units (names ≤ 255 bytes are never cut; long relative paths are matched on their last 1024 units, anchors keep
their real meaning).

Regex simplification: matching is a contains search (unanchored `firstMatch`), so redundant
leading `.*` / `.*?` and trailing (unescaped) `.*` / `.*?` are stripped before compiling. If what
remains is a plain literal (no regex metacharacters), the regex runs on the same fast
case-insensitive substring matcher as Contains mode — `.*backup.*` finds exactly what `backup`
finds. A bare `.*` is kept as is (matches everything). In Contains mode `.*backup.*` is literal
text (0 results, the no-results message is shown).

Regex state is shown WITHOUT any view inside the search field (an earlier `.*` label subview
could stay drawn by the toolbar field): with the menu item checked the placeholder reads
「搜索文件和文件夹（正则）」, the field tooltip names the mode, and the result footer starts with
「正则 · 」 (also for a `/pattern/` query). Gate: `scripts/check/search-field.py`.
Preview: `docs/previews/search-field-states-仅供参考.png`. When a search starts, the list
leaves the tree view immediately and shows 「正在搜索…」; errors, the timeout and zero results
always show a message in the list area.

### Tree access (background readers vs. deletion)
Background readers of the scanned tree: whole-tree search and TreeAnalysis (both off the main thread).
Chart/label layout, capacity bar, outline and protection display all run on the main actor. Deletion edits the
tree in place on the main actor (`removeFromTree` inside `DeletionList.deleteAll`). `TreeAccessGate`: readers
take a ticket before starting; before `deleteAll` the controller cancels and awaits every reader and blocks new
ones; afterwards it re-runs the search and the analysis.

### Chart outlines
Selection (2 pt) and hover (1.5 pt) outlines, hover and tooltip live in `ChartOutlineState`. Every layout
change (drill in/out, rebuild, label-tier relayout, search locate) recomputes them: the selection is kept only
if its node is still a sector, everything else is cleared.

### Timing tests
Budgets are release targets; debug test builds get ×2, TSan ×20. Loops assert p95 < budget and max < 6×
budget (a single preempted sample is not a regression); drill steps use best-of-3.


## Build stamp (which build is installed?)

`./build.sh app` writes `DiskRingsBuildID` into `Contents/Info.plist`:
`<version> (<build>) src:<first 12 hex of the source SHA-256> git:<commit or none> <UTC time>`.
It is logged at launch (category `build`) and shown in 关于 DiskRings (About panel credits).
The zip ships `SOURCE-SHA256.txt`; `scripts/source-hash.sh` recomputes it from the unpacked tree.

Check on the Mac:
- what: `defaults read "$PWD/build/DiskRings.app/Contents/Info" DiskRingsBuildID`
  (or `log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "build"'` after launching)
- paths: reads only that app bundle's Info.plist / the unified log; adjust the path if the app was copied elsewhere
- sudo: not needed
- risk: none (read-only)
- undo: nothing to undo
- match: the `src:` value must equal the first 12 characters of `SOURCE-SHA256.txt` in the zip
  (or of `scripts/source-hash.sh` run in the unpacked folder).

## Gate vs Swift 6.1 (main-actor isolation)

The Mac (Swift 6.1.2, SDK 15.5) rejected 8d609e17: `AppDelegate.showAbout` (nonisolated) called
the `@MainActor` `BuildInfo.showAboutPanel()`. The box compiler (6.0.3) had inferred the whole
`AppDelegate` class `@MainActor` from its `NSApplicationDelegate` conformance, so the gate passed.
Now:
- `AppDelegate` is explicitly `@MainActor`; `main.swift` enters the main actor with
  `MainActor.assumeIsolated` (back-deployed, fine for macOS 12) before creating it.
- The type-check uses a shim copy (`scripts/check/shim-noinfer.py`) in which delegate protocols
  carry `@MainActor` per requirement instead of on the protocol, so conformance never makes a
  whole class main-actor. This is stricter than either compiler, i.e. errs on the safe side.
- Three passes, all must be diagnostic-free: Swift 5, Swift 5 + `-strict-concurrency=complete`,
  and `-swift-version 6` (isolation violations are errors).
- Known 6.0-vs-6.1 difference: in `-swift-version 6`, 6.0.3 reports an unapplied reference to a
  main-actor method (our Linux stand-in for `#selector`) as a nonisolated call. Those diagnostics,
  and only when the column lies inside a rewritten `__selector(...)`, are dropped by
  `scripts/check/filter-selector-artifacts.py` (count printed). Any other 6.1-only rule changes
  cannot be reproduced on the box; the gate remains necessary, not sufficient.
- `scripts/check/selftest-gate.sh` case 6 re-introduces the exact bug and expects the error.
