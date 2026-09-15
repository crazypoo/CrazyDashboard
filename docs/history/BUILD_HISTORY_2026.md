---
doc_id: CD-HISTORY-2026-001
title: Build History 2026
type: history
status: stable
canonical: true
domain: build-history-2026
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-16
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

## 版本规则

营销版本继续为 `2.0.8`，只递增工程 Build。后续 Build 结果先追加本文件，再同步产品总纲、架构/协议/研究 canonical 文档；不要创建新的根目录路线图。
