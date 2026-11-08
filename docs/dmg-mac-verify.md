# DiskRings DMG — Mac 验收命令清单（测试助理）

> 对齐 PRD `diskrings-specs/dmg-distribution-prd.md` §6。  
> **默认在干净用户视角验证**（用下载的 DMG，不要直接开开发目录里的 `build/DiskRings.app`）。  
> 每条命令旁注明：作用 / 路径 / sudo / 风险 / 恢复。  
> **涉及钥匙串、Apple ID、系统设置变更、sudo 的步骤必须先获明确授权。**  
> 本文件只供人在 Mac 上照跑；自动化助手不要通过 machineId 代执行。

版本文件名以实际产物为准，例如 `DiskRings-0.1.0-adhoc-arm64.dmg`。

---

## 0. 前置（只读）

| # | 命令 / 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 0.1 | `sw_vers` | 确认 macOS 版本（含 Sequoia） | 无写 | 否 | 无 | – |
| 0.2 | `uname -m` | 确认本机 arch（arm64 / x86_64） | 无写 | 否 | 无 | – |
| 0.3 | `ls -la ~/Downloads/DiskRings-*.dmg`（私发拷贝路径） | 确认 DMG 已下载 | 只读 Downloads | 否 | 无 | – |
| 0.4 | `shasum -a 256 ~/Downloads/DiskRings-….dmg` 与附带的 `SHA256SUMS` 比对（私发/网盘，非公开 Release） | 校验下载完整 | 只读 | 否 | 无 | 重新下载 |

---

## 1. 打包产物（§6.1）

| # | 命令 / 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 1.1 | Finder 双击 DMG，或 `hdiutil attach ~/Downloads/DiskRings-….dmg` | 挂载卷 `DiskRings` | 挂载点由系统决定（常见 `/Volumes/DiskRings`） | 否 | 低：多一个挂载卷 | `hdiutil detach /Volumes/DiskRings` |
| 1.2 | `ls -la /Volumes/DiskRings` | 应见 `DiskRings.app`、`Applications`；ad-hoc 另有 `安装说明.txt` | 只读挂载卷 | 否 | 无 | – |
| 1.3 | `lipo -archs /Volumes/DiskRings/DiskRings.app/Contents/MacOS/DiskRings` | 核对宣称的 arm64 / universal | 只读 | 否 | 无 | – |
| 1.4 | `codesign -dv --verbose=2 /Volumes/DiskRings/DiskRings.app 2>&1 \| head` | 看签名身份（adhoc = `Signature=adhoc`；公证版应有 Developer ID） | 只读 | 否 | 无 | – |
| 1.5 | 公证版：`xcrun stapler validate /Volumes/DiskRings/DiskRings.app` | 确认 staple | 只读 | 否 | 无 | – |
| 1.6 | 确认文件名：公证无 `-adhoc`；降级含 `-adhoc`；仅 arm64 含 `-arm64` | 命名验收 | – | 否 | 无 | – |
| 1.7 | `hdiutil detach /Volumes/DiskRings` | 推出卷（装完或检查完） | 卸载挂载点 | 否 | 低：未保存的 Finder 窗口关闭 | 再 attach |

---

## 2. 安装（§6.2）

| # | 命令 / 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 2.1 | 在 DMG 窗口把 App **拖到** `Applications` 别名 | 安装到 `/Applications/DiskRings.app`（或用户「应用程序」） | 写入 `/Applications` 或 `~/Applications` | 通常否（系统 Applications 可能要管理员密码） | 低：覆盖同名 App | 废纸篓删除该 App |
| 2.2 | `ls -la /Applications/DiskRings.app` | 确认已复制 | 只读 | 否 | 无 | – |
| 2.3 | 卸载：把 `/Applications/DiskRings.app` 移到废纸篓并清空（或 `rm -rf` **仅**该路径） | 卸载冒烟 | **仅**该 `.app` | 否（rm 本用户可写时） | 中：误删路径会丢 App | Time Machine / 重装 DMG；**禁止**对 `/Applications` 整目录 rm |
| 2.4 | 记录：本 MVP 无登录项/helper；偏好若有则记下 `~/Library/Preferences` 下相关文件（可保留） | 残留检查 | 只读 Library | 否 | 无 | – |

---

## 3. 打开与 Gatekeeper（§6.3）

### 3.A 公证版

| # | 命令 / 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 3A.1 | Finder 双击 `/Applications/DiskRings.app` | 应进入主界面（可有一次「来自互联网」确认） | 启动 App | 否 | 低 | 强制退出 |
| 3A.2 | （授权后）`spctl --assess --verbose /Applications/DiskRings.app` | Gatekeeper 评估 | 只读评估 | 否 | 无 | – |

### 3.B ad-hoc 版（预期被拦）

| # | 命令 / 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 3B.1 | Finder 双击 App | **预期**拦截「无法验证开发者」 | 启动被拒 | 否 | 无 | – |
| 3B.2 | **系统设置 → 隐私与安全性 → 仍要打开**（按 `安装说明.txt`） | Sequoia 官方绕过路径 | 系统设置（用户确认） | 密码提示 | 低：仅允许这一次打开该 App | 可在同样面板移除/不再允许 |
| 3B.3 | （可选进阶，**无 sudo**）`xattr -dr com.apple.quarantine /Applications/DiskRings.app` | 清除下载隔离标记 | **仅**该 App | 否 | 低：去掉隔离后系统少一次提示 | 重新从 DMG 复制即可恢复隔离 |
| 3B.4 | 再次打开，应见首页磁盘卡片 | 功能入口 | – | 否 | 低 | 强制退出 |

**禁止：** `csrutil disable`、`spctl --master-disable`、任何「关闭 SIP / 全局关闭 Gatekeeper」指引。

---

## 4. 功能冒烟（§6.4）

| # | 操作 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 4.1 | 看界面关键文案是否为简体中文 | 本地化 | – | 否 | 无 | – |
| 4.2 | 系统外观浅色/深色切换，回首页看卡片与底栏对比度 | 主题 | – | 否 | 无 | 切回原外观 |
| 4.3 | 选一本地卷或「扫描文件夹」扫用户目录，等旭日图 | 扫描冒烟 | 读用户选择的目录 | 否 | 低：只读扫描 | 点停止 |
| 4.4 | 删除区/底栏入口可点（已知菜单缺陷记 bug，不挡「能开能扫」） | 删除篮入口 | – | 否 | 无（本步不真删） | – |

完全磁盘访问：仅当测系统目录时，在 **系统设置 → 隐私与安全性 → 完全磁盘访问权限** 添加 App（GUI，按需授权）。撤销：同一列表移除。

---

## 5. 负面验收（§6.5）

| # | 检查 | 期望 |
|---|---|---|
| 5.1 | GitHub Release / 网盘说明 / README「普通用户」节 | **没有**「请运行 build.sh / 安装 Xcode」作为终端用户步骤 |
| 5.2 | `安装说明.txt`、README、本清单 | **没有**关闭 SIP / 全局关闭 Gatekeeper |

---

## 6. 开发者本机打 DMG（非终端用户；需工具链）

仅在 Mac 上打包时使用：

| # | 命令 | 作用 | 路径 | sudo | 风险 | 恢复 |
|---|---|---|---|---|---|---|
| 6.1 | `cd ~/Downloads/DiskRings && ./scripts/package_dmg.sh --dry-run --adhoc --universal` | 检查脚本/文档/命名 | 只读 | 否 | 无 | – |
| 6.2 | `./scripts/package_dmg.sh --adhoc --arm64` | 产出 `dist/DiskRings-*-adhoc-arm64.dmg` | 写 `./build`、`./dist` | 否 | 低：覆盖同名 dist | 删 `dist/` 或换文件名 |
| 6.3 | `./build.sh dmg --adhoc --universal` | 同上（转发到 package_dmg.sh） | 同上 | 否 | 同上 | 同上 |
| 6.4 | `--notarize`（**另需授权**） | Developer ID + notarytool；需已设 `IDENTITY`、`NOTARY_*` | 写 build/dist；网络提交 Apple | 否（但触碰已配置的公证凭证） | 中：误用身份/上传二进制 | 用 `--adhoc` 降级；撤销凭证属账号侧 |

脚本**不会**替你打开钥匙串或登录 Apple ID。
