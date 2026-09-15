---
doc_id: CD-RESEARCH-OBD-001
title: OBD Data Discovery Log
type: research
status: active
canonical: true
domain: obd-data-discovery
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-16
related_builds:
  - 57
  - 60
  - 64
  - 65
  - 68
supersedes: []
superseded_by:
---

# OBD 数据发现日志

本日志只追加可追溯观察，不把候选协议自动提升为可执行命令。每条记录应注明来源 `live`、`mock`、`replay` 或 `imported`，设备/车型、时间、原始数据位置、人工确认状态和安全影响。

## 2026-09-15：现有 YMOBD/Jieli 研究收口

| 结论 | 等级 | 依据与边界 |
| --- | --- | --- |
| YMOBD 是 ELM327 会话上的扩展能力 | Confirmed | 当前架构、Vendor Extension 和适配器代码；不能替换通用 ELM transport |
| `AT+VERSION`、普通认证和 `0100` 属于初始化/能力识别 | Confirmed / Inferred | 研究文档与夹具；目标适配器完整状态机仍需现场验证 |
| Jieli RCSP OTA 由官方 iOS SDK 承担 | Confirmed | `JL_OTALib` 与 `PTJieliSDKBridge` 边界；真实传输闭环未完成 |
| OTA 检查/下载完成不等于刷写成功 | Confirmed | 版本回读要求与 Release 安全策略 |
| XP400 ECU 写入、SecurityAccess、任意 CAN injection | Unknown | 当前没有足够车型协议、回滚和实车证据，保持拒绝 |

## 2026-09-16：Build 68 OBD 深诊断基线

以下是来自 Build 68 输入研究日志的 `imported`/`captured` 基线，不代表本次代码检查重新连接了真实车辆；后续实车试验仍必须保存完整原始 Hex、适配器和固件信息。

| 观察 | 证据等级 | 当前处理 |
| --- | --- | --- |
| OBD 使用 ISO 15765、11-bit、500 kbit/s；观察到 RX `0x7E8` | Captured | 保存为 `captured` 地址证据；TX `0x7E0` 仍为 `probable` |
| `0100`、`0120`、`0140` 能力位图返回标准 PID 范围 | Captured | 只在 Session discovery 阶段读取，不进入高频 Runtime Loop |
| `0900` 能力可引导 `0904`/`0906`/`0908`/`090A` | Inferred / Captured | 只读保存原始响应；ASCII 失败保留 raw fallback |
| CALID `XP40E54000370000` 与 CVN 可用于 ECU 指纹 | Captured | 支持多个 record，生成确定性 fingerprint，不作为刷写授权 |
| `010D = 00` | Captured | 解释为合法 `0 km/h`，禁止用零值触发 GPS fallback |

Build 68 新增的证据字段包括 Confirmed/Pending/Permanent DTC、Freeze Frame、Mode 06 continuation、ECU 名称、011F 运行时间、PID42/`ATRV` 电压、Relative Throttle、延迟 EWMA 和脱敏后的 Trace。单次 `NO DATA` 不晋级为 Unsupported；只有重复会话或直接官方契约才能提升证据等级。

## 证据晋级规则

1. 先保存脱敏原始样本和最小复现步骤。
2. 用纯解析器或 Replay 复现，不在车辆上直接重复未知写入。
3. 至少两次不同时间/会话的相同结果，或有官方/SDK 直接契约，才从 Inferred 进入 Confirmed。
4. 任何可写命令仍需独立的安全审计、开发者门禁和回滚方案，不因字段确认而自动开放。

## 待验证队列

- YMOBD BLE 模式切换后的服务、广播名和重连匹配。
- Jieli SDK 的真实设备识别、RCSP characteristic、断点和中断恢复。
- XP400 只读 UDS 的车型/固件适用性、多帧和否定响应矩阵。
- CAN Capture 与 OBD 命令时间关联的多适配器实车证据。
- Cold Idle、Warm Idle、DTC、Mode 06、Mode 09 五类 Trial，以及断连/取消后轮询恢复。
- PID 42 与 `ATRV` 的车辆/适配器电压差异、Relative Throttle 优先级和长时间低带宽表现。

参考：[`YMOBD_JIELI_OTA_REFERENCE.md`](../protocols/obd/YMOBD_JIELI_OTA_REFERENCE.md)、[`PTSpeedTests/OBD`](../../PTSpeedTests/OBD) 和已归档的 [OBD 长期计划](../archive/roadmaps/CrazyDashboard_OBD_YMOBD_Jieli_OTA_Optimization_Plan.md)。
