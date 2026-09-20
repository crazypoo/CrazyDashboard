---
doc_id: CD-PLANNING-ACTIVE-001
title: Active Work
type: planning
status: active
canonical: true
domain: active-work
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-20
related_builds:
  - 66
  - 67
  - 68
  - 69
  - 74
  - 76
  - 77
  - 78
supersedes: []
superseded_by:
---

# 当前工作

快照日期：2026-09-20。当前工程版本为 `2.0.8 (Build 78)`。本文件只保留仍需要完成或验收的工作；已完成 Build 的完整实施正文进入 [`history/BUILD_HISTORY_2026.md`](../history/BUILD_HISTORY_2026.md) 或对应的验收记录。

## Build 78：Vehicle Health Timeline 🟨

代码实现已完成：新增有界的 PTVehicleHealthRepository、PTVehicleHealthPoint、健康趋势分析器和只读 Vehicle Health 页面；适配现有电池历史、诊断报告/会话、车库保养、行程和 live Telemetry。健康数据按车辆 UUID 隔离，区分 Mock/回放与真实/历史来源，使用单一 PTVehicleHealthTimeline.json 通过 PTDataPersistenceActor 做本地/iCloud 原子保存；Garage 新增入口，Vehicle Twin 增加辅助健康摘要。

三个稳定核心 PTBluetoothManager.swift、PTHiddenOBDConnector.swift、PTOBDCommand.swift 保持冻结；ELM327 仍是 OBD 底层，YMOBD 仍是其扩展。Build 78 的真实设备门禁尚未完成：需要 XP400/XP400 GT 电池、里程、保养、DTC、行程、多车、前后台/断连、iCloud、Instruments 和 Release/TestFlight 验证。详细记录见 [Build 78 实施记录](../history/builds/BUILD_078_VEHICLE_HEALTH_TIMELINE.md) 与 [Build 78 真车验收清单](../history/builds/BUILD_078_REAL_DATA_VALIDATION.md)。

## Build 77：Crazy Black Box Pro / CrazyTrace 2.0 🟨

代码实现已完成：统一遥测、位置、Motion、适配器和协议事件进入同一个有界 CrazyTrace；新增 60 秒 Ring Buffer、事件前后窗口、结构化 `.crazytrace`、后台原子导出、隐私导出、旧包兼容、批量 Reader、Replay Source 和 Digital Twin 导入入口。回放继续复用既有 `PTVehicleTelemetryBridge`、`PTCrazyTraceReplayPlayer` 和 `PTVehicleTelemetryConsumerHub`，不新增 BLE、ELM327、YMOBD 或研究传输层。

三个稳定核心 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持冻结；ELM327 仍是 OBD 底层，YMOBD 仍是其扩展。Build 77 的真实设备门禁尚未完成：需要 XP400/XP400 GT 实车采集、前后台/断连恢复、2D/3D 回放一致性、无车辆写入证明、Instruments 和 Release/TestFlight 验证。详细记录见 [`../history/builds/BUILD_077_CRAZYTRACE_2.md`](../history/builds/BUILD_077_CRAZYTRACE_2.md) 与 [`../history/builds/BUILD_077_REAL_VEHICLE_VALIDATION.md`](../history/builds/BUILD_077_REAL_VEHICLE_VALIDATION.md)。

## Build 76：XP400 Vehicle Digital Twin 收尾 🟨

代码范围已收口：当前 2D/3D 页面统一选择 XP400 素材/配置；2D wheel 已改为原生 2:1 XP400 canvas、轮环静止、交叉轮辐按真实轮心和时间积分旋转；原创素材已补齐棱角车身、高位烟熏风挡、灯组、前叉和 XP400 风格交叉辐条，3D 程序化模型同步补齐对应结构；Digital Twin 卡片增加明确的 Open 按钮并禁止内部 renderer 抢占触摸。干净 DerivedData 的通用 iOS Debug build 与 `build-for-testing` 已通过，三个稳定 BLE/OBD 核心零改动。

只剩真实设备门禁：iPhone 点击与滚动冲突、XP400/XP400 GT 实车字段语义、长时间帧率/内存/Energy/thermal 和 Release/TestFlight 包验证。完成这些证据后，再把 Build 76 Final Gate 从 `🟨` 更新为完整通过。

详细记录见 [`../history/builds/BUILD_076_DIGITAL_TWIN_CLOSEOUT.md`](../history/builds/BUILD_076_DIGITAL_TWIN_CLOSEOUT.md)。

## Build 76B：XP400 Vehicle Digital Twin 3D 🟨

代码已完成 SceneKit 3D Renderer、XP400 当前资源/配置、原创程序化低面数资源契约、稳定节点层级、统一 `PTVehicleTwinSnapshot` 状态映射、Lean/Pitch/G-vector、六组相机、停车交互、骑行 Follow、2D/3D/Auto 切换和低电量/thermal 2D fallback。没有修改 BLE、ELM327、YMOBD 或标准 OBD 核心；3D 页面不建立第二套连接监听链。

已通过：

- PTSpeed 通用 iOS Debug build；
- PTSpeed 通用 iOS `build-for-testing`；
- 3D manifest、节点契约和性能策略 XCTest 编译；
- `git diff --check` 与文档门禁。

仍需真实 iPhone、XP400/XP400 GT 和 Release/TestFlight 包验证：

- 3D 实车 Speed、RPM、Fuel、Voltage、TCS/ABS、边撑、灯光、Lean/Pitch 与断连 stale；
- 2D/3D/Mock/Auto fallback 双模式回归；
- Time Profiler、Core Animation、Allocations、Energy Log、thermal pressure 和长时间内存/帧率；
- 真实设备上停车旋转/缩放、骑行 Follow 和不同尺寸布局。

刹车灯和转向角当前没有可靠共享语义，继续保持不可伪造原则，不在 76B 中标记为已实现。

## Build 76A：XP400 Vehicle Digital Twin 2D 🟨

代码已完成只读 Vehicle State Projection、fresh/aging/stale/unavailable、共用 `PTVehicleTwinSnapshot`、XP400/XP400 GT 原创近似 SVG 资产包、2D renderer、状态/运动映射、主页卡片和全屏页面。三项稳定 BLE/OBD 核心保持冻结，ELM327/YMOBD 连接链路没有改动。

仍需真实 iPhone、XP400 GT 和 Release/TestFlight 包验证：

- 速度、RPM、燃油、电压、TCS、ABS、灯光、转向灯、边撑与真实仪表含义逐项核对；
- Mock 高频更新、断连 stale/unavailable、重连、后台/前台恢复；
- Time Profiler、Core Animation、Allocations，确认主仪表和 Twin 页面没有明显掉帧或增长；
- 2D 资产的车轮中心、倾斜锚点和不同屏幕尺寸布局。

未完成上述证据前，不把 Gate 76A 标记为完整发布通过；76B 代码已接入，但 Build 76 Final Gate 仍需 76A/76B 的现场证据。

## Build 66 收口：统一车速真实验证 🟨

代码和离线门禁已完成，以下项目仍需真实 iPhone、GPS、OBD 和 XP400 验证：

- GPS-only 前台道路测试，确认合法 `0 km/h`、弱信号和精度门禁。
- GPS → ELM327 OBD：连续两个有效新鲜样本后切换到 OBD。
- OBD → GPS：车速回传过期后及时回退，不保留旧速度。
- OBD → XP400：XP400 的两个新鲜样本接管；XP400 断开后回落到 OBD/GPS。
- 前后台、定位权限变化、低电量和弱 GPS 条件下的显示稳定性。
- 主仪表与 Peugeot 仪表没有 `0 → -- → speed` 异常跳变。
- Release 签名包、后台行为和版本门禁复核。

验收证据必须记录设备型号、iOS、App Build、适配器、车辆/道路条件、开始结束时间、来源切换、内存/电量和日志位置。完成后把 B66-13 从 `🟨` 更新为对应状态，并同步产品总纲与 Build History。

## Build 67 收口：XP400 仪表协议真实验证 🟨

代码、纯数据测试和外围安全边界已完成；以下项目仍需真实 iPhone、XP400 仪表和 Release 包验证：

- 三组日志 RTC 样例与实车时钟连续性，包括跨分钟和跨小时；
- Engine、Voltage、TCS Off/Mode1/Mode2 与 Ready 状态；
- ABS 自检灯开/关与前轮速度 `0x0310 → 7.84 km/h` 的现场对应关系；
- Backlight、Kickstand 和 Battery Display 的命名 Marker A/B 采样，不能把未知位直接升级为产品字段；
- 长时间 Counter `+5`、回卷、重复和丢帧诊断；
- CAN Lab、主仪表、导航、Widget、Watch、CarPlay 的回归；
- Debug/Release 构建、安装和版本门禁。

验收记录必须包括车辆型号、仪表固件、iOS、App Build、适配器、测试时间、完整原始 Hex、Marker、解析结果和失败/断连表现。完成后把产品总纲中的 B67-09 从 `🟨` 更新为对应状态，并同步 Build History、协议文档和研究日志。

## Build 68 收口：OBD 诊断深挖与 ECU 证据真实验证 🟨

代码、纯数据回归测试、iOS `build-for-testing` 和证据/导出边界已完成；以下项目仍需真实 iPhone、真实 ELM327/YMOBD、XP400GT 和 Release/TestFlight 包验证：

- Cold Idle、Warm Idle、DTC、Mode 06、Mode 09 五类 Trial；
- `03`、`07`、`0A`、Freeze Frame、`0908`、`090A`、`0600 → 0620` 的真实回传、否定响应和超时表现；
- `0x7E8` 的重复 RX 证据；`0x7E0` 继续保持 probable，不得仅凭常规地址升级为 confirmed；
- PID 42 / ATRV 的真实值分离、Relative Throttle 优先、合法 `0 km/h` 与 GPS/OBD 切源；
- 断连、取消、适配器低质量响应后的总线租约、轮询恢复和 Diagnostic Center 状态；
- 真实长时间运行下的 PID 延迟、成功率、Baseline 统计和主仪表流畅度；
- Build 68 脱敏 JSON、车库报告、Protocol Evidence/Vehicle Passport 的读取与分享结果。

验收证据必须记录车辆型号、ECU/仪表固件、iOS、App Build、适配器型号/固件、测试时间、完整原始 Hex、命令顺序、来源切换、错误与恢复表现。未完成上述现场证据前，不把 Build 68 标记为完整发布通过。

## Build 69 收口：协议语义与证据智能 🟨

Build 69 的外围代码、Swift 6 纯解析、`build-for-testing`、版本门禁和文档门禁已完成。实现范围包括 XP400 Semantic Schema/Decoder、Data2 RTC、TCS/ABS 边界、rolling tick、sentinel、Discovery 降噪、ELM/OBD2/UDS 分层、DTC 状态、Passport reducer、跨源 Observation/Correlation、Evidence v3、v2 migration、历史回放和 Dev Inspector。三个稳定传输核心文件仍保持冻结。

以下项目仍需要真实 iPhone、XP400GT、ELM327/YMOBD、Release/TestFlight 包或用户提供的脱敏样本完成验收：

- `MotoHexLog_20260916_160950.txt` 的 Swift 回放结果与真实记录逐字段核对；
- `xp400-protocol-discovery-1789537483.jsonl`、`crazydashboard-protocol-evidence-v2-1789546983.json` 的候选率 `<10%`、sentinel、RTC、counter 和 TX `01` 现场复核；
- Data2 RTC 跨分钟/跨小时、TCS、ABS 前轮速度与警告灯、Data3 配置字段、真实 OBD/UDS 多帧和否定响应矩阵；
- BLE、OBD、GPS、Motion 跨源时间偏差、后台/断连恢复、长时间性能和 Release 安装验证。

验收时必须区分静态/编译证据与真机/实车证据；Build 69 不开放 ECU 写入、SecurityAccess、固件刷写、任意 CAN 注入或 ID 7 主动探针。详细记录见 [`../history/builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md`](../history/builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md)。

## Build 74：Music 模块稳定性优化 🟨

代码门禁已完成：资料库、搜索和详情页已统一使用 `PTMusicBrowseStore`/状态机，加入不可变 `QueryKey`、generation/request identity、取消与迟到响应丢弃、UI watchdog、分页、stale-while-revalidate 缓存、搜索 LRU 缓存、权限/Cloud Library 预检、稳定错误映射和统一重试视图；新增的并发测试已接入 `PTSpeedTests`，且没有修改 BLE/OBD 核心。

仍需真实设备验收：

- Apple Music 已订阅、未订阅、Cloud Library 开/关、权限拒绝/限制和空资料库矩阵；
- Wi-Fi、蜂窝、断网恢复、高延迟、搜索快速输入/切 scope、资料库快速切 segment 和分页到底；
- Album、Playlist、Artist 详情加载、Artwork 复用、SystemMusicPlayer/ApplicationMusicPlayer 切换与播放；
- Release/TestFlight 包和当前 Apple Music 服务行为。

当前静态证据：`PTSpeed` workspace Debug `build` 与 `build-for-testing` 已通过。由于当前 Xcode scheme 没有可用的具体 iOS Simulator destination，本轮 XCTest 尚未在模拟器执行；上述真机/服务依赖项不能由编译结果替代。

## 不在当前工作中

- Build 69 新增的 UDS/历史回放/跨源分析扩展，若超出当前只读证据范围，先写入 [`BACKLOG.md`](BACKLOG.md)，不要新建根目录路线图。
- `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 仍是冻结核心；本文件不授权解冻。
- QWeather 现有可用链路不在本轮治理范围。

## 发布与回滚门

在真实验证未完成前，不把 Build 66–68 标记为完整发布通过。若速度回退出现异常，先关闭 `PTBuild66FeatureFlags.gpsSpeedFallbackEnabled`；若 Build 68 深诊断出现适配器兼容问题，按需关闭 `PTBuild68FeatureFlags` 对应开关。不得回滚或修改 BLE/ELM327 核心来掩盖问题。
