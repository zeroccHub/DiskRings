# DiskRings 0.1.0 ad-hoc arm64 DMG — 本里程碑验收（本机自跑）

对齐：`diskrings-specs/dmg-distribution-prd.md` §6 + `docs/dmg-mac-verify.md`。  
范围：私发 / ad-hoc / arm64；**不上**公开 GitHub Release；**不**公证。  
约束：不关 SIP、不全局关 Gatekeeper；不经 machineId 代跑；系统设置步骤须你授权后自己点。

预期产物（任选其一路径，以实际为准）：
- `~/Downloads/DiskRings/dist/DiskRings-0.1.0-adhoc-arm64.dmg` + 同目录 `SHA256SUMS`
- 或拷贝后的 `~/Downloads/DiskRings-0.1.0-adhoc-arm64.dmg` + `~/Downloads/DiskRings-0.1.0-adhoc-arm64.SHA256SUMS`

下面把 `DMG` 换成你的实际路径。每条旁注：作用 / 路径 / sudo / 风险 / 恢复。

---

## A. 打包前（可选，有源码树时）

```bash
# 作用：确认工具链；路径：只读；sudo：否；风险：无
xcode-select -p && xcrun -f swift && sw_vers && uname -m

cd ~/Downloads/DiskRings
# 作用：命名/文档/禁止关安全指引自检；写：无；sudo：否
./scripts/package_dmg.sh --dry-run --adhoc --arm64

# 作用：打真实 DMG；写：./build ./dist；sudo：否；风险：低，覆盖同名 dist；恢复：删 dist/
./scripts/package_dmg.sh --adhoc --arm64
```

---

## B. §6.1 打包产物（干净用户视角）

```bash
DMG=~/Downloads/DiskRings/dist/DiskRings-0.1.0-adhoc-arm64.dmg
SUMS=~/Downloads/DiskRings/dist/SHA256SUMS
# 若已拷到 Downloads：
# DMG=~/Downloads/DiskRings-0.1.0-adhoc-arm64.dmg
# SUMS=~/Downloads/DiskRings-0.1.0-adhoc-arm64.SHA256SUMS

# 0.4 校验 — 只读；失败则重新拷贝/重打
cd "$(dirname "$DMG")"
shasum -a 256 -c SHA256SUMS 2>/dev/null \
  || shasum -a 256 "$(basename "$DMG")" | tee /dev/stderr | grep -F "$(grep "$(basename "$DMG")" "$SUMS" | awk '{print $1}')"

# 1.1 挂载 — 挂载点常见 /Volumes/DiskRings；恢复：hdiutil detach
hdiutil attach "$DMG"
ls -la /Volumes/DiskRings
# 期望：DiskRings.app、Applications（或别名）、安装说明.txt

# 1.3 / 1.4
lipo -archs /Volumes/DiskRings/DiskRings.app/Contents/MacOS/DiskRings
# 期望：arm64

codesign -dv --verbose=2 /Volumes/DiskRings/DiskRings.app 2>&1 | head -20
# 期望：Signature=adhoc（或等价 ad-hoc 表述）；不要出现 Developer ID

# 1.6 文件名含 -adhoc 与 -arm64
basename "$DMG"

hdiutil detach /Volumes/DiskRings
```

## C. §6.2 安装

1. 再挂载 DMG，Finder 里把 App **拖到** Applications 别名。  
   - 路径：写入 `/Applications/DiskRings.app`（或 `~/Applications`）  
   - sudo：通常否；系统 Applications 可能要管理员密码  
   - 风险：覆盖同名 App；恢复：废纸篓删除该 App  
2. `ls -la /Applications/DiskRings.app`  
3. 本步不要求立刻卸载；整轮结束再移到废纸篓（**仅**该 `.app`，禁止 `rm -rf /Applications`）。

## D. §6.3 Gatekeeper（ad-hoc，预期被拦）— 需你授权再改系统设置

1. Finder 双击 `/Applications/DiskRings.app` → **预期**「无法验证开发者」。  
2. **系统设置 → 隐私与安全性 → 仍要打开**（按盘内「安装说明.txt」）→ 再打开应进首页。  
3. （可选，无 sudo）仅当仍打不开：  
   `xattr -dr com.apple.quarantine /Applications/DiskRings.app`  
   - 只清该 App 隔离标记；恢复：从 DMG 重新复制。  
4. **禁止：** `csrutil disable`、`spctl --master-disable`、关 SIP / 全局关 Gatekeeper。

## E. §6.4 功能冒烟（本步不真删用户文件）

- [ ] 关键文案为简体中文  
- [ ] 浅色/深色切换后卡片与底栏可读  
- [ ] 选一本地卷或「扫描文件夹」扫用户目录，旭日图有结果；可点停止  
- [ ] 删除区/底栏入口可点（本步不真删）

## F. §6.5 负面（静态，可在 Linux/Mac 对照）

- [ ] 普通用户文档不要求 `build.sh` / 装 Xcode  
- [ ] `安装说明.txt` / README / 本清单无「关 SIP / 全局关 Gatekeeper」作为安装步骤（禁止语除外）

## G. 贴回测试助理的最小结果模板

```
macOS: (sw_vers)
arch: (uname -m)
DMG path:
shasum OK?: 
lipo:
codesign (Signature= 行):
DMG 内容 (ls):
Gatekeeper: 首次双击被拦? / 「仍要打开」后进首页?
冒烟: 中文? 主题? 扫描旭日图? 删除入口?
负面文档: OK / 问题=
其他异常:
```

打完 DMG 或跑完后把上面模板贴回即可。
