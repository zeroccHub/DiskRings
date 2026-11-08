# DiskRings R6 Mac 验收脚本说明（修订：APFS 检测 / 前置检查 / BSD 兼容）（acceptance_mac.sh）

**用法**（在你自己的 Mac 上，以普通用户运行，**不要 sudo**）：
```
bash acceptance_mac.sh /path/to/diskrings-r6/DiskRings   # 需显式指定 R6 项目目录
SIZE_MB=64 GUI_FILES=100000 bash acceptance_mac.sh <dir>  # 用小一点的数据
AUTO=1 bash acceptance_mac.sh <dir>                       # 不逐步暂停（第 7 步 GUI 仍需手动）
```
- **前置检查（脚本开头，在任何 xcrun / swift / clang 调用之前）**：先运行 `xcode-select -p`（这个命令不会弹出安装框），并确认它返回的目录确实存在；之后才运行 `xcrun --sdk macosx --show-sdk-path`、`xcrun -f swift`、`xcrun -f clang`。任一项不满足就打印安装提示并退出（退出码 3），此时还没有创建任何东西。`xcode-select --install` 由你自己决定是否运行，脚本不会自动调用。
- **离线自测**：`bash acceptance_mac_selftest.sh`（Linux / macOS 都能跑，只在 mktemp 临时目录里操作）。它用采集到的那类 macOS 输出测试 df、diskutil、mount 的解析函数，并检查前置检查之前没有调用任何开发工具、没有 GNU 专属写法。
- 只写两处：`/tmp/diskrings-accept/`，以及项目里的 `build/`、`.build/`。以 root 身份运行会直接退出。
- 系统路径只做判断（check / preflight），不删除。`guardprobe delete` 在代码里写死：realpath 后必须位于 `/private/tmp/diskrings-accept/` 下才执行；它走的是 App 真正的 `DeletionList.deleteAll` + `PosixRecursiveDeleter`。
- **解锁/清理顺序（固定）**：`chflags -R nouchg` → `chflags -R nouappnd` → `chmod -R -N`（去掉 ACL）→ `chmod -R u+w` → `rm -rf`。脚本里的 `unlock()` 只接受 `$W` 下的路径。
- 恢复命令：`hdiutil detach /tmp/diskrings-accept/vol/mnt`，然后按上面的顺序执行；最后 `./build.sh clean`。
- 旧版本已备份：`acceptance_mac.r3.bak.*`、`acceptance_mac.r4.bak.*`、`acceptance_mac.r5.bak.*`、`acceptance_mac.r6.bak.*`（修订前）。

| 步骤 | 做什么 | 写/删 | 预期 |
|---|---|---|---|
| 0 | 打印环境信息，运行 `build.sh doctor` | 不写 | 只读，不输出 sudo rm -rf |
| 1 | build.sh test、build、swift test | build/、.build/ | 22/22；swift test 全过（Linux 上 116 个） |
| 2 | 用 `df -P -k` 取挂载点（/tmp 实际是 /private/tmp，挂载点通常是 /System/Volumes/Data），先看 `diskutil info <挂载点>` 的 Type (Bundle)，取不到再看 `mount` 括号里的类型；比较不区分大小写 | mkdir | apfs |
| 3 | 用 dd 造大文件，`cp -c` 造 2 个克隆，外加 1 个硬链接、1 个改过的克隆 | data/ | 可用空间只减约 1 份 |
| 4 | 用 C 程序调 getattrlist 读 CLONEID 等属性 | $W | 纯克隆的 cloneid 相同 |
| 5 | `--cli` 与 `du -sk` 对比 | *.txt | du ≈ 4×；ACTUAL ≈ 1×+1MB |
| 6 | 只做 guard 判断：系统路径、大小写变体、`..`、caution、拼写 | 不删 | 全部 BLOCKED / CAUTION |
| 6b | hdiutil 挂载镜像后做预扫描并尝试删除 | $W | 整体拒绝，一个文件都不动 |
| 6c | 正常删除 + 符号链接；ro / uchg / uappnd / 目录 uchg / ACL deny delete / ACL deny delete_child / 继承来的 ACL deny / 000 共 8 种 | $W/del-* | 每种都**整项拒绝**：删前删后完整文件清单完全相同，并显示 BLOCKED（R6 起 ACL 也必须被拒绝） |
| 7 | GUI：A 确认框回车/Esc＝取消；B 删除中 ⌘O/⌘R 和删除菜单为灰色，在 Checking/Verifying 阶段取消；C 取消后 ⌘Q 立即退出；D 删除第 1 项时按 ⌘Q（连按也应无害），要等第 1 项删完后自动退出，第 2 项不动 | $W/gui | 每个被选中的目录要么**完全删掉**，要么**清单不变**；中间状态一律判 FAIL；keep/ 不动；app 最后必须自己退出 |
| 8 | 先 detach → 解锁（按固定顺序）→ 只删 $W | $W | 仍有挂载时拒绝删除 |

说明：schg、sappnd、SF_* 需要 root 才能设置，脚本不做，由单元测试覆盖。ACL 的 C 桥接在 Linux 上编译不了，第 6c 步（acl / aclch / aclinh）是唯一的实机验证。第 7D 步是验证 `.terminateLater` 一定会 reply 的唯一实机测试：app 如果卡着不退，说明 reply 没发出，记为 FAIL。

## R7 note: 7D (P2)

R6 found that Cmd-Q during a delete beeped and showed no "Quitting…" (the quit itself worked).
This is fixed: the sheet keeps "Quitting…", the sheet window handles Cmd-Q itself, and Quit is
always enabled. Step 7D now also asks "every Cmd-Q silent and 'Quitting…' within ~1 s? [y/n]".
The rest of the script is unchanged: no sudo, writes only `/tmp/diskrings-accept` and
`<project>/build`, undo with `rm -rf /tmp/diskrings-accept` and `./build.sh clean`. Details are
in the README section "R6 real-Mac finding 7D".
