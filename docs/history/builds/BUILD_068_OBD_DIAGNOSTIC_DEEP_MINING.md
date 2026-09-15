---
doc_id: CD-HISTORY-BUILD-068-001
title: Build 68 OBD Diagnostic Deep Mining
type: history
status: stable
canonical: false
domain: build-068
owner: Jax
created: 2026-09-16
last_reviewed: 2026-09-16
related_builds:
  - 68
supersedes: []
superseded_by: []
---

# Build 68 — OBD Diagnostic Deep Mining

## 版本定位

Build 68（营销版本仍为 `2.0.8`）把标准 ELM327 读取、YMOBD 扩展、诊断中心、统一遥测、车辆 Passport 和协议证据连接成一条只读、可追溯的诊断链路。

This release adds evidence-first OBD diagnostics around the existing ELM327/YMOBD transport. It does not replace the stable connection, framing, command, or BLE cores.

La versión añade diagnóstico OBD de solo lectura alrededor del transporte ELM327/YMOBD existente y no sustituye los núcleos estables de conexión, entramado, comandos ni BLE.

## 已实现

- P0 DTC escalation：`0101` 报告有 Confirmed DTC 时，在同一会话内有界读取 `03`、`07`、`0A`；不发送 `04` 清码。
- P0 Freeze Frame：按标准 PID 读取 `020200`、`020300`、`020400`、`020500`、`020600`、`020700`、`020B00`、`020C00`、`020D00`，保存 DTC 绑定、原始值和已解码值。
- P0 Capability discovery：连接会话阶段读取 Mode 01、Mode 02、Mode 06、Mode 09 能力，Mode 06 支持有界 continuation（`0600`、`0620`、`0640`、`0660`、`0680`、`06A0`）。能力探测不进入新增的高频深诊断任务。
- P0 Mode 09 identity：根据 `0900` 能力读取 `0904`、`0906`、`0908`、`090A`，支持多个 CALID/CVN，生成确定性的 ECU fingerprint，并保留 ASCII 失败时的原始证据。
- P0/P1 语义：单次 `NO DATA` 只记为临时不可用；连续失败、历史成功和能力位图分别参与 PID 状态判断。
- P0/P1 遥测质量：`0142`（ECU 控制模块电压）与 `ATRV`（适配器供电电压）分开；Relative Throttle（`0145`）优先于 Absolute Throttle（`0111`）；合法的 `0 km/h` 不触发 GPS 回退。
- P1 Engine session：从 `011F` 推导发动机启动时间，并在连续样本足够时提升证据等级，交给 `PTTripManager`。
- P1 baseline：按冷怠速、热怠速、巡航、加速、减速收集有界统计值，不把单次数据硬编码为故障阈值。
- P1 polling recommendation：根据能力、成功率、延迟和信号重要性生成 Tier A–D 建议；稳定轮询核心继续使用原有安全队列，不强行改写其传输行为。
- Security：Trace、诊断证据和 Build 68 导出默认遮盖 MAC 中间段、`crypt` 与 `AT+SETCRYPT`；CALID/CVN 保留用于研究。
- UI：现有 Diagnostic Center 增加 Build 68 只读摘要面板和脱敏 JSON 导出；保存到车库诊断报告并投影到 Protocol Evidence/Vehicle Passport 证据库。

## 实现边界

新增实现集中在 [`Global/OBD/Function/PTBuild68OBDDeepDiagnostics.swift`](../../../Global/OBD/Function/PTBuild68OBDDeepDiagnostics.swift)，并通过现有 `PTAdvancedOBDCoordinator`、`performExclusiveTask` 和 `sendRawCommandAsync` 串行访问 ELM327 会话。

`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`、`PTBluetoothManager.swift` 在本 Build 仍保持冻结，未修改字节。Build 68 不加入清码、写 DID、ECU Coding、SecurityAccess brute force、固件刷写或任何隐式危险命令。

## 代码与测试证据

| 项目 | 结果 |
| --- | --- |
| Build 版本 | `2.0.8 (Build 68)`，所有工程 Target 一致 |
| 纯数据测试 | `PTBuild68OBDDeepDiagnosticsTests` 覆盖 Header/DLC、能力 continuation、DTC/否定响应、Freeze Frame、CALID/CVN、NO DATA、Voltage、Throttle、011F、Polling、Trace 脱敏 |
| 工程检查 | `xcodebuild -list -project CrazyDashboard.xcodeproj` 通过 |
| iOS 编译 | `PTSpeed` Debug `build-for-testing` 通过；未把编译结果当作真机或实车证据 |
| 保护边界 | 三个冻结核心文件零字节改动 |
| 文档门禁 | 版本、文档索引、Build History、Active Work、产品总纲同步 |

## 实车验收仍待完成

以下项目需要配对的 iPhone、真实 ELM327/YMOBD、XP400GT 和 Release/TestFlight 包，不能由静态检查代替：

- Cold Idle、Warm Idle、DTC、Mode 06、Mode 09 五类 Trial；
- `03`、`07`、`0A`、Freeze Frame、`0908`、`090A` 和 `0600 → 0620` 的真实回传与超时表现；
- `0x7E8` 的重复 RX 证据及 `0x7E0` 仍保持 probable、不会被误标 confirmed；
- PID 42 / ATRV 的车辆值与适配器供电值差异；
- Relative Throttle、合法 `0 km/h`、GPS/OBD 切源和长时间运行时实时仪表无卡顿；
- 断连、取消、适配器低质量响应后总线租约、轮询和 UI 恢复正常。

## 回滚

`PTBuild68FeatureFlags` 可分别关闭自动 DTC、Freeze Frame、Mode 06、Mode 09、Adaptive Polling 和 Trace Redaction。关闭新增功能不会改变标准 PID、ELM327 连接或 YMOBD 原有路径。

