---
doc_id: CD-HISTORY-BUILD-081-GHOST-RIDE-001
title: Build 81 Ghost Ride
type: history
status: draft
canonical: false
domain: build-081-ghost-ride
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
  - 79
  - 80
  - 81
supersedes: []
superseded_by:
---

# Build 81 — Ghost Ride

## 范围

Build 81 在既有 GPX、PTRideReplay、Ride DNA、Road Surface 和 XP400 Digital Twin 上增加只读 Ghost Ride。当前骑行与同一车辆的历史骑行先进行路线归一化和空间重叠确认，再按累计路线距离映射历史遥测；没有足够重叠时隐藏 Ghost，不显示伪造的历史位置，也不改变导航路线。

Build 81 不新增 BLE、ELM327、YMOBD、GPS、Motion、导航或 OBD 传输层；`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持冻结。营销版本仍为 `2.0.8`，主 App、Widget 和 Watch 的 Build 为 `81`。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 安全边界 |
| --- | --- | --- | --- |
| B81-01 route normalize | ✅ | 对既有 Replay 样本按时间排序、过滤非法坐标并计算累计 WGS84 距离 | 不修改原始 GPX 或 PTTripReport |
| B81-02 overlap | ✅ | 使用粗粒度空间索引和距离容差寻找两条路线的有效重叠区 | 单点接近或短重叠不会启用 Ghost |
| B81-03 progress index | ✅ | 对路线距离和历史样本建立二分查找/空间索引 | 长轨迹不使用全量 O(n²) 逐帧匹配 |
| B81-04 interpolation | ✅ | 对时间、路线距离、速度、RPM、G 值进行确定性插值 | 仅在已确认的重叠区插值 |
| B81-05 replay compare | ✅ | 在既有 PTRideReplayViewController 增加历史路线、地图位置和差值对比 | 当前回放缺历史文件时仍可独立播放 |
| B81-06 twin compare | ✅ | 复用 XP400 Twin 2D renderer 并排显示当前/历史状态 | 两侧都标记为 Replay/Synthetic，不冒充实车 |
| B81-07 live ghost | ✅ | Dashboard 读取统一遥测和位置快照，显示进度、时间差、速度差、历史 RPM 和历史路况 | 仅展示，不发送指令、不改变导航 |
| B81-08 reroute fallback | ✅ | 偏离路线或重叠不足时隐藏 Ghost，等待重新进入 | 不自动重算、不注入导航、不接触车辆控制 |
| B81-09 UI safety | ✅ | 同车历史筛选、可访问性提示、低干扰状态和明确不可用文案 | 禁止用过期历史点继续显示 |
| B81-10 real-route tests | ✅ | 新增同路线、异路线、插值、实时偏航回退和归一化测试 | 真实 XP400 路线、前后台和性能仍需现场验收 |

## 数据流

~~~text
PTTripReport + existing GPX
           │
           ▼
   PTRideReplaySession
           │
           ▼
  PTRideGhostRouteNormalizer
           │
     ┌─────┴─────┐
     ▼           ▼
Overlap      Progress index
     │           │
     └─────┬─────┘
           ▼
  PTRideGhostSession / LiveResolver
       ┌───┼─────────────┐
       ▼   ▼             ▼
   Replay Twin       Dashboard
   Compare Compare   Live Ghost
~~~

## 可信度边界

- Ghost 只表达“当前路线在已确认重叠区相对于历史路线的差值”，不是实时导航建议。
- 历史数据保留 Replay/Synthetic 语义；Twin 对比不会把历史值标记为 BLE、OBD 或真实 ECU 数据。
- 偏离重叠区后返回安全状态 `hideUntilRejoin`，不使用最后一个历史点填充画面。
- Live Ghost 默认取同一已选车辆最近的已完成 GPX；没有车辆绑定时不跨车混用。

## 验收门

代码门已完成：

- `PTRideGhost.swift`、Replay 对比、分析页入口、Dashboard Live Ghost 和 Build81 测试已加入工程；
- 复用既有 GPX、Replay、XP400 Twin 和统一 Telemetry；
- `git diff --check`、纯 Swift 语法检查和产品 Debug 工程编译需通过；
- 三个稳定 BLE/OBD 核心文件不应发生变化。

现场门仍待完成：

- 使用同一路线、部分重叠、反向路线和完全不同路线的真实 GPX 验证；
- XP400/XP400 GT 实车前台、后台、断连、低 GPS 精度和无历史路线场景；
- 观察 Live Ghost 偏航后是否隐藏、重新进入后是否恢复，且导航路线完全不变；
- 用 Instruments 验证长 GPX、重复路线、地图叠加和 Twin 对比的 CPU/内存/帧率；
- 完成 Release/TestFlight 和多语言/VoiceOver 验收后再将记录提升为 stable。

## 回滚

- 移除分析页 Ghost 入口和 Dashboard Live Ghost 状态层即可关闭 Build81 展示；既有 Replay、DNA、导航和车辆连接不受影响。
- 不需要迁移或删除已有 GPX、PTTripReport 或 CrazyTrace 文件。
- 不修改 BLE、ELM327、YMOBD、OBD 或导航核心来处理 Ghost 对比问题。

---
