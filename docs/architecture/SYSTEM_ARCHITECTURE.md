---
doc_id: CD-ARCH-SYSTEM-001
title: System Architecture
type: architecture
status: stable
canonical: true
domain: system-architecture
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 61
  - 66
supersedes: []
superseded_by:
---

# 系统架构

## 产品运行面

```text
PTSpeed iPhone App
  UIKit / SwiftUI / Dev
  ├─ PTVehicleConnectivityCoordinator
  ├─ Navigation / Location / Ride / PTT / Live Activity
  ├─ OBD / Evidence / CrazyTrace / OTA adapters
  └─ Widget / Watch / CarPlay projections

XP400 BLE ── PTBluetoothManager ───────────────┐
ELM327 OBD ─ PTHiddenOBDConnector + PTOBDCommand ─┤
GPS / Motion / Replay ──────────────────────────┘
                         ↓
       PTVehicleTelemetryBridge / unified snapshot
                         ↓
       Consumer Hub + domain-specific projections
                         ↓
       Dashboard / Ride / Dev / Widget / Watch / CarPlay
```

## 不可破坏边界

- `Global/BLE/PTBluetoothManager.swift` 是 XP400 BLE CoreBluetooth GATT、认证、Credits、分片和车辆状态链路的稳定拥有者。
- `Global/OBD/Function/PTHiddenOBDConnector.swift` 是通用 ELM327 CoreBluetooth/Wi-Fi 兼容连接和既有状态机的稳定拥有者；YMOBD 是其能力扩展，不是替代传输层。
- `Global/OBD/Function/PTOBDCommand.swift` 是标准命令、分片和解码契约的稳定拥有者。
- 三个文件默认零字节变化。需要修改时必须单独说明协议影响、实车证据、测试和回滚，并取得明确解冻许可。

BLE 与 OBD 都使用 CoreBluetooth，但只在外围协调层处理扫描、连接身份、总线租约、状态聚合和生命周期；不把两个稳定实现直接拼成一个传输类。

## 数据与并发

- 传输层产生值类型事件；`PTVehicleTelemetryBridge` 形成统一、可追溯的遥测快照。
- UI 和 View Controller 由 `@MainActor` 持有，只接收不可变投影。
- OBD Session、Evidence、CrazyTrace 和回放使用串行拥有者或 `Sendable` 值类型，避免把 delegate 对象送入后台任务。
- 大型 Evidence、Trace 和 Capture 通过分页或批次流式消费；兼容 API 可以返回完整数组，但新路径不得默认整库读入内存。

## 系统集成

- iCloud、App Group、Watch Connectivity、WidgetKit、CarPlay 和 Live Activity 消费投影，不直接拥有车辆传输状态。
- PTT Live Activity 必须绑定有效组群会话；冷启动不创建虚假活动。
- 普通 App 只读诊断；未知写入、SecurityAccess、CAN injection、OTA 和刷写停留在 Dev/研究边界。

## 证据等级

文档和 UI 必须区分静态检查、自动化测试、目标编译和真实 iPhone/Apple Watch/OBD/XP400 验证。较低层级证据不能把上层功能标为真车已验证。

