---
doc_id: CD-HISTORY-BUILD-080-RIDE-DNA-001
title: Build 80 Ride DNA
type: history
status: draft
canonical: false
domain: build-080-ride-dna
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
  - 78
  - 79
  - 80
supersedes: []
superseded_by:
---

# Build 80 — Ride DNA

## 范围

Build 80 在现有 PTTripReport、PTRideAnalysis、CrazyTrace、道路体验和回放链路之上生成结构化 Ride DNA。它把一次骑行归纳为 Pace、Engine、Motion、Road、Efficiency 和 Coverage 六个维度，并把高转速、强冲击、最大倾角、最长怠速和粗糙路段转成回放时间线标记。

实现是只读纯计算，不新增 BLE、ELM327、YMOBD、CAN、UDS、GPS 或 Motion 传输；三个稳定核心 PTBluetoothManager.swift、PTHiddenOBDConnector.swift、PTOBDCommand.swift 保持零字节变化。营销版本仍为 2.0.8，主 App、Widget 和 Watch 的 Build 为 80。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B80-01 Feature Extractor | ✅ | 从既有行程报告提取移动/停车、速度、RPM、倾角、三轴 G、道路冲击和效率特征 | 来源字段在旧报告中未完整持久化，不能把所有信号标为真实 ECU 来源 |
| B80-02 Histogram | ✅ | RPM、倾角和 G 值分布直方图，使用稳定区间和比例 | 区间是产品分析桶，不是厂家标定或安全阈值 |
| B80-03 Coverage | ✅ | GPS、Motion、OBD、XP400 覆盖状态区分 confirmed/inferred/unavailable | OBD/XP400 在旧报告只有间接证据时显示 inferred |
| B80-04 DNA schema | ✅ | 新增 Codable/Sendable PTRideDNA 及 Pace/Engine/Motion/Road/Efficiency/Coverage 模型 | 不修改 PTTripReport schema，避免旧行程迁移风险 |
| B80-05 History comparator | ✅ | 同车、较早、至少三条有效历史行程的 DNA 指标比较 | 无车辆绑定或历史不足时明确显示不可比较 |
| B80-06 Summary UI | ✅ | 行程列表卡增加 Pace/Impact 紧凑摘要 | 仍需真机检查窄屏、本地化和长文本 |
| B80-07 Detail UI | ✅ | 既有 PTRideAnalysisViewController 增加 DNA 指标、直方图、覆盖率、历史对比和标记入口 | 仍需真机检查长列表、辅助功能和分享布局 |
| B80-08 Twin markers | ✅ | DNA marker 进入既有 PTRideReplayEvent 时间线，可从详情跳转回放 | Digital Twin/回放现场地图显示仍需真实 GPX 验证 |
| B80-09 Trace regression | ✅ | 新增纯数据测试，验证特征、来源边界、历史比较和 Codable 往返 | XCTest 已接入工程，运行环境仍需具体 Simulator/真机 |
| B80-10 Performance | ✅ | DNA 为按需纯计算，详情页在 detached task 中一次生成，列表只生成有界摘要，不新增历史数据库 | 需要 Instruments 对长轨迹、长历史和低端设备实测 |

## 数据流

~~~text
PTTripReport history
        │
        ├── PTRideAnalysisBuilder
        └── PTRideDNABuilder (pure + Sendable)
                 │
     ┌───────────┼────────────┬─────────────┐
     ▼           ▼            ▼             ▼
  list card   detail UI   JSON export   Replay / Twin markers
                 │
                 ▼
      existing PTRideReplayViewController
~~~

## 可信度边界

- confirmed 只用于报告中有明确 GPS/GPX 或 Motion 轨迹证据的来源。
- OBD RPM 和 XP400 里程来源在旧 PTTripReport 中没有逐样本 source tag，因此只在有间接证据时标记为 inferred，不伪造协议来源。
- Ride DNA 是历史数据解释层，不是 ECU 故障诊断、道路质量认证或骑行安全保证。
- Mock/Replay 的属性会随原始报告来源保留在既有链路中；本层不把模拟数据提升为实车数据。

## 验收门

代码门已完成：

- PTRideDNA.swift、回放扩展、分析页、行程列表和测试已加入 PTSpeed/PTSpeedTests；
- 多语言字符串已加入 Global/Localizable.xcstrings；
- git diff --check、JSON 语法检查和 Build80 Debug 工程编译通过；
- 现有稳定 BLE/OBD 核心文件未修改。

现场门仍待完成：

- 使用至少一条真实 XP400/XP400 GT GPX + BLE/OBD 数据完成 DNA、Coverage 和 marker 逐项核对；
- 使用 Mock、旧版 JSON、空轨迹、轨迹长度不一致和损坏/缺失 GPX 回归；
- 检查详情页滚动、窄屏、多语言、VoiceOver、分享 JSON 和回放定位；
- 用 Instruments 检查 20 条以上历史、长轨迹、前后台和低端设备的 CPU/内存；
- 完成 Release/TestFlight 验证后再把本记录状态升级为 stable。

## 回滚

- 移除 PTRideDNA 的详情入口和列表摘要即可隐藏 Build80 UI；既有行程分析和回放仍可使用。
- 不需要删除或迁移历史行程 JSON，因为 Build80 不改变 PTTripReport schema。
- 不修改 BLE、ELM327、YMOBD 或 OBD 核心来处理 DNA 展示问题。

---
