---
doc_id: CD-ARCH-TELEMETRY-001
title: Telemetry Architecture
type: architecture
status: stable
canonical: true
domain: telemetry-architecture
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 61
  - 62
  - 66
supersedes: []
superseded_by:
---

# 统一遥测架构

## Canonical path

```text
XP400 BLE / ELM327 OBD / GPS / Motion / CrazyTrace Replay
                         ↓
              PTVehicleConnectivityCoordinator
                         ↓
               PTVehicleTelemetryBridge
                         ↓
             PTUnifiedVehicleTelemetrySnapshot
                         ↓
       PTVehicleTelemetryConsumerHub + domain projections
                         ↓
 Dashboard / Ride / Instruments / Widget / Watch / CarPlay
```

消费者不应同时从 BLE delegate、OBD manager 和 CLLocation 回调各自决定同一个显示字段。迁移中的旧 facade 可以保留兼容行为，但新 UI 只消费统一投影。

## 速度信号策略

Build 66 专门为 `.speed` 建立 `PTVehicleSpeedResolver`：

| 来源 | 最大新鲜度 | 优先级 | 规则 |
| --- | ---: | ---: | --- |
| XP400 BLE | 1.5 秒 | 400 | 实车车速首选 |
| ELM327 OBD | 2.0 秒 | 300 | XP400 无新鲜样本时回退 |
| 现有 GPS | 3.0 秒 | 200 | 复用 `PTLocationEngine/AMap`，不创建第二个定位管理器 |
| CrazyTrace Replay | 回放时钟 | 500 | 仅在显式回放期间覆盖实时来源 |

GPS 速度经过 m/s → km/h、三点中值和 EMA；合法静止值 `0` 与不可用 `nil` 分开。负值、未来时间、过期或低质量样本拒绝。当前来源仍新鲜时，高优先级新来源需要两个不同时间戳的有效样本接管；当前来源过期或移除时，低优先级新鲜来源立即接管。

## 其他信号与来源

速度以外的 RPM、温度、油量、里程、保养、转向灯、ABS、倾角、G 值和位置仍由各自已有 Resolver/Bridge 进入统一快照。每个信号应保留来源、采样时间、freshness、有效性和必要的原始值；缺失值不能伪造为零。

车库写入、Widget/iCloud、Watch application context、CarPlay 和 LiDAR 只读取已经确定的投影。Mock 和 Replay 必须明确标记为非实车来源，不得覆盖更可信且更新鲜的真实车辆数据。

## 存储与回放

Evidence 采用 SQLite 分页；CrazyTrace 使用有界 JSONL/目录包、manifest 和 checksum；CAN Capture 使用有界批次流式读取。回放与实时数据共用统一快照契约，但回放模式必须显式隔离，停止后重建实时状态，不能把历史值残留到现场车辆界面。

## 当前迁移缺口

Trip、LiDAR、Widget/Watch、CarPlay 和部分 Ride 历史仍有兼容路径。它们进入统一消费边界时，要逐信号迁移、保留回滚开关，并分别完成后台、低电量、断线和真实车辆验证；不以一次性重写取代逐步收口。

