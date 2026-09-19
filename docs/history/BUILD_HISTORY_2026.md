---
doc_id: CD-HISTORY-2026-001
title: Build History 2026
type: history
status: stable
canonical: true
domain: build-history-2026
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-20
related_builds:
  - 57
  - 61
  - 62
  - 63
  - 64
  - 65
  - 66
  - 67
  - 68
  - 69
  - 74
  - 76
  - 77
supersedes: []
superseded_by:
---

# 2026 Build 历史

本文件是已完成或已收口 Build 的年度索引。每条记录把代码证据和真实设备/车辆缺口分开；当前未完成事项移到 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。

## Build 57 — OBD Architecture 2.0 V2

完成 ELM327 Session、命令队列、Vendor Extension、YMOBD 能力识别、总线租约、Jieli SDK bridge、统一会话追踪和兼容 facade。稳定的 ELM327 核心文件未改；主 App/Tests 的完整构建和真实 OTA 仍需按设备环境验证。详细状态见已归档的 [Build 57 状态记录](../archive/superseded/CrazyDashboard_Build57_Implementation_Status.md)。

## Build 61 — Architecture Consolidation

完成统一遥测 Bridge/Consumer/Projection、Instruments Provider、Evidence/CAN/Passport 边界和兼容编解码。BLE/OBD 核心继续冻结；模拟器、Pods、签名、真机和实车证据按当时环境分别记录。原迁移矩阵已归档，当前架构见 [`../architecture/TELEMETRY_ARCHITECTURE.md`](../architecture/TELEMETRY_ARCHITECTURE.md)。

## Build 62–64 — 持久化、研究与电子身份

完成 SQLite Evidence、CrazyTrace Schema 2 包和确定性回放；Protocol Research Lab 的试验、统计、候选 Signal Catalog、时间线与关系图；XP400 Electronic Identity 的身份模型、只读 DID 目录、拓扑和本地存储。它们都是只读研究基础设施，不新增车辆写入传输。

## Build 65 — Swift 6 + Release Hardening

完成外围并发归属、Sendable 目标模型、流式 Trace/CAN/Evidence、崩溃恢复、Release Safety、隐私裁剪、异常语料和版本/CI 门禁。详细验收矩阵保留在 [`builds/BUILD_065_RELEASE_HARDENING.md`](builds/BUILD_065_RELEASE_HARDENING.md)；4 小时 soak、真机/实车、OTA 和签名发布仍不是静态完成证据。

## Build 66 — GPS Speed Fallback + Unified Speed Resolver

完成 GPS 质量门禁、3 点中值/EMA、XP400 > OBD > GPS 优先级、过期回退、连续样本接管、Replay 覆盖、统一仪表消费、来源诊断和离线测试。详细实施记录见 [`builds/BUILD_066_GPS_SPEED_FALLBACK.md`](builds/BUILD_066_GPS_SPEED_FALLBACK.md)。代码门禁已完成，GPS/OBD/XP400 切源、后台、低电量和 Release 设备验收仍在 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。

## Build 67 — XP400 Dashboard Protocol Correction

完成 Data2 RTC 解码、Engine 低位修正、TCS Ready 位运算修复、Control rolling counter 原始证据、ABS 前轮速度/警告状态拆分、分级协议日志、有界 Packet Snapshot、命名实验 Marker 和 Mock 回归。详细实施记录见 [`builds/BUILD_067_DASHBOARD_PROTOCOL_CORRECTION.md`](builds/BUILD_067_DASHBOARD_PROTOCOL_CORRECTION.md)。三个 BLE/OBD 稳定核心文件保持零字节变化；Swift 纯数据解析和 `PTSpeed` Debug `build-for-testing` 已通过，真实仪表/道路/签名验收仍在 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。

## Build 68 — OBD Diagnostic Deep Mining

完成只读 DTC 深挖、Freeze Frame、Mode 01/02/06/09 能力证据、`0908`/`090A` ECU 身份、多个 CALID/CVN 与确定性 Firmware Fingerprint、`011F` Engine Session、PID 42/ATRV 电压分离、Relative Throttle 优先、NO DATA 语义、Baseline 统计、Polling 建议和 Trace 脱敏。详细实施记录见 [`builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md`](builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md)。`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 和 `PTBluetoothManager.swift` 继续冻结；iOS 编译和纯数据测试已通过，五类实车 Trial、真实适配器断连恢复与 Release/TestFlight 验收仍在 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。

## Build 69 — Protocol Semantic Evidence Intelligence

完成 XP400 Semantic Schema/Decoder、Data2 RTC 语义纠偏、Control/TCS Ready 位边界、ABS 前轮速度与 sentinel 识别、rolling tick 锚点、Discovery 降噪、ELM/OBD2/UDS 三层解析、DTC 状态、`unavailable` 与零值分离、Passport reducer、Evidence domain、BLE/OBD/GPS/Motion 统一 Observation 与 Correlation、Evidence schema v3、v2 migration、历史 JSONL/JSON 回放和 Dev Frame Inspector。实现只扩展外围证据与研究层，不修改 `PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 或 `PTBluetoothManager.swift`，不开放 ECU 写入、SecurityAccess、固件刷写、任意 CAN 注入和 ID 7 主动探针。

详细实施记录见 [`builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md`](builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md)。主 App Debug `build-for-testing` 与 Swift 6 纯代码解析已通过；当前工程 Scheme 不提供可用的具体 iOS Simulator destination，因此 XCTest 运行、真实 XP400/ELM327/YMOBD、后台和签名 TestFlight 验收仍需人工完成。

## Build 74 — Music Module Reliability Optimization

完成 Music 浏览稳定性改造：以 `PTMusicBrowseStore` 统一 Library/Search 的 payload、状态、取消、generation、request identity、超时和重试；资料库按歌曲 50、其他分类 40 分页，最近播放独立处理；缓存采用 TTL + stale-while-revalidate，并为搜索查询提供 20 项 LRU；Search、Library、Collection Detail 共用 UIKit 状态视图；权限、Cloud Library 和底层错误映射为稳定 UI 语义；Artwork cell 的复用身份校验保持不变。`PTMusicCoordinator`、`PTMusicTrack` 和 `PTMusicPlaybackManager` 的 MusicKit Swift 6 兼容警告也一并收敛。

实现证据：`PTSpeed` workspace Debug `build` 与 `build-for-testing` 已通过；新增 Store 测试已编译接入。当前 scheme 没有可用的具体 iOS Simulator destination，因此 XCTest 尚未在模拟器运行；Apple Music 账号矩阵、真机播放/搜索/分页、Release/TestFlight 仍需人工验收，完整待验收项见 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`。

## Build 76A — XP400 Vehicle Digital Twin 2D

完成 XP400 / XP400 GT 的只读 2D Digital Twin 第一阶段：统一车辆状态投影、fresh/aging/stale/unavailable、新旧数据源可追溯、2D 共用 Twin Snapshot、原创 SVG 分层素材包、车身 lean/pitch、车轮、灯光、转向灯、边撑、TCS/ABS/Engine 状态、主页卡片和全屏 UIKit 页面。全屏页面使用 `PTMotoBaseViewController`，数据通过现有 `PTVehicleTelemetryConsumerHub` 进入，不直接监听 BLE 或 OBD。

本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`，也没有调整 ELM327/YMOBD 的连接、初始化、握手、能力识别、命令顺序或 fallback。通用 iOS Debug build 与 `build-for-testing` 已通过；Instruments、真机和真实 XP400 GT 验收仍需在设备环境完成。详细记录见 [`builds/BUILD_076A_DIGITAL_TWIN_2D.md`](builds/BUILD_076A_DIGITAL_TWIN_2D.md) 与 [`builds/BUILD_076A_ASSET_IMPORT_GUIDE.md`](builds/BUILD_076A_ASSET_IMPORT_GUIDE.md)。

## Build 76B — XP400 Vehicle Digital Twin 3D

完成 SceneKit 3D 技术选型、原创程序化低面数 XP400/XP400 GT 资产契约、manifest/preview、稳定节点层级、前后轮与灯光/边撑独立节点、统一 `PTVehicleTwinSnapshot` Renderer、RPM/Fuel/Voltage/TCS/ABS/Engine 映射、Lean/Pitch/G-vector、Front/Rear/Left/Right/Top/Follow 相机、停车交互、骑行低干扰 Follow、2D/3D/Auto 切换和低电量/thermal 2D fallback。刹车灯与转向角没有可靠共享语义，因此没有臆测或伪造。

本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`，也没有重排 ELM327/YMOBD 连接步骤。通用 iOS Debug build 与 `build-for-testing` 已通过；manifest/节点/性能策略纯数据测试已接入。Instruments、真机/实车和 Build 76 Final Gate 仍需现场完成。详细记录见 [`builds/BUILD_076B_DIGITAL_TWIN_3D.md`](builds/BUILD_076B_DIGITAL_TWIN_3D.md) 与 [`builds/BUILD_076B_ASSET_IMPORT_GUIDE.md`](builds/BUILD_076B_ASSET_IMPORT_GUIDE.md)。

Build 76 收尾修复了 2D/3D 当前页面素材来源、2D wheel pivot/角速度积分和 Digital Twin 卡片点击入口。2D 当前优先加载 `XP400Twin2DAssets/xp400/` 的 PNG 分层素材，3D 当前固定使用 XP400 配置；卡片增加明确的 Open 触控入口并禁止 renderer 子视图抢占点击。干净 DerivedData 的通用 iOS Debug build 与 `build-for-testing` 均通过。现场点击、实车语义、Instruments 性能和 thermal 证据仍待人工验收。完整收尾记录见 [`builds/BUILD_076_DIGITAL_TWIN_CLOSEOUT.md`](builds/BUILD_076_DIGITAL_TWIN_CLOSEOUT.md)。

## Build 77 — Crazy Black Box Pro / CrazyTrace 2.0

完成 CrazyTrace 2.0 的外围实现：统一 Vehicle State Projection、Motion、GPS、适配器和协议事件进入单一有界 Recorder；增加 60 秒 Ring Buffer、事件前最多 60 秒与事件后最多 30 秒的 Incident Capture、结构化 `.crazytrace` 目录、诊断摘要、后台编码、staging 原子发布、隐私导出、旧 Schema 2/flat JSON 兼容和 bounded Reader。`PTReplayVehicleStateSource` 复用既有 `PTVehicleTelemetryBridge` 与 `PTCrazyTraceReplayPlayer`，Digital Twin 页面可导入 Trace 并继续通过既有 Consumer Hub 驱动 2D/3D renderer。

营销版本继续为 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `77`。本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 或 `PTOBDCommand.swift`，没有改变 ELM327/YMOBD 的连接、初始化、握手、能力识别、命令顺序和 fallback。结构化包、旧包兼容、脱敏和黑匣子离线测试已接入；XP400/XP400 GT 真车采集、后台/断连、2D/3D 字段一致性、无写入证明、Instruments 和 Release/TestFlight 仍需人工验收。详细记录见 [`builds/BUILD_077_CRAZYTRACE_2.md`](builds/BUILD_077_CRAZYTRACE_2.md) 与 [`builds/BUILD_077_REAL_VEHICLE_VALIDATION.md`](builds/BUILD_077_REAL_VEHICLE_VALIDATION.md)。

## 版本规则

营销版本继续为 `2.0.8`，只递增工程 Build。后续 Build 结果先追加本文件，再同步产品总纲、架构/协议/研究 canonical 文档；不要创建新的根目录路线图。
