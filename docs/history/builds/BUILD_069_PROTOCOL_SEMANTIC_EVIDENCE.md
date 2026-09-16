---
doc_id: CD-HISTORY-BUILD-069-001
title: Build 69 Protocol Semantic Evidence Intelligence
type: history
status: stable
canonical: false
domain: build-069
owner: Jax
created: 2026-09-17
last_reviewed: 2026-09-17
related_builds:
  - 69
supersedes: []
superseded_by: []
---

# Build 69 — Protocol Semantic Evidence Intelligence

## 版本定位

Build 69（营销版本仍为 `2.0.8`）把 XP400 BLE 原始帧、ELM327/OBD-II/UDS 响应和跨源遥测从“原始日志 + 人工观察”推进到“语义投影 + 证据归约 + 历史回放”。本版本只增加外围解析、研究、存储和 Dev 可视化能力，不替换稳定传输层。

Build 69 keeps the ELM327 transport, YMOBD extension boundary, CoreBluetooth BLE server, command queue, framing, authentication, polling and standard decoders intact. The new layer is read-only and evidence-first.

La nueva capa es de solo lectura y prioriza la evidencia; mantiene intactos el transporte ELM327, la extensión YMOBD, el servidor BLE CoreBluetooth, la cola de comandos, el entramado, la autenticación, el sondeo y los decodificadores estándar.

## 已实现范围

### XP400 语义与时间

- `PTXP400SemanticEvidence.swift` 提供统一 Schema、字段角色、`available/unavailable`、质量等级、raw Payload 和 Frame Inspector。
- Connection Frame 保持 15 bytes；`0x02–0x06` 车辆状态帧统一为 11 bytes、8-byte Payload。
- Data2 的前三个 Payload byte 按 `second = B0 >> 2`、`minute = B1 >> 2`、`hour = B2 >> 3` 解码；低位保留为 raw/candidate。
- Control TCS mode 从低半字节读取，Ready 从完整 byte3 的 bit7 保留为 candidate；byte0 使用模 256 rolling tick 锚点。
- ABS 前轮速度与 byte2 原始状态分离，bytes 3…7 的全 `FF` 识别为 sentinel/padding；未知位不生成正式业务值。

### Discovery 与证据智能

- TX `01` 先归类为已知 status poll；周期、clock、counter、sentinel、已知语义、candidate 和 anomaly 分开统计。
- 合法认证/TIO 非包络分片不再误报为坏包；未知帧仍保存完整 raw 和 fingerprint。
- `PTBuild69SemanticIntelligenceActor` 通过 baseline、marker correlation、repeatability、cross-source agreement、variability 和 rarity 生成 candidate score；candidate 不会变成可执行命令。
- `PTBuild69EvidenceStore` 保存有界结果和 marker；Dev Protocol Evidence 页面按语义、临时字段、计数/时钟、candidate、sentinel、anomaly 分组并提供 Frame Inspector。

### ELM327 / OBD-II / UDS

- `PTBuild69ELMNormalizer` 只处理 ELM 状态行、Echo、Header、可选 DLC、ISO-TP PCI 和多帧拼接。
- `PTBuild69OBD2Parser` 处理 `02/03/07/0A` 以及标准 Mode response relation；`PTBuild69UDSParser` 处理 `62`、`7F` 和 NRC。
- `03/07/0A` 分别映射 Stored/Pending/Permanent DTC；Mode `02` 不再误报为 UDS。
- `NO DATA`、超时、无效响应和合法零值分开保存；`011F = 0` 不单独伪造 `engineStartedAt`。

### Passport、跨源与回放

- Passport reducer 只从显式身份域 evidence 填充 Connectivity Box、Dashboard、Engine ECU 和 OBD Adapter，避免把连接中心标识冒充仪表身份。
- BLE、OBD、GPS、Motion 通过统一 Observation 适配器保留 source、key、墙钟、单调时钟、质量、可用性和 raw value；Correlation 只输出统计关系，不确认协议语义。
- Evidence schema v3 增加字段角色、原始/归一化值、可用性、质量、置信度、marker 距离、tick、单调时间和 correlation；v2 可迁移且不会把历史 unknown 自动晋级为 confirmed。
- `PTBuild69ReplayAnalyzer` 支持 MotoHex 语义回放；`PTBuild69HistoricalReplayAnalyzer` 支持既有 Discovery JSONL 和 Evidence v2 重新分类，输入大小和保留帧数有上限。

## 代码边界

新增/修改集中在外围语义、证据、OBD parser、Dev UI 和测试文件。以下文件保持冻结、无本 Build 变更：

- `Global/BLE/PTBluetoothManager.swift`
- `Global/OBD/Function/PTHiddenOBDConnector.swift`
- `Global/OBD/Function/PTOBDCommand.swift`

ELM327 仍是 OBD 的底层连接；YMOBD 只是识别后的扩展能力。本 Build 不加入 ECU 写入、SecurityAccess、RoutineControl、固件刷写、任意 CAN 注入或 ID 7 主动探针。

## 验证证据

| 项目 | 结果 |
| --- | --- |
| 版本 | `MARKETING_VERSION = 2.0.8`，所有工程 Target 为 `CURRENT_PROJECT_VERSION = 69` |
| Swift 解析 | Build 69 纯语义、OBD 分层、智能分析、回放和测试源码通过 Swift 6 `swiftc -parse` |
| iOS 编译 | `PTSpeed` Debug generic `build-for-testing` 通过，日志包含 `** TEST BUILD SUCCEEDED **` |
| 保护边界 | 三个稳定 BLE/OBD 核心文件未修改 |
| 自动化测试源码 | 覆盖 RTC、TCS、tick、ABS/sentinel、TX `01`、OBD/UDS、多帧、可用性、Passport、关联和历史回放规则 |
| Simulator XCTest | 当前 Scheme 只提供通用 iOS 设备/通用模拟器 destination，未执行具体 Simulator XCTest |
| 真机/实车 | MotoHex、Discovery、Evidence 样本和 XP400GT/ELM327/YMOBD 现场验收仍需按 Active Work 手工完成 |

静态解析、目标编译和纯数据测试源码不等价于真实车辆行为；外部样本只有在回放器实际执行后，才能把候选率和字段结果写成已复现证据。

## 回滚与后续

Build 69 证据接入位于现有 Dev/Protocol Evidence 路径；出现兼容性问题时可以停止新的 evidence ingest、历史 re-analysis 或 Dev 展示，不影响标准 BLE、ELM327、YMOBD、导航和普通车辆状态路径。未知字段继续保留 raw，待真实 A/B/A 采样和多会话重复后再提升证据等级。
