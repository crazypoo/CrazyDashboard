---
doc_id: CD-HISTORY-BUILD-065
title: Build 65 Release Hardening
type: history
status: stable
canonical: false
domain: build-065
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 65
supersedes: []
superseded_by:
---

# PTSpeed 2.0.8 Build 65 — Swift 6 + Release Hardening

> 本文件记录 Build 65 的实施边界、代码证据、验收矩阵和真实设备缺口。它不替代产品功能总纲，也不授权任何新的车辆写入能力。
>
> EN: This file records Build 65 implementation evidence, release gates, and real-device gaps. It does not authorize new vehicle writes.
>
> ES: Este archivo registra la evidencia, las puertas de Release y las carencias de dispositivo real de Build 65. No autoriza nuevas escrituras del vehículo.

## 1. 基线与不可变边界

| 项目 | Build 65 约束 |
| --- | --- |
| Marketing Version | `2.0.8`，只递增 Build |
| 发布渠道 | `PTSpeed` TestFlight 公开版本 |
| 最低系统 | iOS 17+，watchOS 10.6+ |
| XP400 BLE 核心 | `Global/BLE/PTBluetoothManager.swift` 保持冻结 |
| ELM327/OBD 核心 | `Global/OBD/Function/PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持冻结 |
| 新增范围 | 只在协调层、纯模型、研究存储、回放、验证和 Release 门禁外围修改 |
| 危险操作 | 继续使用现有 Dev 门禁；不把 TestFlight 开发者开关误当成普通用户权限 |

三个冻结文件在本 Build 的静态门禁中必须保持零字节变化。若后续确实需要修改，必须先由用户明确申请解冻并说明会影响的协议行为、验证范围和回滚方案。

## 2. 工作包状态

| ID | 内容 | 当前状态 | 证据 |
| --- | --- | --- | --- |
| B65-01 | Strict Concurrency Ownership Matrix | ✅ | `PTBuild65Hardening.swift` 明确记录各域的唯一状态拥有者 |
| B65-02 | Sendable Audit | ✅（目标模型） | 重点遥测、Evidence、CAN、Signal、ECU、Trace 模型已有显式 `Sendable`，测试以泛型约束编译验证 |
| B65-03 | Remove unsafe MainActor leakage | ✅（已覆盖模型） | 纯错误、结果、Trace、Safety 和 Evidence DB 外围模型显式 `nonisolated`；UI Store 仍归 `@MainActor` |
| B65-04 | Staged Swift 6 migration | 🟨 | `PTSpeedTests` 已开启 Swift 6 + `SWIFT_STRICT_CONCURRENCY = complete`；主 App、Widget、Watch 仍按阶段迁移 |
| B65-05 | Background lifecycle matrix | 🟨 | 代码内有 17 项场景及不变量；需要真机逐项执行 |
| B65-06 | Long-running soak | 🟨 | 已定义 30 分钟、2 小时、4 小时协议；需 Instruments 和真机记录 |
| B65-07 | Storage stress | ✅（代码路径） | Evidence 支持有界分页；CrazyTrace JSONL 写入/读取使用有界缓冲与批次 |
| B65-08 | Crash recovery | ✅（代码路径） | SQLite 事务、Trace staging 发布、原子文件残留清理、既有 Ride/OTA checkpoint 保持 |
| B65-09 | Release safety | ✅（静态门禁） | `PTBuild65ReleaseSafetyPolicy` + 现有 `PTDeveloperSafetyGate` / OBD command gateway / OTA preflight |
| B65-10 | Privacy audit | ✅（Build65 Trace 默认路径） | Trace 默认脱敏 VIN、MAC、位置和自由文本；其他旧导出接口仍按兼容入口单独审计 |
| B65-11 | Release validation/docs | ✅ | 版本门禁、冻结核心检查、Blueprint、检查脚本、CI 和本文件同步 |

“✅（代码路径）”只表示代码和自动化检查已经覆盖，不代表真实车辆、OTA、后台或签名发布已经通过。

## 3. 并发归属矩阵

| 域 | 唯一状态拥有者 | 跨域传递规则 | 冻结 |
| --- | --- | --- | --- |
| UIKit / View Controller | `@MainActor` | 只接收不可变快照 | 否 |
| XP400 BLE Session | 既有串行归属 | 只经现有 Manager/Coordinator 投影 | 是 |
| ELM327 / OBD Session | `PTELM327Session` actor / 既有串行 lease | 只传 `Sendable` 请求、响应和结果 | 是 |
| Unified Telemetry Resolver | actor/不可变投影 | 不把 delegate 对象送入后台任务 | 否 |
| Evidence Database | SQLite 单串行 executor | 查询使用有界 page，不整库读入 | 否 |
| CrazyTrace | 主线程录制入口 + 原子持久化/有界流 | 回放通过值类型批次 | 否 |
| Instruments Provider | `@MainActor` provider registry | Provider 只返回值类型快照 | 否 |
| UI Store | `@MainActor` | 只在 UI 线程更新通知和有限历史 | 否 |

### 3.1 迁移顺序

1. `PTSpeedTests` 与纯模型。
2. Protocol Research / Evidence 数据。
3. Unified Telemetry。
4. OBD 外围 Core；不触碰冻结 ELM327 实现。
5. Instruments Provider。
6. Main App UI。
7. Widget。
8. Watch。

每一阶段须先记录 warnings、测试和编译结果，再进入下一阶段；Build 65 不使用一次性把全部 Target 改成 Swift 6 来掩盖既有遗留问题。

## 4. 存储、流式化与恢复

### 4.1 Evidence

- `PTProtocolEvidenceDatabase.records(domain:limit:offset:)` 将 page 限制为最多 10,000 条。
- 旧的 `records(domain:limit:)` API 继续读取第一页，保持 UI 兼容。
- Evidence 写入继续使用事务和 SQLite `FULL` synchronous；未更改 BLE/OBD transport。
- 大数据验证必须使用 page/offset 或逐页消费 API，禁止新增 `SELECT *` 全量数组接口。

### 4.2 CrazyTrace

- Writer 逐事件写入 JSONL，单个流使用 64KB 缓冲。
- Writer 在 sibling staging 目录完成全部文件和校验后才替换目标目录。
- 启动时清理仅匹配本地 `.tmp` 原子写入残留；Trace writer 只清理指定父目录内的隐藏 `.staging` 目录。
- Reader 保留兼容的完整 `load` API，同时提供 `streamEvents(..., batchSize:)`，回放/导出新路径不得把大型 timeline 一次性读入内存。

### 4.3 CAN Capture

- `PTCANCaptureStore.streamFrames(from:batchSize:_:)` 以 64KB 读取块和最多 4,096 帧的批次回放 JSONL。
- `loadJSONL` 改为复用该流式读取路径；兼容 API 仍返回完整 `PTCANCaptureSession`，但不再额外把整个文件复制成 `Data`/`String`。
- 单行损坏会被跳过，超出 1MB 的无界行会明确返回 `invalidCapture`，避免异常文件造成无限内存增长。

### 4.4 崩溃恢复边界

| 数据 | 保护策略 | 恢复判断 |
| --- | --- | --- |
| Trace package | staging + manifest 最后写入 + checksum | 只接受完整目标包；孤儿 staging 可清理 |
| Evidence DB | SQLite 事务 + FULL synchronous | 重开后 schema/记录可读，未提交事务不出现 |
| Ride | 既有 checkpoint/journal | 从最后提交点恢复，不重复车辆命令 |
| OTA | 既有 checkpoint/state machine | 只恢复状态，不绕过开发者 preflight |
| CAN Capture | 现有 JSONL/Session 恢复路径 | 异常退出后保留可解析部分和明确丢失计数 |

## 5. Release 安全与隐私

### 5.1 Release 默认策略

`PTBuild65ReleaseSafetyPolicy.publicReleaseDefault` 必须满足：

- Dev 危险入口默认隐藏。
- 未知 UDS mutation 禁止。
- 固件研究只读。
- CAN injection 禁止。
- SecurityAccess 自动化禁止。
- Jieli OTA 仅允许识别为 YMOBD 的适配器。

现有 TestFlight Dev 操作仍需显式打开 `PTDeveloperSafetyGate`，并继续受既有 command gateway、OTA preflight 和生命周期撤销控制。Build 65 不删除该开发者测试通道，也不把它暴露给普通用户入口。

### 5.2 默认脱敏字段

新建的 Build 65 Trace 发布路径默认裁剪：VIN、MAC、精确停车/家庭位置、联系人、PTT 音频和通知文本。自由文本以 `<redacted-text>` 替代；协议文本中的 VIN token 也会脱敏后再计算 checksum。

任何新的导出字段必须先经过 `PTBuild65PrivacyPolicy.isSensitiveKey` 判断。真实研究需要保留敏感数据时，必须是开发者明确选择的本地内部导出，并在 UI 上标注未脱敏。

## 6. 真机与长时间验证矩阵

以下是验收记录模板，不把静态代码检查当成设备结果：

| 场景 | 时长/动作 | 观察项 | 通过条件 | 结果 |
| --- | --- | --- | --- | --- |
| XP400 BLE only | connect/auth/telemetry/credits/navigation/disconnect/reconnect | 内存、回调、重连、后台 | 无重复 owner、无错误停止 | ⬜ |
| OBD only | BLE adapter/Wi-Fi/YMOBD/generic ELM/PID/DTC/UDS/CAN | lease、超时、断开恢复 | lease 在成功/取消/断开后归还 | ⬜ |
| XP400 + YMOBD | 并存 30 分钟以上 | 两条链路相互影响 | OTA 不错误停止 XP400 BLE | ⬜ |
| Background / locked | 进入后台、锁屏、恢复前台 | 任务、Live Activity、数据 freshness | 不假设 UI 仍可执行 | ⬜ |
| Network/Bluetooth off-on | 各切换 3 次 | 本地数据、重连、错误 | 不重复订阅、不丢 committed 数据 | ⬜ |
| Low Power / thermal / memory warning | 系统压力期间 | 采样、队列、历史 | 采样可降级，文件不损坏 | ⬜ |
| Trace soak | 30m / 2h / 4h | CPU、内存、热、电量、文件增长 | 无明显泄漏、文件可读 | ⬜ |
| Storage stress | 100k Evidence / 1M CAN / 4h Trace / 1000 rides | page、磁盘、恢复 | 不整库读入内存，重开可读 | ⬜ |

### 6.1 记录格式

每次真机/实车执行至少记录：设备型号、iOS 版本、App Build、适配器型号、车辆状态、开始/结束时间、内存峰值、CPU/thermal、电量变化、重连次数、队列深度、文件/数据库大小、结果和日志位置。

## 7. Golden Fixture 与 Fuzz 规则

所有解析器必须保持纯、有限和无副作用。Build 65 语料覆盖：

- 空输入、截断输入、超大输入。
- 非 UTF-8、非法 Hex、重复记录、乱序记录、未知 schema。
- XP400 BLE envelope validator。
- ELM327 prompt parser。
- UDS DID read result parser。
- CAN Capture JSON decoder。
- CrazyTrace event stream reader。
- Evidence persisted-state decoder。

每个语料的验收条件：不崩溃、不无限循环、不发送车辆命令、不修改持久化状态。真实协议新增样本必须先保存为 Golden Fixture，标注来源（live/mock/replay/imported）、时间、设备、车型和是否经过人工确认。

## 8. 验证入口

本地静态和工程检查：

```text
./Scripts/build65_checks.sh
```

版本/工程单独检查：

```text
./Scripts/validate_project_versions.sh 65 2.0.8
plutil -lint CrazyDashboard.xcodeproj/project.pbxproj
git diff --check
```

已知环境限制：当前 Xcode/Pods 环境可能出现 SmartCodable 宏插件网络拉取、arm64 Simulator 排除或 Watch App 资源被错误按 iOS SDK 处理等问题。遇到这类错误时必须保留完整日志，并分别报告“代码解析/纯测试”“目标编译”“模拟器 XCTest”“真机/实车”四类证据。

## 9. 回滚方案

- 版本回滚：恢复 `CURRENT_PROJECT_VERSION` 到上一 Build，同时保持 `MARKETING_VERSION = 2.0.8`。
- 代码回滚：只回滚 Build 65 外围文件；三个冻结核心不需要回滚。
- Trace：保留旧 flat JSON 兼容 API；新目录包失败时不替换旧目标目录。
- Evidence：数据库迁移失败时继续使用既有兼容 fallback，不删除旧 UserDefaults blob。
- Safety：任何 Release 门禁不通过时，关闭新增入口，不放宽既有 Dev gate。

## 10. Definition of Done

Build 65 只有在以下证据齐全后才能标记“发布级完成”：

- Swift 6 staged target 编译成功，strict concurrency blocker 清零。
- Main App、Widget、Watch、Tests 目标分别有明确编译证据。
- Core Replay、Evidence、Trace、Fuzz 纯测试通过。
- 4 小时 soak 无明显泄漏，存储压力场景可恢复。
- OTA 真机闭环和 XP400 + YMOBD 并存由真实设备记录确认。
- Release Safety Gate 和隐私导出审计通过。
- [`../../product/APP_FEATURE_BLUEPRINT.md`](../../product/APP_FEATURE_BLUEPRINT.md)、版本门禁、脚本和 CI 与代码同步。

截至当前工作区，Build 65 的外围代码、静态门禁和自动化测试已接入；真机/实车/OTA/签名发布验收仍为未完成证据，不在本文件中虚标为通过。
