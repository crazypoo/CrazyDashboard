---
doc_id: CD-HISTORY-BUILD-083-MUSIC-DASHBOARD-THEME-001
title: Build 83 Music Dashboard Theme
type: history
status: draft
canonical: false
domain: build-083-music-dashboard-theme
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 78
  - 79
  - 80
  - 81
  - 82
  - 83
supersedes: []
superseded_by:
---

# Build 83 — Music × Dashboard Theme

## 范围

Build 83 将当前 Now Playing 专辑封面转换为受约束的 Dashboard 装饰主题。数据流为：

```text
Now Playing artwork
        ↓
bounded color extraction
        ↓
contrast-checked theme tokens
        ↓
Dashboard / XP400 Twin decoration
```

本轮只改变背景、环境光、非语义光晕和装饰卡片渐变。TCS、ABS、警告、车速可读性、导航关键 UI 和车辆状态颜色不由封面主题决定。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B83-01 Theme Token | ✅ | 新增 `PTDashboardThemeColor`、`PTDashboardThemeTokens` 和 `PTDashboardThemeResolver`；主题值为 `Sendable` 纯数据 | 只表达装饰颜色，不表达车辆语义 |
| B83-02 Artwork Color Extractor | ✅ | 新增基于 ImageIO/CoreGraphics 的低分辨率主色/强调色提取 | 仅处理已有 artwork Data，不新增媒体传输 |
| B83-03 Cache | ✅ | 新增有界 `NSCache`，按 Track ID 与 artwork 内容缓存调色板 | 最多保留 24 个小调色板，不持有原图 |
| B83-04 Contrast Validator | ✅ | 对背景做暗化和文本对比度选择，目标白色文本对比度不低于 4.5 | 是展示层可读性门，不是车辆安全认证 |
| B83-05 Dashboard Adapter | ✅ | 主 Dashboard 背景与音乐卡片消费同一份主题令牌 | 速度、地图、导航和警告的语义颜色保持原逻辑 |
| B83-06 Twin Theme Adapter | ✅ | 2D/3D Twin 应用背景、环境光、卡片渐变和非语义 glow | 不改变 TCS、ABS、灯光、RPM 状态色或车辆快照 |
| B83-07 Safety Mode | ✅ | `warning`/`maneuver` 强制默认安全主题；骑行、导航和连接降级降低装饰透明度 | 安全上下文优先于音乐主题 |
| B83-08 Settings | ✅ | 新增 Dashboard artwork theme 开关，默认开启并支持现有本地化资源 | 开关只影响装饰层 |
| B83-09 Permission Fallback | ✅ | 无播放项、封面缺失、不可解码、权限/资料库不可用时回退默认主题 | 不伪造封面颜色，不阻塞 Dashboard |
| B83-10 Performance | ✅ | 24px 采样、后台提取、缓存命中和只在 artwork/context 变化时发布 | 未完成真机 Instruments/thermal 证据 |

## 代码与数据边界

- `PTDashboardThemeEngine` 是主线程状态协调器，颜色提取只接收 `Data`，在后台任务执行，再回主线程发布令牌。
- 主题引擎只观察既有 `PTDashboardContextEngine` 和 Now Playing artwork；不访问 BLE、ELM327、YMOBD、OBD、GPS 或车辆写入 API。
- `PTDashboardThemeResolver` 在 warning 和 maneuver 上下文使用安全回退；navigating、riding 和 connection degraded 只降低装饰干扰。
- iOS Widget、Watch、Live Activity、iCloud 和车辆通信数据没有新增主题字段或持久化迁移。
- `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持零字节变化；ELM327/YMOBD 连接步骤、握手、轮询和 fallback 未改。

## 测试与构建证据

已完成：

- `PTDashboardThemeBuild83Tests.swift` 接入 `PTSpeedTests`，覆盖 artwork 非默认主题、安全回退、关闭开关、导航低干扰和 PNG 提取。
- PTSpeed workspace Debug generic iOS Simulator `build`：`BUILD SUCCEEDED`。
- PTSpeed workspace Debug generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- 三个稳定 BLE/OBD 核心文件 SHA-256 保持基线：
  - `PTBluetoothManager.swift`: `841abfbab70f6c199c3130b68c8f55f42104684e6f6ea39a11ad3215c7b676e4`
  - `PTHiddenOBDConnector.swift`: `21a3657de6c7bfd4ac4e40883fc14ec45aabed168376629e15a2e2573a4632d1`
  - `PTOBDCommand.swift`: `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66`

尚未替代现场验收的项目：

- 真实 Apple Music/系统媒体权限、无 artwork 和不同封面尺寸；
- iPhone 真机上主 Dashboard、2D/3D Twin 的长时间帧率、内存、Energy 和 thermal；
- warning、ABS/TCS、导航接近转向时主题回退和语义颜色不变；
- Reduce Motion、VoiceOver、九种语言、窄屏、CarPlay、前后台和 Release/TestFlight 包。

## 回滚

- 关闭设置中的 Dashboard artwork theme 即可回到默认装饰主题。
- 若需代码回滚，只移除 `PTDashboardThemeEngine` 的 Dashboard/Twin 接入和新增三份主题源码，不需要迁移或删除车辆、行程、媒体、iCloud 或协议证据数据。
- 不修改稳定 BLE/OBD 核心来处理主题问题。
