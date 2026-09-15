---
doc_id: CD-HISTORY-BUILD-066
title: Build 66 GPS Speed Fallback
type: history
status: stable
canonical: false
domain: build-066
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 66
supersedes: []
superseded_by:
---

# PTSpeed 2.0.8 Build 66 — GPS Speed Fallback 实施记录

> English: This file records the implementation and validation boundary for Build 66.
>
> Español: Este archivo registra la implementación y los límites de validación de Build 66.
>
> 中文：本文件记录 Build 66 的实施内容和验证边界。

## 1. 版本与安全边界

| 项目 | 当前值 |
| --- | --- |
| Marketing Version | `2.0.8` |
| Build | `66` |
| 最低系统 | iOS 17.0+ |
| 核心范围 | XP400 / ELM327 OBD / GPS / CrazyTrace Replay 的只读车速仲裁 |
| 危险能力 | 不新增写入、SecurityAccess、CAN Injection、ECU 刷写或固件修改 |

以下稳定传输文件在本 Build 必须保持零字节变化：

```text
Global/BLE/PTBluetoothManager.swift
Global/OBD/Function/PTHiddenOBDConnector.swift
Global/OBD/Function/PTOBDCommand.swift
```

## 2. 已落地的架构

所有车速先进入 `PTVehicleTelemetryBridge` 的专用路径：

```text
XP400 BLE ─┐
ELM327 OBD ├─> PTVehicleSpeedResolver ─> Unified Snapshot ─> Consumer Hub ─> UI
现有 GPS ──┤
Replay ────┘
```

`PTGPSSpeedProvider` 只消费现有 `PTLocationEngine / AMap` 产生的 `CLLocation`，不启动新的定位管理器。其他遥测信号继续由原有 `PTVehicleTelemetryResolver` 处理。

### 2.1 车速策略

| 来源 | 最大新鲜度 | 优先级 | 说明 |
| --- | ---: | ---: | --- |
| XP400 | 1.5 秒 | 400 | 优先使用原车仪表车速 |
| ELM327 OBD | 2.0 秒 | 300 | XP400 无新鲜车速时回退 |
| GPS | 3.0 秒 | 200 | 水平精度不超过 30m，速度精度不超过 3m/s（未知精度允许） |
| Replay | 回放时钟 | 500 | 仅在显式回放模式覆盖实时来源 |

GPS 车速经过 m/s → km/h、3 点中值和 EMA（`alpha = 0.45`）处理；低于 `2 km/h` 的 GPS 平滑值钳制为合法 `0 km/h`。负速度、未来时间戳、过期样本和低精度样本保持不可用，不会伪造为零。

新优先级来源必须连续两个不同时间戳的有效新鲜样本才能接管当前仍新鲜的来源；当前来源过期或被移除时，较低优先级的新鲜来源立即接管。

## 3. 文件变更

### 新增

- `Global/Global/PTVehicleSpeedResolver.swift`：速度领域模型、策略、候选缓存、优先级、freshness、hysteresis 和诊断。
- `Global/Global/PTGPSSpeedProvider.swift`：GPS 速度质量门禁、平滑和诊断。
- `Global/Global/PTBuild66FeatureFlags.swift`：仅供开发验证的 GPS fallback 开关，默认开启，不暴露给普通用户。
- `PTSpeedTests/PTVehicleSpeedResolverTests.swift`：优先级、回退、接管、Replay 和 `0/nil` 测试。
- `PTSpeedTests/PTGPSSpeedProviderTests.swift`：GPS 校验、换算、平滑、静止和精度测试。
- `PTSpeedTests/PTBuild66SpeedIntegrationTests.swift`：CrazyTrace 零速保留和旧 Instruments 快照兼容测试。

### 修改

- `Global/Global/PTVehicleTelemetryBridge.swift`：接入专用车速 Resolver；保留非速度信号旧路径；回放时显式覆盖；断开时清理对应来源。
- `Global/Dashboard/Views/PTDashBoardView.swift`：只从统一 Dashboard Projection 渲染车速，定位回调仅负责航向和环境。
- `Global/Dashboard/ViewController/PTPeugeotDashBoardViewController.swift`：改用统一 Consumer Hub，RPM/温度等未迁移字段保留兼容回调。
- `Global/PTMotoInfoViewController.swift`：旧首页的 BLE/OBD 直接写速路径收口到统一 Consumer Hub，避免同一界面多来源竞争。
- `Global/Dev/PTCrazyDashboardInstruments.swift`、`PTInstrumentArchitecture.swift`、`PTCrazyDashboardInstrumentsViewController.swift`：加入来源、年龄、质量、回退原因、接管计数和 GPS 原始/过滤值。
- `CrazyDashboard.xcodeproj/project.pbxproj`：所有 Target Build 对齐到 66，新增文件和测试纳入工程。
- [`../../product/APP_FEATURE_BLUEPRINT.md`](../../product/APP_FEATURE_BLUEPRINT.md)、[`../../architecture/TELEMETRY_ARCHITECTURE.md`](../../architecture/TELEMETRY_ARCHITECTURE.md)：同步 Build 66 架构和验证状态。

## 4. 验收状态

### 已完成的静态/离线门禁

- [x] Marketing Version 保持 `2.0.8`。
- [x] 主 App、Widget、Watch、Tests、UI Tests 的 Build 对齐 `66`。
- [x] 三个冻结 BLE/OBD 核心文件无工作区或暂存区差异。
- [x] 没有新增 `CLLocationManager` 或 `AMapLocationManager`；GPS 复用现有位置引擎。
- [x] Main Dashboard、Peugeot Dashboard、`PTMotoInfoViewController` 不再直接仲裁 OBD/BLE/GPS 车速。
- [x] Swift 6 纯模型和 Provider 解析通过。
- [x] Debug `build-for-testing` 通过。
- [x] 旧 Instruments JSON 缺少 `speed` 字段时可以按默认诊断值解码。
- [x] CrazyTrace 的合法 `0 km/h` 保留为零，不与缺失值混淆。

### 尚需真实设备/车辆验证

以下不能由模拟器、静态检查或工程编译替代，完成前保持 🟨：

- [ ] iPhone GPS-only 前台道路测试。
- [ ] GPS → OBD：OBD 连上并连续回传后，车速稳定切换到 OBD。
- [ ] OBD → GPS：停止 OBD 车速回传后，过期回退到 GPS。
- [ ] OBD → XP400：XP400 连上后，连续两个新鲜样本接管。
- [ ] XP400 断开后的即时回退。
- [ ] 前后台切换、定位权限变化、低电量模式和弱 GPS 信号观察。
- [ ] Dashboard 与 Peugeot Dashboard 实车显示无 `0 → -- → speed` 异常跳变。
- [ ] Release 签名包安装及真实配对设备验证。

## 5. 推荐真实测试步骤

1. 在 Developer Instruments 打开 Unified Speed 面板，确认 `resolved source`、`age`、`reason` 和 GPS quality 可见。
2. 只启动现有定位能力，确认 `GPS` 候选有效；检查停车/静止时显示 `0 km/h` 而不是 `unavailable`。
3. 连接 ELM327，确认先经历 `higherPriorityPending`，第二个不同时间戳有效样本后变为 `obd`。
4. 停止 OBD 车速回传，等待超过 2 秒，确认 `fallbackAfterStale` 并切到 GPS。
5. 在 OBD 保持在线时连接 XP400，确认两个新鲜 XP400 样本后切换到 `xp400`。
6. 断开 XP400，确认不会保留旧速度，且 OBD/GPS 可按 freshness 规则接管。
7. 启动 CrazyTrace Replay，确认 Replay 速度覆盖实时 GPS；停止回放后检查实时状态重建。

测试中不要通过本版本发送车辆写入命令，也不要把 GPS 速度当作 ECU 或 CAN 证据。

## 6. 回滚

开发验证期间如 GPS 质量或道路表现不符合预期，可在 MainActor 上关闭：

```swift
PTBuild66FeatureFlags.gpsSpeedFallbackEnabled = false
```

该开关只停止 GPS 速度候选，不停止定位、航向或环境数据，也不改变 XP400、ELM327、YMOBD 和 Jieli 传输逻辑。长期维护时应修正策略参数或删除开关，不保留两套业务路径。

## 7. 结论

Build 66 的代码和工程静态部分已完成；真实 iPhone、GPS、OBD、XP400、前后台和低电量验证仍由设备测试完成后再把 Blueprint 的 B66-13 标记为 `✅`。当前实现不代表真实车辆协议或道路表现已经验收。
