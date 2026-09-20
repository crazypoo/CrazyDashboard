---
doc_id: CD-HISTORY-BUILD-082-DYNAMIC-DASHBOARD-001
title: Build 82 Dynamic Dashboard
type: history
status: draft
canonical: false
domain: build-082-dynamic-dashboard
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
supersedes: []
superseded_by:
---

# Build 82 — Dynamic Dashboard

## 范围

Build 82 在既有统一遥测、导航会话、音乐卡片、Vehicle Health、Road Surface、Ghost Ride 和 XP400 Digital Twin 之上增加动态 Dashboard 上下文层。它把停车、骑行、导航、接近转向、媒体变化、车辆警告和连接降级归纳成可测试的展示意图，再按 `Safety > Navigation > Vehicle > Media > Decoration` 输出模块策略。

本轮没有新增车辆传输层、连接层、轮询层或诊断协议。`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持冻结；ELM327 仍是 OBD 底层，YMOBD 仍是 ELM327 扩展。营销版本保持 `2.0.8`，主 App、Widget 和 Watch 的 Build 为 `82`。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B82-01 Context | ✅ | 新增只读、`Sendable` 的 `PTDashboardContext`、模块和输入快照模型 | 上下文是展示意图，不替代车辆或导航状态机 |
| B82-02 Engine | ✅ | 新增 `PTDashboardContextEngine`，消费统一遥测、连接、导航和媒体通知 | Engine 不直接访问 BLE、ELM327 或 YMOBD |
| B82-03 Priority Resolver | ✅ | 以固定优先级解析主上下文和所有模块展示策略 | Warning 永远优先于 Navigation、Vehicle 和 Media |
| B82-04 Module Protocol | ✅ | 新增 `PTDashboardModuleView`，让 UI 模块消费确定性策略 | 模块不能通过协议发送车辆命令 |
| B82-05 Twin module | ✅ | 2D/3D XP400 Twin 接入同一模块策略；导航/警告时收缩或强调 | 不改变 Twin 数据源和 2D/3D 渲染器的车辆快照语义 |
| B82-06 Existing cards | ✅ | 现有速度、音乐和地图卡片复用上下文，调整透明度、可见性和交互 | 不重建原有卡片，不复制遥测或音乐数据源 |
| B82-07 Overlay | ✅ | 增加低干扰上下文覆盖层，展示导航、转向、警告、连接和媒体变化 | 只读展示；不覆盖事故警报和系统级安全提示 |
| B82-08 Warning priority | ✅ | ABS/倾倒警报进入 Warning 主上下文，压低媒体与 Ghost 展示 | Warning 不会触发任何车辆写入操作 |
| B82-09 Throttling | ✅ | Engine 以 20 Hz 为状态发布上限，忽略仅时间变化的重绘 | 上限是 UI 状态预算，不改变底层遥测采样频率 |
| B82-10 Regression | ✅ | 增加 warning/navigation/twin/health/media/speed 的纯 Resolver 回归测试 | XCTest 编译与真机视觉/性能验证仍需分别完成 |

## 数据流

~~~text
PTUnifiedVehicleTelemetrySnapshot ─┐
PTVehicleSnapshot / connection ────┼──> PTDashboardContextEngine
PTNavigationGuidanceSnapshot ──────┤             │
MPMusicPlayer notification ────────┘             ▼
                                      PTDashboardContextResolver
                                      Safety > Navigation > Vehicle
                                                 │
                      ┌──────────────────────────┼─────────────────────────┐
                      ▼                          ▼                         ▼
                Dashboard cards             XP400 Twin 2D/3D          Context overlay
~~~

## 可信度与安全边界

- Engine 只消费已有的不可变遥测快照和系统通知，不建立第二套 BLE、OBD、导航或音乐管线。
- `warning` 只由已有倾倒状态或 ABS 警告快照触发；缺少数据不会被推断成车辆故障。
- `connectionDegraded` 只在骑行或导航期间、且连接待定/无有效车辆传输时出现；停车状态不会因为暂时未连接而制造驾驶警报。
- `mediaChanged` 是短暂的展示提示，不会抢占骑行、导航或安全告警。
- 20 Hz 节流只限制 UI 上下文发布，不会暂停连接、轮询、GPS、Motion 或 OBD 采集。
- Twin、地图、音乐和 Ghost 都保持只读；本轮不开放 ECU 写入、仪表配置、SecurityAccess、固件刷写或未知指令。

## 验收门

代码门已完成：

- `PTDashboardContext.swift`、`PTDashboardContextEngine.swift` 和覆盖层已加入主 App 工程；
- 主仪表与 `PTVehicleTwinViewController` 共享同一个上下文 Engine，不重复接入传输层；
- `PTDashboardContextBuild82Tests.swift` 已加入 `PTSpeedTests`；
- `Global/Localizable.xcstrings` 已补齐九种语言的上下文文案；
- `PTSpeed` workspace Debug `build` 与 `build-for-testing` 已通过；
- Watch target 使用正确的 `watchsimulator` SDK 可独立编译，Widget target 可独立编译；
- `git diff --check`、工程列表、JSON 语法和核心文件哈希检查通过；
- 三个稳定 BLE/OBD 核心文件保持零字节变化。

现场门仍待完成：

- 真实 XP400/XP400 GT 在停车、骑行、导航、接近转向、ABS/倾倒警告和断连期间逐项验证主上下文；
- 检查 Dashboard 与 Twin 同时出现/退出时没有重复订阅、残留覆盖层或状态闪烁；
- 用 Instruments 验证 20 Hz 遥测、地图、音乐和 Twin 同时更新时的 CPU、内存、帧率、能耗和 thermal；
- 验证前后台、CarPlay、Mock/Replay、VoiceOver、九种语言、窄屏和 Reduce Motion；
- 用 Release/TestFlight 包复核 Watch、Widget、Live Activity 和主 App 的安装/嵌入关系。

## 回滚

- 移除 `PTDashboardContextEngine` 的 Dashboard/Twin 接入和覆盖层即可关闭 Build82 展示增强；已有统一遥测、导航、音乐、Twin、Health、Road Surface 和 Ghost 功能继续工作。
- 不需要迁移或删除任何车辆、行程、Replay、CrazyTrace、iCloud 或协议证据数据。
- 不修改 BLE、ELM327、YMOBD、OBD 或导航核心来处理 Dashboard 展示问题。
