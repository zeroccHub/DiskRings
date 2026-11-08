# 首页浅 / 深色语义色简表

> 给源码助理修主题切换用。主来源：视觉设计说明 §2.2 / §3.2。
> 日期：2026-11-07。括号内为实现建议。

## 核心表面与文字

| Token | 浅色 | 深色 | 用途 | 实现建议 |
|---|---|---|---|---|
| `windowBg` | `#F5F5F7` | `#1C1C1E` | 窗口底 | `NSColor.windowBackgroundColor` |
| `surface`（卡片底） | `#FFFFFF` | `#2C2C2E` | 磁盘卡片、图表底、说明面板 | 自定义动态色；旭日图对比度按它算 |
| `surfaceSecondary` | `#F0F0F2` | `#3A3A3C` | 次级按钮、搜索框 | `controlBackgroundColor` 或自定义 |
| `sidebarBg` | `#ECECEF` | `#252527` | 侧边栏示意 | 实现用 `NSVisualEffectView`（`.sidebar`） |
| `separator` | `#D9D9DE` | `#48484A` | 分隔线、卡片描边 | `NSColor.separatorColor` |
| `textPrimary` | `#1D1D1F` | `#F5F5F7` | 主文字 | `NSColor.labelColor` |
| `textSecondary` | `#636366` | `#AEAEB2` | 次文字（11pt 也要 ≥4.5:1） | 自定义；**不要**只用 `secondaryLabelColor`（浅色白底约 3.9:1） |

## 品牌与状态

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `accent` | `#0B7A6E` | `#3DD6BE` | 主按钮、选中、进度、链接 |
| `accentContainer` | `#DDF3EF` | `#123F3A` | 选中行底、安全徽章底 |
| `onAccent` | `#FFFFFF` | `#0B1F1C` | 主按钮上的字（浅 5.22:1 / 深 9.42:1） |
| `safe` | `#1F7A4D` | `#4CD38A` | 「✓ 可以删除」（必须配文字） |
| `caution` | `#A15C00` | `#FFB547` | 「⚠ 谨慎」 |
| `protected` | `#6E6E73` | `#AEAEB2` | 「🔒 受保护」 |
| `freeTrack` | `#E8E8ED` | `#3A3A3C` | 可用空间轨道 |

## FDA 完全磁盘访问权限底条

首页 / 空状态若展示「需要完全磁盘访问权限」提示条，建议：

| Token | 浅色 | 深色 | 说明 |
|---|---|---|---|
| `fda.bg` | `#DDF3EF` | `#123F3A` | 与 `accentContainer` 同色，品牌弱提示，不是警告 |
| `fda.border` | `#0B7A6E` @ 28% | `#3DD6BE` @ 35% | 1pt 顶边或左边条即可 |
| `fda.title` | `#1D1D1F` | `#F5F5F7` | 「需要完全磁盘访问权限」 |
| `fda.body` | `#636366` | `#AEAEB2` | 一句说明 + 链到系统设置 |
| `fda.action` | `#0B7A6E` | `#3DD6BE` | 「打开系统设置」链接 / 按钮描边 |

若权限缺失导致扫描结果明显偏少，可升为谨慎态：

| Token | 浅色 | 深色 |
|---|---|---|
| `fda.warn.bg` | `#FFF6E5` | `#3D3415` |
| `fda.warn.text` | `#A15C00` | `#FFB547` |

不要用破坏性红（`danger`）表达 FDA——那不是数据丢失风险。

## 与 simplify-v2 的差异（切换主题时注意）

| 项 | 视觉稿 / 本表 | simplify-v2 已定稿 |
|---|---|---|
| 主按钮 accent | `#0B7A6E` / `#3DD6BE` | `#0064D2` / `#1A6FD6`（白字对比度更好） |
| 窗口底近似 | `#F5F5F7` / `#1C1C1E` | `#F2F2F2` / `#252527` |
| 分隔线 | `#D9D9DE` / `#48484A` | `#D8D8DA` / `#3A3A3C` |

修主题切换时：
1. 背景 / 文字 / 分隔线继续跟系统语义色走，避免两套 hex 写死导致闪烁。
2. 品牌强调色在工程里只保留**一套** Asset / `NSColor(name:dynamicProvider:)`；若已落地蓝，首页 FDA 条的 `fda.action` 可跟蓝；若改回深青，整表用本文件。
3. 机器可读：`Resources/DesignTokens.json`。

## 磁盘卡片（首页）最小集

| 元素 | 浅色 | 深色 |
|---|---|---|
| 卡片底 | `surface` `#FFFFFF` | `#2C2C2E` |
| 卡片描边 | `separator` | `separator` |
| 卷名 | `textPrimary` | `textPrimary` |
| 容量说明 | `textSecondary` | `textSecondary` |
| 容量条填充 | `accent` | `accent` |
| 容量条轨道 | `freeTrack` | `freeTrack` |
