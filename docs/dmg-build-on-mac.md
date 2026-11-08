# 在 Mac 上打 DiskRings ad-hoc arm64 DMG（本机自跑）

对齐拍板：ad-hoc + arm64 + 私发 + 纯色背景。本机**不要**动钥匙串里的 Developer ID；本里程碑不公证。

## 前置

- 项目在 `~/Downloads/DiskRings`（若只有 box 上的 zip：先解压覆盖到该目录）。
- 已装 Xcode CLT（`xcode-select -p` 有输出）。

## 打包命令（无 sudo、不碰钥匙串）

```bash
cd ~/Downloads/DiskRings
./scripts/package_dmg.sh --adhoc --arm64
```

| 项 | 说明 |
|---|---|
| 作用 | release 编 arm64 → ad-hoc 签名 → 打 `DiskRings-0.1.0-adhoc-arm64.dmg`（含「安装说明.txt」）+ `SHA256SUMS` |
| 路径 | 读当前仓库；写 `dist/DiskRings-0.1.0-adhoc-arm64.dmg`、`dist/SHA256SUMS` |
| sudo | 否 |
| 风险 | 低：本机编译与 ad-hoc codesign；不访问网络、不动钥匙串 |
| 恢复 | 删除 `dist/` 下产物即可 |

可选：把 DMG 拷到下载目录方便私发：

```bash
cp -f ~/Downloads/DiskRings/dist/DiskRings-0.1.0-adhoc-arm64.dmg ~/Downloads/
cp -f ~/Downloads/DiskRings/dist/SHA256SUMS ~/Downloads/DiskRings-0.1.0-adhoc-arm64.SHA256SUMS
```

| 项 | 说明 |
|---|---|
| 作用 | 复制产物到 `~/Downloads` |
| 路径 | 只复制上述两个文件 |
| sudo | 否 |
| 风险 | 无 |
| 恢复 | 删 Downloads 里这两个文件 |

## 预期产物

- `~/Downloads/DiskRings/dist/DiskRings-0.1.0-adhoc-arm64.dmg`
- 同目录 `SHA256SUMS`
- 版本：`0.1.0`（Info.plist）
- 签名：ad-hoc（Gatekeeper 会拦，按盘内安装说明「仍要打开」）
- 架构：arm64 only

## 已知限制

- Linux box **无法**生成真实 DMG（无 hdiutil/AppKit）。
- 未公证；仅 Apple Silicon。
- DMG 背景为纯色占位，UI 设计师出图后再换。
- 不上公开 GitHub Release。
