---
doc_id: CD-HISTORY-BUILD-079-ROAD-SURFACE-001
title: Build 79 Road Surface Intelligence
type: history
status: draft
canonical: false
domain: build-079-road-surface
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
  - 78
  - 79
supersedes: []
superseded_by:
---

# Build 79 — Road Surface Intelligence

## 范围

Build 79 在现有 GPS、PooTools Motion、统一 Vehicle Telemetry 和 CrazyTrace 之上增加只读道路体验层，用于识别颠簸、强冲击、减速带候选、重复振动和粗糙路段。它不新增 BLE、ELM327、YMOBD、CAN 或 UDS 传输，不向车辆发送任何指令。

营销版本保持 `2.0.8`，主 App、Widget 和 Watch 工程 Build 推进到 `79`。`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持零字节变化；ELM327 仍是 OBD 底层，YMOBD 仍是其扩展。

## 工作包状态

| 工作包 | 状态 | 实施内容 | 证据边界 |
| --- | --- | --- | --- |
| B79-01 Motion window | ✅ | 复用现有 30 Hz Motion 回调，按 0.2 秒采样并按时间、距离、样本上限切分窗口 | 纯数据测试已接入；真实手机安装姿态仍需验证 |
| B79-02 Mounted gate | ✅ | 要求 Motion 已启动、车速 3–260 km/h、GPS 精度不超过 50 m、位置新鲜且没有倾倒状态 | 不能仅凭软件断言手机固定方式正确，真车需验证 |
| B79-03 Classifier | ✅ | 计算垂向、横向和纵向冲击评分，并分类 smooth/moderate/rough/severe 与事件候选 | 阈值是产品启发式，不是厂家或道路工程结论 |
| B79-04 Dedup | ✅ | 按车辆、时间窗口、分数相似度合并重复分段和重复 Trip flush | 需要长时间多次结束行程验证 |
| B79-05 Trace regression | ✅ | 事件通过既有 CrazyTrace marker 记录；回放复用统一遥测快照重算，不新增第二套回放管线 | 固定样本测试已接入，完整 Trace 包现场待补 |
| B79-06 Route segment | ✅ | 保存车辆 UUID、时间、起止坐标、距离、样本数、速度、冲击、置信度和 synthetic 来源 | GPS 漂移、隧道和弱信号需实车验证 |
| B79-07 Map overlay | ✅ | Road Surface 页面提供 MapKit 路线折线和事件标注 | 地图网络、权限和不同地区显示需真机验证 |
| B79-08 Detail UI | ✅ | Garage 新增入口；页面展示质量、平均/峰值评分、冲击、覆盖距离、事件列表和 JSON 分享 | 多语言、布局、分享面板需真机验收 |
| B79-09 Calibration | ✅ | 停车且 Motion 活动时按车辆 UUID 保存本地 IMU 偏置和倾角零点校准 | 必须在固定手机支架上操作，不能骑行中校准 |
| B79-10 Real-road validation | 🟨 | 保留 XP400/XP400 GT、不同路面、模拟/真实来源、长时间性能和 Release/TestFlight 验收门 | 不能由 Mock、编译或日志替代现场证据 |

## 数据流

~~~text
PTMotion + PTLocationEngine + unified Telemetry / Replay
                         │
                         ▼
             PTRoadSurfaceRepository
                         │
              PTRoadSurfaceAnalyzer
                         │
             ┌───────────┼───────────┐
             ▼           ▼           ▼
        Garage UI     MapKit      CrazyTrace marker
             │                       │
             ▼                       ▼
      JSON export + iCloud       Replay re-analysis
                         │
                         ▼
                 Vehicle Twin impact hint
~~~

## 安全边界

- 所有道路体验数据均为只读分析，不改变 BLE、ELM327、YMOBD、仪表轮询、连接握手或命令队列。
- Mock/Replay 样本保留 `isSynthetic`，页面明确区分模拟与实时/历史数据。
- 校准只写入按车辆 UUID 隔离的本地 UserDefaults，不写入车辆、不上传原始传感器命令。
- 数据按 180 天和每车 2,000 个路段限制，并通过 `PTDataPersistenceActor` 原子保存本地/iCloud。
- 评分和事件名称是应用分析结果，不应被解释为道路质量认证、车辆故障诊断或安全保证。

## 验收门

在完成 [`BUILD_079_REAL_DATA_VALIDATION.md`](BUILD_079_REAL_DATA_VALIDATION.md) 前，Build 79 不标记为现场全部通过。至少需要验证：

- XP400/XP400 GT 真车连接和断连不会影响既有 BLE/OBD 轮询；
- 真实 GPS、Motion、车速和固定支架下能形成合理路段，而静止、低速、弱定位不会产生误报；
- 颠簸、减速带候选、强冲击、重复振动和正常路面在不同速度下可区分；
- CrazyTrace 录制、停止、回放和 Digital Twin 位置/冲击提示一致；
- 多车、Mock/Replay、前后台、iCloud 无网络、损坏文件和长时间内存/能耗表现稳定；
- Debug/Release/TestFlight 包和多语言页面通过验收。

## 回滚

- 移除 Garage 道路体验入口即可隐藏 UI；不会停止现有 GPS、Motion、BLE 或 OBD。
- 停止 `PTRoadSurfaceRepository` 监听即可关闭采集，既有遥测和 CrazyTrace 仍可运行。
- 删除 `PTRoadSurfaceTimeline.json` 只会删除道路体验历史，不影响车辆档案、Trip、健康时间线或原始诊断。
- 不修改或回滚三个稳定 BLE/OBD 核心文件来处理道路分析问题。

