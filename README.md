# DiskRings

DiskRings is a small native macOS disk usage analyzer written in Swift and AppKit. You pick a
folder or volume, it scans it, and it shows the result as an interactive sunburst next to a
list. You can put items in a delete zone and then move them to the Trash or delete them
permanently.

This repository is the application source and the scripts that build it. Version **0.1.0**
(bundle id `app.diskrings.DiskRings`, macOS 12 or later). An installer appears only after you
package one on a Mac; see [Package a disk image](#package-a-disk-image).

DiskRings is an independent implementation. It has no licensing, activation, registration,
update, or telemetry code.

## Features

- **Home.** Internal and external disks are listed with free and total space. Click a disk to
  scan it. Scanning the startup disk reads the user-data volume (`/System/Volumes/Data`),
  because the System volume is sealed. **Scan Folder…** (⌘O) picks any folder. A scan shows
  progress and can be stopped.
- **Results.** A sunburst and an outline of the same folders. Angle follows on-disk size, or
  logical size from **View › Size Rings by Logical Size**. Click to select; double-click a
  folder to open it. A capacity bar at the top still shows the whole disk while you drill in.
  Paths on the startup disk are shown as `/Users/…`, not under `/System/Volumes/Data`.
- **Counting.** Each hard link is counted once. APFS clones are an **estimate**: shared blocks
  and snapshots are not fully visible, so “on disk” can be higher than the space a delete would
  free. The column tooltip says so.
- **Search.** The toolbar field searches names in the scanned tree. The magnifier menu can turn
  on regular expressions, or you can type `/pattern/` for one query. Esc clears the search.
- **Delete zone.** **Move to Trash…** is the default. **Delete Permanently…** removes files
  in place and does not follow symlinks or cross volumes. Both ask first. Protected items are
  refused. See [Use the app](#use-the-app).
- **Other.** Quick Look (Space or ⌘Y), Reveal in Finder, and **View › Appearance** (follow
  system, light, or dark). The interface is English or Simplified Chinese. `DiskRings --cli
  <path>` prints a text report with logical and estimated on-disk columns and does not open a
  window.

## Requirements

- macOS 12 or later.
- To compile: the Command Line Tools (`xcode-select --install`) or Xcode 15+ with Swift 5.9+.
- The app is not sandboxed. It can scan folders your user can read. Mail, Messages, and some of
  `~/Library` stay hidden until you grant [Full Disk Access](#full-disk-access).

`./build.sh` never calls `sudo`. A normal build writes only inside `./build`. Packaging also
writes `./dist`.

## Build on a Mac

Run the commands in the folder that contains `build.sh`.

### Command Line Tools

This path does not need Swift Package Manager. It compiles the sources into one module.

```bash
xcode-select --install          # once
./build.sh                      # build/DiskRings
./build.sh app                  # build/DiskRings.app, ad-hoc signed
./build.sh doctor               # print the toolchain and SDK; writes nothing
./build.sh clean                # delete ./build only
```

```bash
open build/DiskRings.app
build/DiskRings --cli ~/Downloads
```

`ARCH=arm64`, `ARCH=x86_64`, or `ARCH=universal` selects the architecture (`universal` merges
both with `lipo`). `DEBUG=1` turns off optimization. `SDKROOT`, `DEVELOPER_DIR`, and
`TOOLCHAINS` are passed through and are not overwritten.

`./build.sh app` signs the bundle ad hoc (`codesign --sign -`). That is enough to run an app
you just built on the same Mac. Copying it to another Mac by AirDrop or a browser quarantines
it; use the install steps below.

Rebuilding changes the ad-hoc signature, so macOS may drop an earlier Full Disk Access grant.
Remove DiskRings from the list and add `build/DiskRings.app` again. A bare `build/DiskRings`
launched from Terminal uses **Terminal’s** Full Disk Access.

### Xcode or Swift Package Manager

For a Mac with Xcode 15+ (or a working Swift 5.9+ toolchain):

```bash
swift build
swift run DiskRings
swift run DiskRings --cli ~/Downloads
scripts/make-app-bundle.sh                 # dist/DiskRings.app, ad-hoc signed
scripts/make-app-bundle.sh --universal
```

Open `Package.swift` in Xcode, choose the `DiskRings` scheme and My Mac, then Run (⌘R). No
`.xcodeproj` is checked in.

### Known issues

`./build.sh doctor` prints the compiler, the SDK path, and whether they disagree.

- If the compiler and SDK are different builds, point one run at a matching SDK:
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ./build.sh`
  (use the versioned SDK path `doctor` prints). Leave `SDKROOT` unset afterwards.
- If clang reports `redefinition of module 'SwiftBridging'`, `doctor` prints the module-map
  paths. Fix that system file by hand, or reinstall the Command Line Tools. `build.sh` does
  not edit it.
- Last resort: in Finder, move `/Library/Developer/CommandLineTools` to the Trash (do not
  empty it yet), run `xcode-select --install`, then `./build.sh doctor`. Put the folder back
  from the Trash if the new install is worse.

On some Command Line Tools installs, `swift build` fails inside PackageDescription before any
app code compiles. `./build.sh` does not use Swift Package Manager, so that failure does not
block it. Full Xcode is the other option.

### Full Disk Access

Folders the app cannot read are marked unreadable and drawn in grey. To include them:

1. **DiskRings › Open Full Disk Access Settings…** (System Settings › Privacy & Security ›
   Full Disk Access).
2. Add `build/DiskRings.app`, or `dist/DiskRings.app` if you used the packaging script.
3. Quit DiskRings and scan again.

Files owned by another user or by root may still fail to delete. This repository has no
privileged helper.

## Package a disk image

A `.dmg` is produced on macOS (`hdiutil` and `codesign`). The default is an ad-hoc,
Apple Silicon disk image. The version in the file name comes from `CFBundleShortVersionString`
in `Resources/Info.plist` (currently 0.1.0).

```bash
./build.sh dmg --adhoc --arm64
# dist/DiskRings-0.1.0-adhoc-arm64.dmg and dist/SHA256SUMS
```

```bash
./scripts/package_dmg.sh --adhoc --universal
# dist/DiskRings-0.1.0-adhoc.dmg
```

Notarizing needs a Developer ID certificate and notary credentials that you set yourself. The
script does not open Keychain or an Apple ID prompt for you. If `IDENTITY` or the notary
variables are missing, `--notarize` stops and tells you to use `--adhoc` instead.

```bash
export IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='NotaryProfile'
./scripts/package_dmg.sh --notarize --universal
# dist/DiskRings-0.1.0.dmg
```

Ad-hoc file names include `-adhoc`. Those images are not notarized. The disk image
volume is named DiskRings, with the app and an Applications alias. Ad-hoc images also include
`安装说明.txt`, taken from [`docs/install-adhoc.zh.txt`](docs/install-adhoc.zh.txt).

On Linux, `./scripts/package_dmg.sh --dry-run --adhoc --arm64` only checks the script. It does
not write a disk image.

## Install a disk image you built

These steps install a `.dmg` produced by the packaging commands above.

1. Optional: `shasum -a 256 -c SHA256SUMS` next to the disk image.
2. Open the image and drag **DiskRings** to **Applications**.
3. Open DiskRings from Applications. If Gatekeeper blocks an ad-hoc build, use **System
   Settings › Privacy & Security › Open Anyway**. Do not turn off SIP, and do not turn off
   Gatekeeper for the whole Mac.
4. The same notes are in `安装说明.txt` inside an ad-hoc image.

If Open Anyway is not enough, this removes the quarantine flag from that one app and does not
need `sudo`:

```bash
xattr -dr com.apple.quarantine /Applications/DiskRings.app
```

## Use the app

1. On the home page, click a disk or **Scan Folder…** (⌘O). **‹ Disks** (⌘1) returns home.
2. Open folders from the sunburst or the list. Search from the toolbar if you need a name
   elsewhere in the scan.
3. Add what you want to remove to the delete zone, then choose **Move to Trash…** or
   **Delete Permanently…** (⌘⌫ opens the confirmation).

**Move to Trash** can be restored from the Trash. A short undo toast also appears after a
successful move.

**Permanent delete cannot be undone.** The confirmation asks you to type `永久删除` in
Chinese or `Delete Permanently` in English, then click the button. Return does not confirm a
permanent delete. The sheet states that the items will be erased immediately.

The app refuses to delete system locations, volume roots, a folder that contains another
volume, the home folder itself, and items flagged by SIP. Launch agents and daemons, apps
under `/Applications`, and items under `/private/var/folders` need a second, explicit
confirmation; the default there is to skip them. If a folder cannot be removed completely, that
item is left untouched. If a delete is interrupted after it has started, the summary lists what
was only partly removed so you can rescan.

Quitting while a delete is running cancels after the current item. It does not stop in the
middle of that item.

## 使用与永久删除

1. 在首页点按磁盘，或使用「扫描文件夹…」（⌘O）。「‹ 磁盘」（⌘1）回到首页。点按启动磁盘时，扫描的是存放你的应用和文件的数据卷，而不是密封的系统卷。
2. 在环图或列表中进入文件夹。工具栏可以按名称搜索本次扫描结果。
3. 把要清理的项目放进删除区，再选择「移到废纸篓…」或「永久删除…」（⌘⌫ 打开确认）。

**移到废纸篓**之后，可以在废纸篓里恢复。成功移走后，界面上还会短暂出现撤销提示。

**永久删除无法撤销，也无法从废纸篓恢复。** 确认框要求输入「永久删除」（英文界面为 `Delete Permanently`），再点按按钮。回车不会确认永久删除。确认框会写明这些项目将被立即抹掉。

下列位置不能删除：系统目录、磁盘根目录、里面还挂着别的卷的文件夹、你的主文件夹本身，以及受系统完整性保护（SIP）标记的项目。启动项、`/Applications` 里的应用，以及 `/private/var/folders` 下的项目，需要再确认一次，默认是跳过。某一项如果不能被完整删除，就会整项保留。删除已经开始后又被打断时，结果里会列出只删除了一部分的项目，便于你重新扫描。

删除进行中退出应用时，会等当前这一项做完再停，不会停在这一项的中途。

界面语言跟随系统：中文（简体或繁体）显示简体中文，其他语言显示英文。命令行 `--cli` 的报告始终是英文。显示 › 外观可以选择跟随系统、浅色或深色。

扫描受系统保护的文件夹时，到「系统设置 › 隐私与安全性 › 完全磁盘访问权限」里加入 DiskRings，然后重新扫描。读不了的文件夹会标成灰色。

安装和日常使用都不要关闭 SIP，也不要全局关闭 Gatekeeper。

## 简体中文

DiskRings 用环图和列表显示文件夹或磁盘占了多少空间，再把选中的项目移到废纸篓，或永久删除。

本仓库是源代码和打包脚本。版本 **0.1.0**，套件标识为 `app.diskrings.DiskRings`，需要 macOS 12 或更高版本。磁盘镜像要在 Mac 上自己执行 [打包](#package-a-disk-image) 才会出现在 `dist/`，仓库里没有现成的安装包。

在包含 `build.sh` 的目录中：

```bash
xcode-select --install
./build.sh app
open build/DiskRings.app
```

打包 Apple Silicon、未公证的磁盘镜像：

```bash
./build.sh dmg --adhoc --arm64
```

得到 `dist/DiskRings-0.1.0-adhoc-arm64.dmg` 和 `dist/SHA256SUMS`。打开镜像，把 DiskRings 拖到「应用程序」。若系统提示无法验证开发者，到「系统设置 › 隐私与安全性 › 仍要打开」。说明也写在镜像里的「安装说明.txt」，正文来自 [`docs/install-adhoc.zh.txt`](docs/install-adhoc.zh.txt)。
