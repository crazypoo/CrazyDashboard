---
doc_id: CD-ARCH-OBD-001
title: OBD Architecture
type: architecture
status: stable
canonical: true
domain: obd-architecture
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-16
related_builds:
  - 57
  - 60
  - 65
  - 68
supersedes: []
superseded_by:
---

# OBD 架构

## 分层关系

```text
BLE / Wi-Fi / Mock adapter
          ↓
PTHiddenOBDConnector  ← 通用 ELM327 物理连接与既有状态机
          ↓
PTOBDCommand / PTELM327Session / command queue
          ↓
PTMotoTelemetryManager / PTOBDBusCoordinator
          ↓
标准 PID、DTC、UDS 只读、CAN Capture、证据与回放

ELM327 capability identification
          ↓
PTYMOBDVendorExtension / YMOBD initializer + authenticator
          ↓
PTYMOBDAdapterModeCoordinator
          ↓
PTJieliSDKBridge / official Jieli RCSP OTA SDK
```

## ELM327 是底层，YMOBD 是扩展

项目不能把 YMOBD 当成另一种独立 OBD 传输。所有普通连接先通过 ELM327 兼容初始化、Prompt、命令队列、超时和响应分流；只有识别到 YMOBD capability 后，才启用 `AT+VERSION`、`AT+CRYPT`、厂商设备分类和维护模式。普通 PID/DTC/UDS/CAN 路径不依赖 Jieli SDK。

稳定边界：

- `PTHiddenOBDConnector.swift`：通用 ELM327 CoreBluetooth/Wi-Fi、连接生命周期和既有兼容逻辑。
- `PTOBDCommand.swift`：命令、分片和标准解码。
- `PTBluetoothManager.swift`：XP400 原车 BLE，不属于 OBD 的替代通道。

Build 57 以后新增的 Session、Vendor Extension、Bus Coordinator、Trace 和 OTA bridge 都通过适配器/兼容 facade 接入，不复制 CoreBluetooth 或 ELM327 物理写入器。

## Build 68 只读诊断证据层

`PTBuild68OBDDeepDiagnostics.swift` 位于稳定传输层之上，负责能力发现、DTC/Freeze Frame、Mode 06/09、ECU 身份、运行质量和证据投影。它通过既有 `PTAdvancedOBDCoordinator`、`performExclusiveTask` 和 `sendRawCommandAsync` 串行使用 ELM327 会话；不修改 `PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 或 BLE 核心。

```text
ELM327 ready
    ↓
Build68 capability discovery（0100/0120/0140/020000/0600/0900）
    ↓
ECU identity（0904/0906/0908/090A） + Mode06 continuation
    ↓
0101 preflight ── DTC > 0 ──→ 03/07/0A + Freeze Frame
    ↓
PID runtime evidence（success / NO DATA / failure / latency）
    ↓
Diagnostic Center / Garage / Protocol Evidence / Vehicle Passport / Trip
```

Capability 位图只在连接会话阶段读取；`0100/0120/0140` 不作为新增的高频诊断命令。单次 `NO DATA` 仅标记为暂时不可用，连续失败和历史成功共同决定 PID 可用性。所有新增命令都经过只读目录与 `PTOBDCommandClassifier`，不包含清码、写入、SecurityAccess 或刷写。

## 读路径与独占

普通读取使用单一 ELM Session 和串行队列；诊断任务经 `PTOBDBusCoordinator` 取得独占租约，结束、取消、超时或断开都必须归还租约并恢复轮询。UDS 结果统一区分 `62` 正响应、`7F` 否定响应/NRC、超时、截断和无效帧。大型节点扫描、DID 探测和 CAN Capture 只返回结构化结果并支持取消、速率限制和进度。

## YMOBD 与 Jieli

- YMOBD 普通认证、版本解析和能力识别属于 ELM327 Vendor Extension。
- Jieli RCSP OTA 只能通过官方 `JL_OTALib` SDK；CrazyDashboard 只做配置、生命周期、进度、取消、重连交接和版本回读。
- 不在 App 内重写 RCSP 分包、CRC、认证、断点或恢复算法。
- OTA 必须先完成适配器识别、固件检查、稳定供电、开发者安全开关和二次确认；普通用户入口不发送危险命令。

详见 [`YMOBD_JIELI_OTA_REFERENCE.md`](../protocols/obd/YMOBD_JIELI_OTA_REFERENCE.md)、[`OBD_DATA_DISCOVERY_LOG.md`](../research/OBD_DATA_DISCOVERY_LOG.md) 和 [`BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md`](../history/builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md)。历史计划保留在 [`CrazyDashboard_OBD_YMOBD_Jieli_OTA_Optimization_Plan.md`](../archive/roadmaps/CrazyDashboard_OBD_YMOBD_Jieli_OTA_Optimization_Plan.md)。

## 验证边界

纯解析、Mock、Swift 语法和目标编译只能证明外围契约。YMOBD 初始化、断线恢复、Jieli 设备重连、AE00/AE01/AE02 行为和真实 OTA 必须使用实际适配器、车辆、稳定电源和可回滚条件单独记录。
