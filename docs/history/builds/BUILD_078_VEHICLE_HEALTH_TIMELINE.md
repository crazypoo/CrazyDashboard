---
doc_id: CD-HISTORY-BUILD-078-HEALTH-001
title: Build 78 Vehicle Health Timeline
type: history
status: draft
canonical: false
domain: build-078-vehicle-health
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
  - 78
supersedes: []
superseded_by:
---

# Build 78 — Vehicle Health Timeline

## 范围

Build 78 在现有遥测、车辆档案、电池历史、诊断、保养和行程记录之上增加只读的车辆健康时间线。它不创建第二套电池数据库，也不新增 BLE、ELM327、YMOBD、UDS 或车辆写入传输层。

营销版本保持 2.0.8，工程 Build 推进到 78。PTBluetoothManager.swift、PTHiddenOBDConnector.swift、PTOBDCommand.swift 未修改；ELM327 仍是 OBD 底层，YMOBD 仍是其扩展边界。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B78-01 Repository Adapter | ✅ | 新增 PTVehicleHealthRepository，统一读取已有 Battery History、Garage、Trip、Build 68 Diagnostic 和 live Telemetry | 代码编译；字段的真实 XP400 含义仍需现场核对 |
| B78-02 Health Point | ✅ | 新增可 Codable/Sendable 的 PTVehicleHealthPoint，按车辆 UUID、来源、时间和 synthetic 标记保存 | 纯数据模型测试 |
| B78-03 Trend Calculator | ✅ | 提供 Battery、Mileage、DTC 图表数据以及 latest/min/max/average/slope 统计；指标斜率按对应字段计算 | 纯 Swift 测试；阈值不是厂家诊断结论 |
| B78-04 Diagnostic Timeline | ✅ | 把诊断报告、DTC 状态、Freeze Frame、Mode 6 数量和诊断会话写入健康时间线 | 只读结构化投影；真实 ECU 证据待补 |
| B78-05 Maintenance Merge | ✅ | 合并车库保养记录、仪表剩余保养里程和保养标志，继续按车辆隔离 | Mock/代码路径；真实仪表回传待补 |
| B78-06 Health UI | ✅ | 新增 PTVehicleHealthViewController，从车库进入，展示状态、来源、摘要、趋势和 JSON 分享 | UIKit 编译；布局/语言/真实数据仍需设备验收 |
| B78-07 Twin Summary | ✅ | Vehicle Twin 增加辅助健康摘要，不替换现有实时车辆指标 | 代码路径；2D/3D 现场视觉回归待补 |
| B78-08 Multi Vehicle | ✅ | 所有点按车辆 UUID 分组，查询、摘要、图表和导出只读取指定车辆 | 纯模型/存储边界测试 |
| B78-09 Storage Policy | ✅ | 使用单一 PTVehicleHealthTimeline.json，365 天保留、每车最多 2,000 点、原子本地/iCloud 持久化 | 目标编译；无网络/冲突/容量场景待补 |
| B78-10 Real-data Validation | 🟨 | 保留 XP400/XP400 GT 真车、电池、诊断、保养、长时间内存和 Release/TestFlight 清单 | 必须由真实设备与车辆完成，不能由 Mock 或编译替代 |

## 数据流

~~~text
PTVehicleConnectivityCoordinator
PTBatteryHealthHistoryStore
PTMotorcycleGarageStore
PTTripManager
PTBuild68DiagnosticCoordinator
             │
             ▼
PTVehicleHealthRepository
             │
             ├── PTVehicleHealthAnalyzer
             ├── PTVehicleHealthViewController
             ├── Vehicle Twin auxiliary summary
             └── PTDataPersistenceActor → PTVehicleHealthTimeline.json / iCloud
~~~

健康时间线只保存已经存在的数据投影，并用 isSynthetic 明确区分 Mock/回放与真实或历史来源。没有可靠语义的字段不会被推断为厂家健康结论。

## 验收门

在完成 BUILD_078_REAL_DATA_VALIDATION.md 前，Build 78 不标记为现场全部通过：

- 真实 XP400/XP400 GT 连接后，健康页能按正确车辆显示电池、里程、诊断和保养数据；
- Mock 数据不会跨车辆污染，也不会冒充真实健康状态；
- 前台、后台、断连、重连和 iCloud 无网络时，时间线不会破坏既有连接或轮询；
- 365 天/2,000 点上限持续有效，导出只包含用户选择的车辆；
- 健康页、Garage 和 Digital Twin 在多语言和不同屏幕尺寸下可用；
- Instruments、Release/TestFlight、真机/实车和长时间内存证据完成。

## 回滚

- 移除车库健康入口即可隐藏 Build 78 UI；既有 Garage、Twin、诊断和行程功能继续运行；
- 停止健康仓库监听不会停止 BLE、ELM327、YMOBD 或仪表轮询；
- 删除 PTVehicleHealthTimeline.json 只会清理健康历史，不影响现有车辆档案或原始诊断记录；
- 不修改或回滚三个稳定 BLE/OBD 核心文件来掩盖健康分析问题。

