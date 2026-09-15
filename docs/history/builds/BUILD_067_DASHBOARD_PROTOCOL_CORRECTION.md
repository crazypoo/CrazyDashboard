---
doc_id: CD-HISTORY-BUILD-067
title: Build 67 Dashboard Protocol Correction
type: history
status: stable
canonical: false
domain: build-067
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 67
supersedes: []
superseded_by:
---

# PTSpeed 2.0.8 Build 67 — XP400 仪表协议纠偏实施记录

> English: This record separates confirmed dashboard decoding from unresolved vehicle semantics.
>
> Español: Este registro separa la decodificación confirmada del tablero de la semántica del vehículo aún no resuelta.
>
> 中文：本记录区分已确认的仪表解码与仍未确认的车辆语义。

## 1. 版本与安全边界

| 项目 | 当前值 |
| --- | --- |
| Marketing Version | `2.0.8` |
| Build | `67` |
| 最低系统 | iOS 17.0+ |
| 核心范围 | XP400 Data2 RTC、TCS Ready、Control Counter、ABS 原始证据和开发者诊断 |
| 危险能力 | 不新增写入、SecurityAccess、CAN Injection、ECU 刷写或固件修改 |

以下稳定传输文件在本 Build 保持零字节变化：

```text
Global/BLE/PTBluetoothManager.swift
Global/OBD/Function/PTHiddenOBDConnector.swift
Global/OBD/Function/PTOBDCommand.swift
```

本次不需要申请临时解冻：所有改动都位于现有仪表模型、外围解码、Mock、开发者抓包和离线测试边界，没有改写 CoreBluetooth、ELM327 或 YMOBD 传输逻辑。

## 2. 已落地内容

| 工作包 | 结果 | 说明 |
| --- | --- | --- |
| B67-00 | 完成 | 所有工程 Target 对齐 `2.0.8 (67)`。 |
| B67-01 | 完成 | Data2 前三字节按 `B0 >> 2` 秒、`B1 >> 2` 分、`B2 >> 3` 时解码为可选 `PTDashboardClock`；非法时钟不进入业务显示。 |
| B67-02 | 完成 | Data2 不再把 `bytes[1]` 高位解释为背光、电瓶显示或边撑；保留低位原始值和既有发动机、电压、温度、保养字段。 |
| B67-03 | 完成 | TCS 模式仍只接受 `0x00/0x02/0x04`；Ready 从完整 `controlFlagsRaw` 的 bit7 读取。 |
| B67-04 | 完成 | Control 暴露 `rollingCounterRaw`，提供模 256 距离，并记录重复帧、跳变和正常 `+5` 诊断。 |
| B67-05 | 完成 | ABS 保留前轮速度与三个原始字节；警告灯状态改为 `unknown`，避免与轮速低字节冲突。 |
| B67-06 | 完成 | 增加 `normal/protocolDebug/rawHex` 分级日志和有界 `PTDashboardPacketSnapshot`。 |
| B67-07 | 完成 | CAN Lab 可为背光、边撑、ABS、TCS 实验添加命名事件，事件只写入抓包，不发送车辆指令。 |
| B67-08 | 完成 | Mock Data2 使用确认的 RTC 布局，Mock Control 使用回卷且每帧递增 5 的计数器。 |
| B67-09 | 待实测 | 真实停车、骑行、ABS 自检、TCS 三模式、背光/边撑 A/B 采样、Release 签名和设备验收。 |

## 3. 代码边界

数据流保持：

```text
XP400 BLE frame
    ↓
PTXP400TelemetryDecoder（包络校验）
    ↓
PTBluetoothServerManager+Diagnostics（语义解码）
    ↓
PTDashboardData2 / PTDashboardControl / PTAbsStatus（类型模型）
    ↓
Dashboard / Telemetry / Dev UI
```

界面和遥测协调层不再从 Data2 高位伪造背光、边撑或电瓶显示状态；ABS `unknown` 也不会覆盖已有可信 ABS 业务状态。原始 Payload 始终保留，供后续 Evidence、CAN 和 Replay 分析。

## 4. 自动化验证

已加入 `PTBuild67DashboardProtocolTests`，覆盖：

- `E5 DE 90 → 18:55:57`；`01 E2 90 → 18:56:00`；`25 06 98 → 19:01:09`；
- `0x5C >> 2` 作为分钟、`0x5C & 0x03` 作为 Engine Status；
- TCS `0x82` 为 Mode1 + Ready，`0x02` 为 Mode1 + Not Ready；
- Counter `F0 → F5`、`FA → 00` 和重复值的模运算；
- ABS `03 10 → 7.84 km/h`，保留 raw byte 且 warning 为 unknown；
- Packet Snapshot JSON 编解码和最多 200 条内存快照限制。

Swift 6 语法解析、`PTSpeed` workspace 的 Debug `build-for-testing` 已通过；`Scripts/build67_checks.sh` 负责版本、冻结文件、工程文件、JSON、文档和纯数据解析门禁。XCTest 实际运行、签名安装和车辆验证仍单独记录。

## 5. 验证边界

静态解析和离线测试不等于真机或实车验收。当前仍需在真实 XP400 上记录车辆型号、仪表固件、iOS、App Build、完整原始 Hex、命名 Marker 和 UI 结果，至少覆盖：

1. 冷车/热车启动、怠速、行驶、停车和熄火时的 RTC 与 Engine；
2. TCS Off、Mode1、Mode2 与 Ready 变化；
3. ABS 自检灯开/关与前轮速度同步；
4. Backlight Auto/LED0/LED1/LED2、Kickstand Up/Down 的低位 A/B 采样；
5. 长时间日志中的 Counter 丢帧、重复和回卷；
6. CAN Lab、主仪表、导航、Widget、Watch、CarPlay 的回归。

当前已验证主 App workspace 的 iPhoneOS Debug `build-for-testing`；模拟器实际运行、签名安装和 Watch/CarPlay/车辆联调仍需按设备环境单独验证。目标构建通过不能替代 XCTest 实际运行或实车结果。

## 6. Build68 延后项与回滚

以下继续保持未知，不在 Build67 通过猜测开放：

- Backlight 的正式字段映射；
- Kickstand 的正式字段映射；
- Battery Display 的正式字段映射；
- ABS Warning Lamp 的正式字段映射；
- Rolling Counter 的精确时间单位；
- 仪表 RTC 与手机日期、时区或时钟同步。

若新数据证明某个解码假设不成立，优先停止对应 UI 消费并继续保留 raw Payload；不得恢复 Data2 旧高位状态解释，也不得修改冻结传输核心来掩盖问题。TCS Mode、Engine、Voltage、车速、RPM、油量、里程、续航和前轮速度保留现有兼容路径。

## 7. 结论

Build67 已完成外围协议纠偏、可观测性和离线回归基础，未扩展任何高风险车辆写入能力。B67-09 的真实设备、实车和签名发布验收完成后，才可以把对应状态从待实测提升为已验证。
