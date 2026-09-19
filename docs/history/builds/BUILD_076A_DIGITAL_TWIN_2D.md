---
doc_id: CD-HISTORY-BUILD-076A-001
title: Build 76A Digital Twin 2D
type: history
status: draft
canonical: false
domain: build-076a
owner: Jax
created: 2026-09-19
last_reviewed: 2026-09-19
related_builds:
  - 76
supersedes: []
superseded_by: []
---

# Build 76A — XP400 Vehicle Digital Twin 2D

## 版本定位

Build 76A（营销版本继续为 `2.0.8`，工程 Build 为 `76`）建立 XP400 / XP400 GT 的只读 2D Digital Twin。它复用现有 `PTUnifiedVehicleTelemetrySnapshot`、`PTVehicleConnectivityCoordinator` 和 `PTVehicleTelemetryConsumerHub`，不创建第二套 BLE、ELM327、YMOBD 或遥测研究通道。

Build 76A keeps the ELM327 transport, YMOBD extension boundary, CoreBluetooth dashboard manager and standard OBD command behavior unchanged. The twin is a read-only presentation layer.

La capa Twin es solo de lectura y mantiene intactos el transporte ELM327, la extensión YMOBD, el gestor CoreBluetooth del tablero y los comandos OBD estándar.

## 已实现范围

- `PTVehicleTwinSnapshot`：为 2D 与后续 3D 共用的车辆状态输入，保留来源、采集时间、模拟数据标记和 fresh/aging/stale/unavailable 新鲜度。
- `PTVehicleTwinStateMapper`：将 XP400、OBD、GPS、Motion 和连接状态映射到统一状态；TCS、ABS、灯光和边撑没有可靠数据时保持 unavailable，不填充假值。
- `PTVehicleTwinStore`：通过现有遥测消费者 Hub 接收快照，页面不直接监听 BLE/OBD。
- `PTXP400TwinView`：轻量 UIKit/Core Animation 2D renderer，支持车身 lean/pitch、轮胎旋转、远光/近光、转向灯、危险灯和边撑显示。
- `PTXP400TwinCardView`：已接入 `PTMotoInfoViewController`，点击进入全屏 `PTVehicleTwinViewController`。
- `XP400Twin2DAssets`：提供 XP400 / XP400 GT 的原创近似 SVG 分层素材、manifest、pivot/anchor 和 preview；已作为 PTSpeed bundle resource 导入，运行时同时保留程序化 fallback。
- `PTVehicleTwinTests`：覆盖 freshness、Mock 标记、unavailable 不转成数字零、断开后缓存降级为 stale、Motion/Engine 分离。

## 稳定核心边界

本 Build 未修改：

- `Global/BLE/PTBluetoothManager.swift`
- `Global/OBD/Function/PTHiddenOBDConnector.swift`
- `Global/OBD/Function/PTOBDCommand.swift`

ELM327 仍然是 OBD 底层连接，YMOBD 仍然是其扩展；Build 76A 没有重排 YMOBD 初始化、握手、能力识别、特征订阅、命令顺序、超时或 fallback。

## 验证状态

| 项目 | 状态 |
| --- | --- |
| Swift 代码接入 | 已接入工程源码和测试 target |
| 2D Asset Pack | 已交付并导入 PTSpeed bundle，含原创 SVG、manifest、preview 和导入说明 |
| 主 App / Card / Full Screen | 已实现，通用 iOS Debug build 已通过 |
| 纯数据回归 | 测试 target 已通过通用 iOS `build-for-testing` 编译 |
| Instruments | 待在真机执行 Time Profiler、Core Animation、Allocations |
| XP400 GT 真车 | 待使用真实仪表验证速度、RPM、燃油、电压、TCS/ABS、灯光、边撑和断连恢复 |
| 后台/前台 | 待真实设备验证状态 freshness 和页面恢复 |

静态编译和纯数据测试不能替代真实车辆行为。只有真机、实车和 Instruments 证据完成后，才能把 Gate 76A 标记为完整通过，并进入 76B 的 3D 阶段。
