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
  - 78
  - 79
  - 80
  - 82
  - 83
  - 84
  - 85
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

## Build 78 — Vehicle Health Timeline

完成只读车辆健康时间线外围能力：PTVehicleHealthRepository 复用既有 live Telemetry、电池历史、Garage 诊断/保养、Trip 和 Build 68 Diagnostic Session；PTVehicleHealthAnalyzer 提供 Battery、Mileage、DTC 趋势与健康状态；数据按车辆 UUID 隔离，Mock/回放通过 isSynthetic 标记；Garage 新增健康页面入口，Vehicle Twin 增加辅助摘要。

健康时间线以单一 PTVehicleHealthTimeline.json 保存，使用 PTDataPersistenceActor 做本地与 iCloud 原子写入，365 天保留且每车最多 2,000 点，并提供 JSON 导出。营销版本保持 2.0.8，主 App、Widget 和 Watch 工程 Build 推进到 78。PTBluetoothManager.swift、PTHiddenOBDConnector.swift、PTOBDCommand.swift 保持零字节变化，ELM327/YMOBD 连接逻辑未改。

主 App Debug generic build 已通过，Build 78 健康分析纯逻辑测试已接入 build-for-testing；真实 XP400/XP400 GT、iCloud、前后台/断连、长时间性能和 Release/TestFlight 验收仍在 [Build 78 真车清单](builds/BUILD_078_REAL_DATA_VALIDATION.md)。

## Build 81 — Ghost Ride

完成只读 Ghost Ride 路线对比层：复用既有 GPX、PTRideReplay、Ride DNA、Road Surface、统一遥测和 XP400 Twin，新增路线归一化、空间重叠、进度索引、距离/时间插值、回放地图对比、Twin 当前/历史并排对比和 Dashboard Live Ghost。Ghost 只在同车且确认路线重叠时显示；偏离路线时安全隐藏，不改变导航、不发送车辆指令。Build81 不修改 BLE、ELM327、YMOBD、OBD 或 PTTripReport schema。Debug 工程、纯数据测试和现场路线验收仍需分别完成；详细记录见 [Build 81 实施记录](builds/BUILD_081_GHOST_RIDE.md)。

## Build 82 — Dynamic Dashboard

完成统一 Dashboard 上下文层：`PTDashboardContextEngine` 消费现有统一遥测、连接快照、导航会话和媒体变化，`PTDashboardContextResolver` 以 `Safety > Navigation > Vehicle > Media > Decoration` 解析主上下文和模块策略。主 Dashboard 与 XP400 Twin 2D/3D 共享同一策略，停车显示 Twin/Health，骑行强调 Speed/RPM，导航接近转向时强调导航并收缩 Twin，Warning 覆盖媒体/Ghost，连接降级提供低干扰提示。状态发布采用 20 Hz 上限，不改变底层采集。

Build82 增加纯 Resolver 回归测试、九种语言上下文文案、低干扰覆盖层和模块协议；主 App、Widget、Watch 的 Build 为 `82`，营销版本保持 `2.0.8`。本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`，也没有改变 ELM327/YMOBD 连接步骤、握手、轮询或 fallback。主 App workspace Debug `build` 与 `build-for-testing`、以及独立 Widget/Watch target 编译均已完成；真实车辆状态、CarPlay、前后台、性能、Release/TestFlight 和现场安装关系仍需验收。详细记录见 [Build 82 实施记录](builds/BUILD_082_DYNAMIC_DASHBOARD.md)。

## Build 83 — Music × Dashboard Theme

完成音乐封面驱动的 Dashboard 装饰主题：新增纯值 Theme Token、ImageIO/CoreGraphics 低分辨率 Artwork Color Extractor、有界缓存、对比度校验、主 Dashboard 适配、XP400 Twin 2D/3D 适配、安全上下文回退、设置开关和无权限/无封面 fallback。主题只影响背景、环境光、非语义 glow 和装饰卡片渐变，不影响 TCS、ABS、Warning、车速可读性、导航关键 UI 或车辆状态颜色。

Build83 的主题回归测试已接入 PTSpeedTests；主 App workspace Debug `build` 与 `build-for-testing` 均通过。营销版本保持 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `83`。本轮未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`，没有改变 ELM327/YMOBD 连接步骤、握手、轮询或 fallback。真实 Apple Music 权限、真机视觉/性能、Warning/Navigation 安全上下文、CarPlay、前后台和 Release/TestFlight 验收仍待完成。详细记录见 [Build 83 实施记录](builds/BUILD_083_MUSIC_DASHBOARD_THEME.md)。

## Build 84 — Pit Wall / 第二屏

完成默认关闭、仅 Wi-Fi 局域网、Token 配对、只读的 Pit Wall 第二屏：复用现有统一 Vehicle Telemetry 与 XP400 Twin Snapshot，新增 GET-only `NWListener`、Bonjour `_pt-pitwall._tcp`、隐私裁剪后的 Snapshot/rolling samples/events JSON、内置浏览器 UI、简化 2D Twin、Live Map、Speed/RPM rolling chart、设置页开关与配对分享，以及前后台/场景生命周期清理。所有数据都经过有界模型和坐标舍入，不暴露 VIN、蓝牙 UUID、原始 Hex、诊断错误或协议载荷。

Build 84 没有修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`，没有改变 ELM327/YMOBD 的连接、初始化、握手、能力识别、命令顺序、轮询或 fallback；没有新增 BLE 写入、OBD 写入、OTA、SecurityAccess 或车辆控制入口。营销版本保持 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `84`。主 App Debug generic iOS `build` 与 `build-for-testing` 已通过；B84-10 纯边界测试已编译接入，但当前环境没有可用的具体 Simulator destination，真实 iPhone/LAN 浏览器、系统局域网授权、断网/场景生命周期、Release/TestFlight 和长期性能仍需人工验收。详细实施记录见 [`builds/BUILD_084_PIT_WALL.md`](builds/BUILD_084_PIT_WALL.md)。

## Build 85 — Vehicle Intelligence

完成只读车辆智能摘要层：新增 `PTVehicleIntelligence` Schema、Evidence Pack、规则分析器、车辆范围去重/过期和 false-positive review。分析器复用 Build 78 Health、Build 79 Road Surface、Build 80 Ride DNA、Trip、DTC、Garage Maintenance 与已确认 XP400 Semantic State，提供电池六次真实启动趋势、发动机怠速基线、确认/待定 DTC、保养剩余里程、最近行程、道路体验和新鲜 XP400 ABS 状态摘要。每条洞察都携带来源、时间窗口、样本数、质量和证据说明；Unknown Candidate、Probable Protocol Field、Raw Hex Guess 以及 Mock/Replay synthetic 数据不进入可通知故障。

Vehicle Twin 停车页已接入紧凑的 Vehicle Summary 与 evidence count；Twin 只显示定位信息，不播放伪造故障动画。通知策略仅允许非 synthetic、confirmed/observed、可操作且非保养类洞察，并复用现有 `PTNotificationCenter` 的冷却、去重和权限边界。Ride/Road 洞察以事实发生时间为基准 24 小时过期，不会因为重新计算而延长旧证据生命周期。

营销版本保持 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `85`。`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持零字节变化，ELM327/YMOBD 连接、初始化、握手、能力识别、命令顺序、轮询和 fallback 未改。Build85 纯规则测试已接入，主 App workspace Debug `build` 与 `build-for-testing` 已通过；真实车辆、通知权限、长时间性能和 Release/TestFlight 仍需人工验收。详细记录见 [`builds/BUILD_085_VEHICLE_INTELLIGENCE.md`](builds/BUILD_085_VEHICLE_INTELLIGENCE.md)。

## Build 80 — Ride DNA

完成结构化 Ride DNA 纯计算层：从既有行程报告提取 Pace、Engine、Motion、Road、Efficiency、Coverage，生成 RPM/倾角/G 直方图、同车历史比较和高转速/强冲击/最大倾角/最长怠速/粗糙路段回放标记；列表摘要、详细分析页、JSON 分享和 Replay 共用同一份结果。Build80 不修改 PTTripReport schema，不增加任何 BLE、ELM327、YMOBD、CAN 或 UDS 传输。Debug 工程编译、静态门禁和纯数据测试已接入；真实 XP400/XP400 GT、长历史性能、UI/本地化和 Release/TestFlight 仍需验收。详细记录见 [Build 80 实施记录](builds/BUILD_080_RIDE_DNA.md)。

## Build 79 — Road Surface Intelligence

完成只读道路体验层：复用既有 PooTools Motion、PTLocationEngine、统一 Vehicle Telemetry 和 CrazyTrace，新增有界采样窗口、速度/GPS/倾倒门控、支架偏置校准、路面评分、pothole/speed bump/repeated vibration/strong impact 候选分类、路段分割与去重。道路数据按车辆 UUID 隔离，Mock/Replay 标记为 synthetic，使用 `PTDataPersistenceActor` 保存 180 天/每车 2,000 段的本地与 iCloud JSON。

Garage 新增 Road Surface 页面，提供 MapKit 路线覆盖、事件点、质量摘要、JSON 分享和停车校准；Vehicle Twin 在强冲击时显示短暂 Road Impact 提示，回放通过统一快照重算。营销版本保持 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `79`。三个稳定 BLE/OBD 核心零字节变化，ELM327/YMOBD 连接流程未改。

纯数据回归和工程接入已完成；真实 XP400/XP400 GT 道路场景、固定支架校准、前后台/断连、iCloud、长时间性能和 Release/TestFlight 验收仍在 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md)。详细记录见 [`builds/BUILD_079_ROAD_SURFACE_INTELLIGENCE.md`](builds/BUILD_079_ROAD_SURFACE_INTELLIGENCE.md) 与 [`builds/BUILD_079_REAL_DATA_VALIDATION.md`](builds/BUILD_079_REAL_DATA_VALIDATION.md)。

## 版本规则

营销版本继续为 `2.0.8`，只递增工程 Build。后续 Build 结果先追加本文件，再同步产品总纲、架构/协议/研究 canonical 文档；不要创建新的根目录路线图。
