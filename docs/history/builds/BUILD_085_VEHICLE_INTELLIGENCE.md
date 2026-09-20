---
doc_id: CD-HISTORY-BUILD-085-VEHICLE-INTELLIGENCE-001
title: Build 85 Vehicle Intelligence
type: history
status: draft
canonical: false
domain: build-085-vehicle-intelligence
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 78
  - 79
  - 80
  - 82
  - 84
  - 85
supersedes: []
superseded_by:
---

# Build 85 — Vehicle Intelligence

## 范围

Build 85 将已经成熟的只读车辆数据转换为可解释的 Vehicle Intelligence 摘要，并把摘要接入 XP400 Digital Twin 停车页。它不是 ECU 诊断替代品，也不改变车辆通信链路。

```text
Health / Ride DNA / Road Surface / Trip / DTC / Maintenance
                              +
                 confirmed XP400 semantic state
                              ↓
                 PTVehicleIntelligenceAnalyzer
                              ↓
               evidence-backed summary + review
                              ↓
       Vehicle Twin UI / guarded notification policy
```

明确禁止进入正式洞察层的数据：

- Unknown Candidate。
- Probable Protocol Field。
- Raw Hex Guess。
- Mock、Replay 或 synthetic 数据作为真实故障证据。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 验收边界 |
| --- | --- | --- | --- |
| B85-01 | ✅ | `PTVehicleIntelligenceSeverity`、Source、Quality、Insight、Summary、Review 和 Input Schema | Codable、Equatable、Sendable；分析模型无传输副作用 |
| B85-02 | ✅ | 每条洞察附 source、time window、sample count、quality 和 evidence note | evidence 必须来自成熟结构化数据 |
| B85-03 | ✅ | 六次真实启动/静置电压的非递增趋势与低电压观察规则 | 至少六个真实样本才允许趋势；synthetic 不可通知 |
| B85-04 | ✅ | 真实怠速 RPM baseline | 仅描述观察，不宣称工厂故障阈值 |
| B85-05 | ✅ | confirmed、pending、permanent DTC 分层 | confirmed 为 critical，pending/permanent 为 attention；复用既有结构化 DTC |
| B85-06 | ✅ | 最近 Trip、Ride DNA 和高强度 marker 摘要 | 只做骑行描述，不升级为机械故障 |
| B85-07 | ✅ | Road Surface rough/severe/impact 摘要 | 只做道路体验描述，不升级为车辆故障 |
| B85-08 | ✅ | 车辆 ID 维度 dedup，Ride/Road 按事件时间 24 小时 expiry | 重新计算不会延长旧事件生命周期 |
| B85-09 | ✅ | Twin 停车页显示 Vehicle Summary、状态、evidence count 和摘要明细 | 不替换实时指标，不新增导航或连接入口 |
| B85-10 | ✅ | Twin insight adapter 使用现有 Snapshot/semantic projection | 只提供定位信息，不制作故障动画 |
| B85-11 | ✅ | 受保护通知策略与现有 `PTNotificationCenter` 对接 | 仅 confirmed/observed、非 synthetic、可操作且非 maintenance |
| B85-12 | ✅ | false-positive review、抑制 ID 和证据质量门 | 记录不足样本、synthetic、probable 和 unconfirmed suppression |

## 代码实现

### 1. 纯规则分析层

`Global/Global/PTVehicleIntelligence.swift` 提供非隔离、可测试的 `PTVehicleIntelligenceAnalyzer`。它先按车辆 UUID 过滤，再分离真实与 synthetic 数据，生成电池、发动机、诊断、保养、行程、道路和已确认 ABS 洞察。每条结果都保留：

- `source`：health、rideDNA、roadSurface、trip、diagnostic、maintenance 或 confirmedSemanticState；
- `windowStart/windowEnd`；
- `sampleCount`；
- `quality`：confirmed、observed、inferred、insufficient 或 syntheticExcluded；
- evidence note、生成时间、过期时间和是否可操作。

`PTVehicleIntelligenceRepository` 是 `@MainActor` 的快照协调器，只监听既有仓库通知并做 250 ms 防抖；它不启动 BLE/OBD 连接、不改变轮询、不读取原始帧，也不进入写入、OTA、SecurityAccess 或 YMOBD 扩展路径。

### 2. Digital Twin 与通知

`PTVehicleTwinIntelligenceAdapter` 将摘要裁剪为最多五条只读展示洞察、evidence count 和保养剩余里程，再由 `PTVehicleTwinViewController` 在既有 `PTMotoBaseViewController` 页面中显示。摘要不会覆盖车速、RPM、TCS、ABS 或导航安全状态；confirmed ABS 只作为定位提示，不播放“故障动画”。

通知使用 `PTVehicleIntelligenceNotificationPolicy` 过滤后交给 `PTNotificationCenter`，沿用既有权限、24 小时 cooldown、deduplication key 和用户关闭通知后的行为。保养通知继续由现有维护模块负责，避免重复提醒。

### 3. 本地化与测试

`Global/Localizable.xcstrings` 新增 Vehicle Intelligence 的摘要、状态、证据和 ABS 文案，并覆盖当前项目的十种语言。`PTSpeedTests/PTVehicleIntelligenceBuild85Tests.swift` 覆盖：

- 六个真实启动样本形成电压趋势；
- synthetic 电压不会变成可通知洞察；
- confirmed/pending DTC 严重级别；
- 车库保养不产生重复通知；
- Road Surface 只是 inferred 描述；
- 只有 fresh、非 synthetic、XP400 BLE ABS 才进入语义摘要；
- 旧 Ride/Road 证据过期后不会被复用。

## 版本与冻结边界

- `MARKETING_VERSION` 保持 `2.0.8`。
- 主 App、Widget、Watch 的 `CURRENT_PROJECT_VERSION` 为 `85`；Tests/UI Tests 保持既有测试版本。
- `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持零字节变化。
- ELM327 仍是 OBD 底层，YMOBD 仍是 ELM327 扩展；连接、初始化、握手、能力识别、命令顺序、轮询和 fallback 没有修改。
- Build 85 没有新增 ECU 写入、CAN 注入、SecurityAccess、OTA 或固件刷写路径。

## 静态与构建证据

已完成：

- `git diff --check`。
- `Global/Localizable.xcstrings` JSON 校验。
- 主 App workspace Debug generic iOS `build`。
- 主 App workspace Debug generic iOS `build-for-testing`。
- Build85 纯逻辑 XCTest 已加入 `PTSpeedTests` 编译目标。
- 项目文件已登记新源文件、测试文件和 Build 85 版本号。

稳定核心 SHA-256 应保持既有基线：

| 文件 | SHA-256 |
| --- | --- |
| `Global/BLE/PTBluetoothManager.swift` | `841abfbab70f6c199c3130b68c8f55f42104684e6f6ea39a11ad3215c7b676e4` |
| `Global/OBD/Function/PTHiddenOBDConnector.swift` | `21a3657de6c7bfd4ac4e40883fc14ec45aabed168376629e15a2e2573a4632d1` |
| `Global/OBD/Function/PTOBDCommand.swift` | `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66` |

## 尚需人工验收

静态构建和纯规则测试不能替代车辆现场证据，以下仍保持 `🟨`：

- 真实 XP400/XP400 GT 的六次启动电压趋势与电压来源核对；
- 真车 confirmed/pending/permanent DTC、断连和过期诊断快照；
- 真实车库保养里程、行程、Road Surface 和多车辆隔离；
- 通知权限拒绝、允许、冷却、重复事件、前后台和 TestFlight 行为；
- Twin 在窄屏、长摘要、多语言、断连和高频遥测下的布局与性能；
- Time Profiler、Allocations、Energy、thermal 和长时间稳定性；
- Release/归档包和真实 iPhone/车辆安装验证。

## 回滚

回滚只需移除 Vehicle Intelligence 源文件、测试文件、Twin 摘要区域、本地化键和 Build85 文档登记。不会删除 Health、Trip、Road Surface、DTC、Garage、CrazyTrace、Twin 或任何车辆历史，也不需要迁移 BLE、ELM327、YMOBD 或 OBD 数据。
