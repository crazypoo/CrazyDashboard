---
doc_id: CD-HISTORY-BUILD-077-CRAZYTRACE-001
title: Build 77 CrazyTrace 2
type: history
status: draft
canonical: false
domain: build-077-crazytrace
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
supersedes: []
superseded_by:
---

# Build 77 — Crazy Black Box Pro / CrazyTrace 2.0

## 范围

Build 77 在 Build 76 的统一 `PTVehicleTwinSnapshot` 之上增加可恢复、可脱敏、可回放的车辆状态 Trace。它只复用现有 `PTVehicleTelemetryBridge`、`PTCrazyTraceReplayPlayer` 和 `PTVehicleTelemetryConsumerHub`，不创建第二套 BLE、ELM327、YMOBD、UDS 或遥测研究传输链。

营销版本保持 `2.0.8`，工程 Build 推进到 `77`。`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 未修改；ELM327 仍是 OBD 底层，YMOBD 仍是其扩展边界。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B77-01 Trace Schema V2 | ✅ | 保留 `PTCrazyTraceDocument` Schema 2，并增加车辆、Motion、GPS、事件、Marker、诊断摘要的结构化流 | 离线编码/解码；真实车辆字段仍需现场核对 |
| B77-02 Recorder | ✅ | 记录器继续作为唯一入口；统一遥测、位置、Motion、适配器和协议事件共用同一 Trace | 代码与目标编译 |
| B77-03 Ring Buffer | ✅ | 主线程 Actor 隔离的 60 秒/20,000 事件有界滚动缓冲，避免无限内存增长 | 有界逻辑测试；长时间能耗待真机 |
| B77-04 Incident Trigger | ✅ | 支持事件前最多 60 秒、事件后最多 30 秒，并生成 `incident_triggered` Marker；取消/关闭不会发送车辆指令 | 异步单元测试；真实碰撞/异常触发策略待人工接入 |
| B77-05 Reader | ✅ | Package Reader 校验路径、Checksum、Legacy Stream，并以 bounded batch 读取 Timeline | 包 round-trip 与旧结构化流缺失兼容测试 |
| B77-06 Replay Source | ✅ | 新增 `PTReplayVehicleStateSource`，复用既有 Replay Player 和统一 Telemetry Bridge | 编译；时钟/Seek 真机 UI 待补 |
| B77-07 Twin Replay | ✅ | Digital Twin 页面支持导入 `.crazytrace`，2D/3D 仍从统一 Bridge/HUB 获取回放状态 | 代码路径；真实导入交互待设备验证 |
| B77-08 Export | ✅ | 新增目录型 `.crazytrace` 导出，后台编码、临时目录原子发布、崩溃 staging 清理 | 包文件与导出测试 |
| B77-09 Privacy | ✅ | 默认导出走 `redacted`，沿用现有 Trace/Evidence 脱敏策略；保留 raw 仅供 Dev/测试调用 | 脱敏回归；真实分享渠道待设备验证 |
| B77-10 Mock Fixture | ✅ | 复用现有 Replay Fixture Catalog，并新增包含车辆、Motion、Marker 的 Build 77 回归样本 | 确定性断言与包回读 |
| B77-11 Migration | ✅ | 保留旧 flat JSON 与 Schema 2 legacy streams；结构化流可缺失时仍可回放旧包 | 旧包兼容测试；外部历史文件矩阵待补 |
| B77-12 真车验证 | 🟨 | 已准备现场检查清单，尚未把静态/Mock 结果冒充 XP400/XP400 GT 真车证据 | 需要真实 iPhone、车辆、后台和性能证据 |

## 数据包结构

```text
ride_xxx.crazytrace/
├── manifest.json
├── samples/
│   ├── vehicle.jsonl
│   ├── motion.jsonl
│   └── gps.jsonl
├── events/
│   ├── events.jsonl
│   └── markers.jsonl
├── diagnostics/
│   └── summary.json
└── legacy streams / metadata / attachments
```

旧 `timeline.jsonl` 和按域 JSONL 保留用于迁移、校验和回放；新结构化流不是第二套事实来源，而是同一事件文档的可分析投影。

## 真车验收清单

详见 [`BUILD_077_REAL_VEHICLE_VALIDATION.md`](BUILD_077_REAL_VEHICLE_VALIDATION.md)。在完成以下证据前，Build 77 不标记为现场全部通过：

- XP400/XP400 GT 实车连接后，黑匣子滚动缓冲持续记录且内存有界；
- 触发事件后导出包含前 60 秒、触发 Marker 和后 30 秒；
- iPhone 前后台、锁屏、断连、重连不改变 ELM327/YMOBD/BLE 连接顺序；
- 导入 Trace 后 2D/3D Twin 的速度、RPM、Fuel、Voltage、TCS/ABS、Lean/Pitch 与原始记录一致；
- Replay 期间没有 BLE、ELM327、YMOBD 或车辆写入命令；
- Time Profiler、Memory、Energy、Thermal 和 Release/TestFlight 包完成记录。

## 回滚

- 关闭黑匣子入口即可停止滚动采集，不影响实时车辆状态；
- 停止 Replay 后回到既有 Live Bridge；
- 若导入包异常，Reader 拒绝包并保持当前 UI 状态；
- 删除 Build 77 的 structured streams 不影响旧 Timeline 回放；
- 不回滚或修改三个稳定 BLE/OBD 核心文件来掩盖问题。

