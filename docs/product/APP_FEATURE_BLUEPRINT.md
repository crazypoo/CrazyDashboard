---
doc_id: CD-PRODUCT-001
title: APP Feature Blueprint
type: product
status: active
canonical: true
domain: product
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-20
related_builds:
  - 66
  - 67
  - 68
  - 69
  - 77
supersedes: []
superseded_by:
---

# XP400 Ride / PTSpeed APP 功能总纲

> 本文件是项目功能、入口、平台覆盖和完成状态的唯一事实源（Single Source of Truth）。
>
> 快照日期：2026-09-20
>
> 仓库基线：当前工作区已进入 Build 69 Protocol Semantic Evidence Intelligence；Build 57–68 的 OBD、统一遥测、Instruments、Evidence/CAN/Passport、持久化、CrazyTrace 回放、协议研究、XP400 电子身份、Swift 6 Release Hardening、统一车速、仪表协议纠偏和 OBD 深诊断能力继续保留，Build 69 的语义证据、跨源关联和历史回放已接入，真实设备、车辆、OTA 和完整发布验证仍待补
>
> 发布版本：`MARKETING_VERSION = 2.0.8`，主 App / Widget / Watch `CURRENT_PROJECT_VERSION = 77`；Tests / UI Tests 保持各自测试版本
>
> 最低系统：iOS 17.0+，watchOS 10.6+
>
> 发布渠道：仅维护 `PTSpeed` TestFlight 公开版本，不建立第二套 App、Scheme 或 Bundle ID。

## 1. 文档职责

本总纲用于回答以下问题：

- App 当前有什么功能，用户从哪里进入。
- 功能运行在哪个平台，依赖哪一条数据链路。
- 功能已经可用、仍需真机验证、仅限开发者，还是只处于计划阶段。
- 新增、修改、隐藏或删除功能时，需要同步更新哪些记录。

本文件不代替实施记录。当前未完成工作、实施证据、验证缺口与回滚方法统一记录在 [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md) 和 [`../history/BUILD_HISTORY_2026.md`](../history/BUILD_HISTORY_2026.md)；本文件只维护“当前产品是什么”。当两者不一致时，以当前代码和本文件最近一次核验结果为准。

## 2. 状态与维护规则

### 2.1 状态定义

| 状态 | 含义 |
| --- | --- |
| ✅ 可用 | 当前代码已接入正式入口，核心流程可以使用 |
| 🟨 部分完成 | 已有实现，但仍缺完整 UI、异常恢复、硬件或真实道路验证 |
| 🧪 开发者实验 | 只允许从 Dev 模块显式开启，不属于普通用户能力 |
| ⬜ 计划 | 尚未形成可交付闭环，不能在宣传或 UI 中视为已完成 |
| 🗑️ 已退役 | 已从产品移除；保留记录，功能 ID 永不复用 |

### 2.2 功能 ID

| 前缀 | 范围 |
| --- | --- |
| `CORE` | 连接、基础运行、设置与通用能力 |
| `DASH` | 主仪表、专业仪表与骑行数据显示 |
| `NAV` | 地图、导航、停车与路线 |
| `RIDE` | 行程、回顾、安全、维护与故事 |
| `PTT` | 车队对讲、成员状态与 PTT Live Activity |
| `OBD` | 标准诊断、UDS、CAN 与离线回放 |
| `SYS` | Widget、Watch、Siri、Live Activity、CarPlay 与系统集成 |
| `DEV` | 开发者工具和高风险实验能力 |
| `IDEA` | 候选功能，不承诺交付时间 |

规则：

1. 功能 ID 创建后不得改名或复用。
2. 删除功能时改为 `🗑️ 已退役`，不得直接抹去历史。
3. 功能状态、入口、支持平台或数据来源变化时，必须在同一次提交中更新本文件。
4. 只有完成对应验证后才能把 `🟨`、`🧪` 或 `⬜` 改为 `✅`。
5. 静态检查、单元测试、目标编译、真机/实车验证必须分别记录，不得互相替代。

### 2.3 验证层级

| 层级 | 说明 |
| --- | --- |
| 静态 | 代码路径、配置、资源、调用关系和危险命令边界已检查 |
| 测试 | 纯逻辑或 Mock 场景已有可重复测试 |
| 编译 | 涉及的 App / Widget / Watch / Tests target 可以完整编译 |
| 真机 | 已在真实 iPhone、Apple Watch、OBD 适配器或 XP400 上完成场景验证 |

## 3. 产品入口与运行平台

### 3.1 工程 Target

| Target | Bundle ID | 作用 |
| --- | --- | --- |
| `PTSpeed` | `com.yd.PTSpeed` | iPhone 主 App、蓝牙、导航、行程、PTT、OBD 与系统协调 |
| `xp400WidgetExtension` | `com.yd.PTSpeed.xp400Widget` | 展示车辆连接、油量、里程与停车状态 |
| `xp400watch Watch App` | `com.yd.PTSpeed.watchkitapp` | 展示由 iPhone 同步的最近车辆状态 |
| `PTSpeedTests` | `com.yd.PTSpeedTests` | 纯逻辑、兼容性和回归测试 |

### 3.2 主入口

| 一级入口 | 当前内容 |
| --- | --- |
| 机车 | XP400 连接状态、车辆概览、普通仪表、标致风格仪表、骑行中心 |
| 导航 | 高德地图、地点搜索、路线规划、实时导航、停车位置与车友位置 |
| 数据 | OBD 实时数据、故障码、ECU 信息、诊断与 CAN 工具入口 |
| PTT | 车队发现、按键对讲、免提/VOX、成员状态与 Live Activity |
| 设置 | 连接、语言、仪表偏好、快捷指令说明、版本信息与开发者入口 |

补充入口：

- 四指手势进入 Dev 工具，仅供 TestFlight 开发测试。
- Siri / App Intents 和 URL Scheme 提供系统快捷入口。
- Widget、Apple Watch、Live Activity 和 CarPlay 提供主 App 之外的只读或导航展示。

## 4. 核心架构与不可破坏边界

```text
XP400 原车 BLE
  PTBluetoothManager
      -> PTBluetoothServerManager
      -> 仪表 / 行程 / 安全 / 连接协调

OBD BLE / Wi-Fi / Mock
  PTHiddenOBDConnector + PTOBDCommand
      -> PTMotoTelemetryManager
      -> 标准 PID / DTC / UDS 只读 / CAN 工具

位置与高德地图
  PTLocationEngine / AMap
      -> 导航 / 行程 / 停车 / Widget / iCloud / Watch / CarPlay

车队对讲
  PTT 会话与音频
      -> PTT UI / 成员状态 / 地图位置 / Live Activity
```

### 4.1 受保护核心

以下文件已经是稳定核心，普通优化、UI 改造和功能扩展不得直接修改其内部逻辑：

- `Global/BLE/PTBluetoothManager.swift`
- `Global/OBD/Function/PTHiddenOBDConnector.swift`
- `Global/OBD/Function/PTOBDCommand.swift`

约束：

1. 新需求优先通过现有公开 API、协调层、适配器或外围服务实现。
2. BLE 与 OBD 虽然都使用 CoreBluetooth，但不能直接合并稳定文件；后续只允许抽取外围的扫描仲裁、状态聚合和总线占用策略。
3. 如确实需要修改受保护核心，必须建立独立工作包，列出调用方、协议样本、回归测试、实车验证和回滚点，得到明确确认后再实施。
4. OBD 写入、刷写和开机画面实验不得混入标准 PID、连接、分片或轮询路径。

## 5. 当前功能清单

### 5.1 连接、运行与数据协调

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| CORE-001 | ✅ | XP400 原车 BLE 连接 | 扫描、连接、状态接收和原车数据入口；稳定核心保持不动 |
| CORE-002 | ✅ | OBD BLE 连接 | 通过隐藏 OBD Connector 接入 ELM327 类设备 |
| CORE-003 | ✅ | OBD Wi-Fi 连接 | 支持网络 OBD 通道，连接入口与 BLE 分离 |
| CORE-004 | ✅ | OBD Mock 模式 | 无实车时提供标准数据和界面开发基础 |
| CORE-005 | 🟨 | 多连接协调 | 已有连接协调与状态转发；仍需覆盖 BLE 竞争、断线重连和后台恢复实测 |
| CORE-006 | ✅ | 按需启动服务 | 已减少无条件启动；需持续防止 PTT、Live Activity、OBD 等在冷启动时误激活 |
| CORE-007 | ✅ | 运动数据统一来源 | 俯仰、倾角、G 值等已接入；仍需不同安装角度和真车校准 |
| CORE-008 | 🟨 | 四语言基础 | App 已支持简中、繁中、英语、西班牙语；仍需清理动态文案和遗漏硬编码 |

### 5.2 仪表与车辆状态

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| DASH-001 | ✅ | 机车首页 | 展示车辆连接和核心骑行状态，并进入各仪表页面 |
| DASH-002 | ✅ | 原车状态指示 | 转向灯、远光、警告、连接等基础状态展示 |
| DASH-003 | ✅ | 普通专业仪表 | 速度、转速、油量、里程等常用数据仪表 |
| DASH-004 | ✅ | Peugeot 风格仪表 | 模拟 XP400 风格的 LED / 数字仪表展示 |
| DASH-005 | ✅ | 动态骑行组件 | 倾角、俯仰、G 值、颠簸等组件已存在，需实车校准与异常值治理 |
| DASH-006 | 🟨 | 摔车与碰撞预警 | 已有运动阈值和警告链路；不能替代专业救援设备，需道路误报验证 |
| DASH-007 | ✅ | 媒体与设备状态 | Now Playing、手机电量和本地歌词已有接入；歌词支持用户选择的 LRCLIB 在线回退，需真机 Apple Music、权限、网络和骑行安全验证 |
| DASH-008 | ✅ | 仪表颜色配置 | 用户可以调整支持的仪表主题或颜色 |
| DASH-009 | ✅ | 公英制单位 | 支持速度、距离等单位切换 |
| DASH-010 | ✅ | 仪表语言 | 仪表文案跟随当前 App 支持语言 |
| DASH-011 | 🟨 | Ride Center | 已整合行程、Roadbook 与回放入口；仍需真实道路和大文件验证 |

### 5.3 地图、导航与停车

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| NAV-001 | ✅ | 高德地图与定位 | 地图展示、实时位置和基础定位状态 |
| NAV-002 | ✅ | POI 搜索 | 搜索目的地并生成导航候选 |
| NAV-003 | ✅ | 路线偏好 | 支持路线策略和骑行偏好选择 |
| NAV-004 | ✅ | 多路线选择 | 展示并选择候选路线 |
| NAV-005 | ✅ | 实时导航 | 提供路线、转向、距离和到达信息 |
| NAV-006 | 🟨 | 仪表导航同步 | 导航信息可进入仪表展示；需后台、锁屏和重算路线验证 |
| NAV-007 | 🟨 | CarPlay 导航 | 已有 CarPlay 地图与导航接入；需真实车机完成生命周期验证 |
| NAV-008 | ✅ | 停车位置 | 保存停车坐标、地址和最近停车状态 |
| NAV-009 | ✅ | 收藏目的地与快捷导航 | 可保存常用目的地，并由快捷入口发起导航 |
| NAV-010 | 🟨 | 车友地图标记 | PTT / 组群位置可映射到地图；需处理过期、重复和隐私状态 |
| NAV-011 | ✅ | QWeather 天气 | 当前项目接入方式可用，本轮升级明确不重构 |
| NAV-012 | 🟨 | 加油站搜索与导航 | 已有快捷入口，需无结果、跨城和路线确认流程验证 |
| NAV-013 | 🟨 | 自定义路线编辑 | 已接入地图、有序路点列表、当前位置/坐标添加、重排、删除、重命名和保存；自动规划与真实地图验收不在本包 |

### 5.4 行程、回顾、安全与维护

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| RIDE-001 | ✅ | 自动行程记录 | 按连接和骑行状态记录行程基础数据 |
| RIDE-002 | ✅ | 行程历史 | 浏览已保存行程和基础摘要 |
| RIDE-003 | ✅ | 骑行指标与回顾 | 统计距离、时间、速度等并生成回顾信息 |
| RIDE-004 | 🟨 | GPX 导入导出 | 已有 GPX 能力，需覆盖大文件、异常轨迹和跨 App 分享 |
| RIDE-005 | ✅ | 行程快照 | 保存关键时刻或行程摘要快照 |
| RIDE-006 | 🟨 | 行程 iCloud 同步 | 已有云端保存链路，需冲突、离线、容量和多设备恢复验证 |
| RIDE-007 | 🟨 | 骑行黑匣子 | 已实现事件前 60 秒/后 30 秒有界片段、活动行程检查点、异常恢复、90 日/数量限制及 JSON/CSV/GPX 导出；真实碰撞和大数据验证待补 |
| RIDE-008 | 🟨 | 骑行故事 | 可基于行程生成分享内容；模板与隐私裁剪仍需完善 |
| RIDE-009 | 🟨 | 续航估算 | 优先使用仪表续航；XP400 GT 默认油箱 13.5 L，实时油耗无效时使用距离加权历史样本；加油记录和不同车型校准待补 |
| RIDE-010 | 🟨 | 维护提醒 | 已有维护数据与提醒能力，需明确周期来源和用户确认 |
| RIDE-011 | 🟨 | 组群安全 | 已有车友状态和安全事件基础，需真实多车、弱网和退出组群验证 |
| RIDE-012 | 🟨 | 防盗监控 | 用户主动开启；只有新鲜熄火状态才进入宽限/布防，支持断连定位校验、误报冷却和通知操作；后台耗电与误报真机验证待补 |
| RIDE-013 | 🟨 | 诊断与安全通知 | 保养、DTC、电瓶/低温、防盗统一使用类型化本地通知、分类动作和持久去重；授权降级与系统行为待补 |
| RIDE-018 | 🟨 | LiDAR 低速辅助与车库测距 | 前台显式开启；安装模式按仪表/OBD/GPS 新鲜车速门禁，车库模式支持三区测距、冻结、备注、本地有界保存和 JSON/CSV 导出；不替代专业防碰撞设备，真实设备误报与耗电待验证 |

### 5.5 PTT 车队对讲

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| PTT-001 | 🟨 | 局域网车队发现 | 基于 MultipeerConnectivity 发现和连接附近成员，需多设备稳定性验证 |
| PTT-002 | 🟨 | 按键对讲 | 支持按住发言和音频传输，需耳机、电话打断和音频路由验证 |
| PTT-003 | 🟨 | 免提 / VOX | 支持音量阈值触发；需风噪、头盔麦克风和误触发调校 |
| PTT-004 | ✅ | 成员名称与头像 | 展示车友身份信息，并在会话中同步 |
| PTT-005 | 🟨 | 人数、信号与延迟 | 已有指标展示和异常人数修复；仍需真实组群回归，禁止使用未初始化内存值 |
| PTT-006 | 🟨 | 成员位置同步 | 支持位置数据包和地图展示；需权限、过期时间和隐私开关 |
| PTT-007 | 🟨 | PTT Live Activity | 仅在用户加入有效组群后激活；需继续验证冷启动、恢复和离组清理 |
| PTT-008 | ✅ | 显式加入与恢复策略 | App 启动不应自动创建 PTT 活动，只有有效连接状态才能恢复 |
| PTT-009 | 🟨 | PTT 音频生命周期 | 仅在用户显式启动后激活 AudioSession；电话/导航中断或媒体服务重置后停止音频图，需用户点击恢复，不自动恢复麦克风或 VOX；耳机、电话和后台真机验证待补 |

### 5.6 OBD、UDS 与 CAN

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| OBD-001 | ✅ | 标准 PID 实时数据 | 使用稳定命令层读取并解码支持的标准车辆数据 |
| OBD-002 | ✅ | 故障码 | 读取已确认、待定和永久故障码并支持清晰展示 |
| OBD-003 | ✅ | ECU / 协议信息 | 展示支持的 ECU、协议和模块信息 |
| OBD-004 | ✅ | Mode 6 报告 | 读取并展示支持的车载监测测试结果 |
| OBD-005 | ✅ | VIN | 支持标准 VIN 读取和解码 |
| OBD-006 | 🟨 | 只读 UDS 服务 | 复用 `PTOBDiagnosticAddress`、稳定传输和已有独占轮询；已接入 62/7F/NRC、确认 DID 白名单、批量边界、取消与进度；实车车型证据待补 |
| OBD-007 | 🧪 | ECU 节点扫描 | 仅 Dev 显式开启，必须支持超时、取消、速率限制和轮询恢复 |
| OBD-008 | 🧪 | 内存读取与深度 Dump | 只读、限地址和限长度；无车型证据时不得扩大扫描范围 |
| OBD-009 | 🟨 | CAN Capture | 支持开始/停止、Header 过滤、流式保存和事件标记，需更多适配器实测 |
| OBD-010 | 🟨 | Capture 历史与导出 | 支持恢复、历史、JSON / JSONL / CSV；需异常退出与大文件验证 |
| OBD-011 | 🟨 | CAN 分析 | 支持 Capture diff、Byte / Bit diff、事件窗口和变化统计 |
| OBD-012 | 🟨 | Capture 离线回放 | 已有回放基础，可辅助无实车 UI 与回归测试，样本库仍需扩充 |
| OBD-013 | 🧪 | XP400 诊断证据目录 | 记录已确认请求、响应与适用 ECU；当前普通读取证据以 F190 VIN 为主 |
| OBD-014 | 🟨 | 独立只读诊断中心 | 已接入 DTC、VIN、Freeze Frame、Mode 6、确认 DID、结构化报告及进度/取消；真实设备和完整构建待补 |
| OBD-015 | 🟨 | 完整 CAN 实验室 UI | 已接入公开离线 Capture 历史、JSONL 恢复、分析、比较、分享、删除与回放；实时抓包只在 Dev 门禁入口，真实适配器验证待补 |

### 5.7 Apple 平台与系统集成

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| SYS-001 | ✅ | iOS Widget | 展示连接、油量、里程和停车信息 |
| SYS-002 | ✅ | Widget 共享状态 | `PTWidgetDataManager` 写入 App Group，Widget 读取统一字段 |
| SYS-003 | 🟨 | Widget iCloud 快照 | 同步最近状态；需多设备冲突、容器不可用和恢复验证 |
| SYS-004 | 🟨 | Apple Watch 骑行助手 | 按 Widget 风格展示车辆状态、只读导航和停车寻车；需不同表径和真实配对设备验证 |
| SYS-005 | 🟨 | Watch 最新状态同步 | 通过 `updateApplicationContext` 同步最近一份车辆与导航状态，不维护历史队列 |
| SYS-006 | 🟨 | 导航 Live Activity | 展示进行中的导航状态，需系统中断和结束清理验证 |
| SYS-007 | 🟨 | PTT Live Activity | 与有效组群会话绑定，不允许 App 启动即自动激活 |
| SYS-008 | 🟨 | CarPlay | 展示地图和导航；需真实车机覆盖连接、重连和退出 |
| SYS-009 | ✅ | Siri / App Intents | 支持车辆状态、停车位置、行程事件、打开 HUD、目的地导航和查找加油站 |
| SYS-010 | ✅ | URL Scheme | 支持 `checkFuel`、`antiTheft`、`openHUD`、`openSafety`、`confirmGasStationRoute`、`navigate` 路由 |
| SYS-011 | 🟨 | 本地通知 | 支持部分维护、诊断、防盗和骑行事件，需权限降级与去重 |
| SYS-012 | ✅ | Bugly 崩溃上报 | 收集生产测试崩溃；日志不得包含密钥和敏感车辆数据 |
| SYS-013 | 🟨 | XP400 系统通知镜像 | 复用 iOS 通知中心和系统 ANCS 条件；设置页区分 iPhone 本地通知测试、App 自有 ANCS 风格固定英文测试和真实仪表验证指引。已确认仅连接 PTSpeed、退出 Peugeot 官方 App 时真实来电和短信可显示；自有测试通道不读取其他 App 通知、不替代系统 ANCS，真实服务订阅和显示仍待验证 |

### 5.8 设置与产品基础

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| CORE-009 | ✅ | 连接设置 | 管理支持的车辆和 OBD 连接入口 |
| CORE-010 | ✅ | App 语言设置 | 支持简中、繁中、英语和西班牙语切换 |
| CORE-011 | ✅ | Siri / Scheme 使用说明 | 设置页进入独立说明页，展示 6 个 App Intent、6 条 URL Scheme、系统快捷指令入口和可复制示例 |
| CORE-012 | ✅ | 版本与 Build 展示 | 对外版本固定 2.0.8，后续只递增 Build |
| CORE-013 | 🟨 | 首次使用与更新说明 | 已有部分引导和版本内容，需随功能总纲持续同步 |

## 6. 开发者模块与高风险边界

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| DEV-001 | ✅ | 四指 Dev 入口 | TestFlight 中提供隐藏开发者工具入口 |
| DEV-002 | 🧪 | OBD / CAN Sniffer | 只供开发诊断；收起只隐藏控制台并保留当前会话，显式退出、失败、后台或断线后必须恢复 Header、轮询与 Sniffer 状态 |
| DEV-003 | 🧪 | 高风险功能总开关 | 默认关闭；开发者必须在 Dev 页面明确开启后才能进入实验流程 |
| DEV-004 | 🧪 | DID Fuzz | 必须限制范围、速率、超时和取消，不允许无边界全车扫描 |
| DEV-005 | 🧪 | 节点与深度读取 | 只读、结构化返回并保留失败节点，不得依赖日志作为数据接口 |
| DEV-006 | 🧪 | 仪表配置 / 开机画面实验 API | 仅保留受控研究入口；无真实协议证据、Seed-Key 和回滚方案时拒绝危险帧 |
| DEV-007 | ⬜ | 真实 OTA 更新 | 当前不具备可交付 Bootloader、CRC、ACK、断点续传与恢复闭环 |
| DEV-008 | ⬜ | ECU 固件刷写 | 当前不具备真实固件格式、分块传输、校验与失败回滚闭环 |
| DEV-009 | ⬜ | 原固件备份与完整性校验 | 空备份或固定成功结果不能视为功能完成 |
| DEV-010 | 🧪 | 刷写前置检查 | 计划校验电压、连接、车型、文件签名、备份、用户确认和恢复资源 |
| DEV-011 | 🟨 | LiDAR 碰撞辅助实验 | 复用统一 LiDAR 服务和现有 Dev 入口进行只读验证；正式低速辅助与车库测距已有独立入口，真实硬件和误报验证待补 |
| DEV-012 | 🧪 | Dev 会话与浮层生命周期 | Overlay 支持隐藏、收起和展开三态；收起后保留紧凑 DEV 按钮与当前会话，显式退出、退后台或断车自动撤销门禁 |

高风险操作统一规则：

1. 仅可从现有 Dev 模块开关进入，普通 UI、Widget、Watch、Siri 和 URL Scheme 不得调用。
2. 默认关闭；每次 App 启动后不得静默继承危险执行许可。
3. 开发者开关只是入口授权，不代表协议已验证；执行前仍需车型、ECU、会话、电压、文件和回滚检查。
4. 未确认 Seed-Key、Bootloader、签名、CRC、ACK、备份和恢复时，只允许生成报告或拒绝执行。
5. 所有实验必须保留原始请求/响应、时间、目标地址、固件标识和中止原因，并对导出内容脱敏。

## 7. Build 45 新增与补全功能计划

下列功能已经从候选池提升为 Build 45 正式工作包。当前代码已接入外围实现，但真实设备、云端和完整发布验证仍未全部完成，因此统一保持 `🟨`；只有代码、自动检查和对应设备验证均具有证据后，才能按第 2.1 节规则提升状态。

### 7.1 Build 45 正式新增功能

| ID | 状态 | Build 45 功能 | 最小可交付范围 |
| --- | --- | --- | --- |
| RIDE-014 | 🟨 | 出发检查 | 只读汇总当前车辆、连接、油量/续航、电瓶、保养、已有路线天气和 PTT 位置共享状态，不触发新的 BLE、OBD、定位或天气请求 |
| RIDE-015 | 🟨 | 每车轮胎与悬挂档案 | 按车辆保存轮胎型号、冷热胎压观察、载荷场景以及前后悬挂预载/回弹/压缩设置；不伪装为 TPMS 或厂家推荐值 |
| RIDE-016 | 🟨 | 加油记录与校准续航 | 按车辆保存里程、加油量、金额和是否加满；只使用有效的连续满箱记录校准油耗，绝不回写或覆盖仪表原始里程 |
| NAV-014 | 🟨 | 综合路线骑行风险 | 复用现有路线、弯道几何、天气结果和预计时段生成雨、风、低温、能见度、夜间与连续弯道路段提示，不提供竞速或极限速度建议 |
| SYS-014 | 🟨 | Watch 出发检查 | 通过现有 `updateApplicationContext` 展示最近一次出发检查摘要；不新增 Watch 数据库、OBD/BLE 连接或第二条同步通道 |
| RIDE-017 | 🟨 | 保养项目、费用与配件闭环 | 按车辆记录机油、滤芯、CVT、链条/传动、制动、轮胎、冷却液、电瓶等自定义任务、完成里程/日期、费用和备注；周期由用户或现有仪表数据确认 |
| DEV-013 | 🟨 | BLE 实车证据导入与报告 | Dev 模式只读导入抓包/验证记录，按已知帧契约分类、脱敏并生成差异报告；不得自动发送、重放或修改核心 BLE 逻辑 |
| SYS-015 | 🟨 | 多车库 iCloud 同步 | 云端同步车辆档案、保养、配件、轮胎/悬挂和加油记录；本机 Central UUID/仪表绑定单独保存，使用记录 ID、修改时间和删除墓碑处理冲突 |

### 7.2 既有 IDEA 跟踪

| ID | 状态 | 候选功能 | 最小可交付范围 |
| --- | --- | --- | --- |
| IDEA-001 | 🟨 | ADV Roadbook | 已支持 GPX 导入、路点列表、逐点仪表导航、连续偏航检测/返回和 GPX 分享；待真实 GPX、定位与仪表验收 |
| IDEA-002 | 🟨 | 完整行程回放 | 已支持 GPX 地图轨迹、速度/转速/倾角/三轴 G 值同步播放、事件时间轴和地图标记；待大文件、异常 GPX 与真机验证 |
| IDEA-003 | 🟨 | Watch 骑行助手 | 已支持 Roadbook / 普通导航只读提示、转向触觉和停车寻车；待真实配对、后台/锁屏及不同表径验证 |
| IDEA-004 | 🟨 | 多车库 | 已支持多辆摩托档案、当前车辆切换、里程、按车保养预警距离、实时保养状态、保养记录、只读 OBD 摘要和配件记录；仪表序列号优先、CoreBluetooth UUID 兜底关联，连接后自动保存里程与保养状态，PTT 昵称仅作为默认车辆名；待行程历史按车辆归属、iCloud 冲突同步与真实车辆验证 |
| IDEA-005 | ⬜ | 轮胎与悬挂档案 | 已提升到 Build 45 `RIDE-015` / `B45-07`，保留本 ID 用于追溯原始想法 |
| IDEA-006 | 🟨 | 路线天气风险 | Roadbook 优先使用 WeatherKit；任一采样失败时整条路线统一回退 QWeather，不混用数据，并显示实际来源；待真实路线与网络权限验收 |
| IDEA-007 | 🟨 | 防盗事件时间轴 | 已记录防盗启停、停车点、断连、报警、恢复和宽限期事件，并支持有界 JSON/CSV 导出；位移/震动传感器证据和通知闭环待真机验收 |
| IDEA-008 | 🟨 | 车队危险点与停车分享 | 已基于现有 PTT 可靠通道分享停车、路障、湿滑、施工、加油和集合点，支持 TTL、中继跳数、去重、过期和导出；待多真机验收 |
| IDEA-009 | 🧪 | XP400 指令证据库 | 已将只读 DID 结果按车辆、ECU 地址、原始响应、状态和观察等级保存，并对 VIN 导出脱敏；真实车型样本与证据晋级规则待补齐 |
| IDEA-010 | 🧪 | 安全固件升级状态机 | 已接入 Dev 面板的固件前置检查、阻断原因、审计和明确确认状态；未验证 Bootloader/CRC/ACK/恢复协议前始终拒绝发送字节 |

### 7.3 Build 46 LiDAR、PTT 与系统能力实施范围

| ID | 状态 | Build 46 内容 | 当前边界 |
| --- | --- | --- | --- |
| RIDE-018 | 🟨 | 前台 LiDAR 低速辅助、车库测距、三区采样、置信度过滤、5 帧中值平滑、报警驻留和有界本地测量记录 | 不在后台运行、不保存原始 ARFrame、不自动开启；真实 iPhone LiDAR、安装角度和道路误报待补 |
| PTT-009 | 🟨 | 按需 AudioSession、电话/导航中断处理、媒体服务重置、显式恢复按钮和播放/麦克风状态门禁 | 不自动恢复麦克风、VOX 或组网；两台以上真机和蓝牙耳机矩阵待补 |
| SYS-016 | ⬜ | CallKit / PushKit 评估边界 | Build 46 不添加 VoIP 推送、CallKit Provider、后台通话或新服务器；未来只有在线 PTT 后端、用户可接听语义和合规隐私方案确认后再立项 |

Build 46 不改变 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 或 `PTOBDCommand.swift`，也不改变 QWeather 初始化和现有 Watch、Widget、iCloud 数据通道。

### 7.4 Build 48 原生能力与资料功能

Build 48 已接入以下外围能力。它们不改变 BLE/OBD 稳定核心；尚未经过真机、真车、真实 NFC/SharePlay 或签名 TestFlight 验收的能力保持 `🟨`。

| 工作包 | 状态 | 当前产品能力 | 入口与边界 |
| --- | --- | --- | --- |
| B48-01 | 🟨 | 只读 UDS/ECU 批量 DID、取消、进度和结构化响应报告 | 诊断中心/Dev；只读，复用现有 OBD 传输 |
| B48-02/B48-08 | 🟨 | Widget、Watch 和新增页面共用状态/本地化出口；新增日语、俄语 | 设置语言；共十种 locale，仍需人工语言校对 |
| B48-03 | 🧪 | Dev 固件文件格式、大小、SHA-256 和元数据预检 | 既有 Dev 浮层；不会发送任何固件字节 |
| B48-04 | 🟨 | 出发检查、车库、Roadbook App Intent/Shortcuts；已有 Scheme 可作为 NFC 标签目标 | Siri/快捷指令/自动化说明页；NFC 实体标签和冷启动待验证 |
| B48-05 | 🟨 | 按车辆保存维修手册、保险/登记资料和扫描 PDF | 车库 > 车辆资料；本机私有文件，不并入 iCloud 档案 |
| B48-06 | 🟨 | 行程照片选择、压缩、预览和删除 | 行程回放 > 照片；PHPicker 选择权限，本机私有文件 |
| B48-07 | 🟨 | 只读 Roadbook SharePlay 路线快照 | Roadbook 操作菜单；最多 64 个路点，不同步车辆隐私和控制指令 |
| B48-09 | 🟨 | 十语言资源、三平台目标构建与测试构建门禁 | 发布流程；真实设备和签名发布仍需验证 |

### 7.5 Build 49 CAN 证据链与语言切换修复

Build 49 保持普通用户功能和三个稳定核心不变，重点收口开发者 CAN 证据链与 Build 48 日语/俄语切换问题：

| 工作包 | 状态 | 当前产品能力 | 入口与边界 |
| --- | --- | --- | --- |
| B49-01 | 🟨 | 原始 CAN Frame 保留首字节；显式 DLC、11/29-bit Header、分隔 Extended Header 可区分 | Dev CAN Capture；真实适配器回显待补 |
| B49-02 | 🟨 | 统一暂停轮询、配置 ELM327 被动监听、停止后恢复 Header/轮询 | 既有 Dev 门禁；不修改 BLE/OBD 稳定核心 |
| B49-03 | 🟨 | 日语/俄语可被运行时选择；缺失 key 安全回退英语；Widget/Watch 同步选择 | 设置 > 语言；真机完整页面校对待补 |
| B49-04 | 🟨 | 新增 CAN DLC/Header/语言回退测试和 Build49 版本门禁 | 测试与发布流程；XCTest/签名发布待补 |

Build 49 不宣称已经完成 XP400 GT 真实 ECU/CAN 证据，更不开放固件写入、开机画面写入或未知仪表指令。

### 7.6 Build 52 Apple Music 歌词与安全展示

Build 52 继续保持营销版本 `2.0.8`，只递增工程 Build。歌词能力只接入 `PTSpeed` 主 App，不把歌词内容写入 iCloud、Widget、Watch、Live Activity、PTT 或车辆通信链路。

| 工作包 | 状态 | 当前产品能力 | 入口与边界 |
| --- | --- | --- | --- |
| B52-00 | ✅ | Build 52、工程接入和稳定核心保护 | 三个 BLE/OBD 核心文件不变；主 App、嵌入 Watch App 和独立 Watch 目标构建通过 |
| B52-01 | ✅ | 共享歌曲快照、LRC/纯文本解析、时间戳偏移和重复时间戳处理 | 主 App 本地纯数据服务；不新增第三方 SDK |
| B52-02 | 🟨 | Now Playing 内嵌歌词优先、切歌取消、后台停止观察和当前行显示 | 仅消费 `MPMediaItem.lyrics`；系统媒体权限与真机播放状态待验证 |
| B52-03 | 🟨 | 用户同意后通过 HTTPS 调用 LRCLIB，并严格校验歌名、歌手、专辑和时长 | 设置页可关闭；内存缓存和负缓存有界；不上传 VIN、坐标或车辆数据 |
| B52-04 | 🟨 | 停车时可打开只读完整歌词页，行驶/速度数据不新鲜时自动拒绝或退出 | 不提供骑行中滚动歌词、地图、车辆控制或后台联网歌词 |
| B52-05 | 🟨 | 十语言文案、单元测试、编译与发布检查 | 真实 iPhone/Apple Music、网络异常、权限和 Watch/Widget 回归待补 |

Build 52 不使用私有 MusicKit 歌词接口、不抓取 Apple Music 页面、不绕过版权或 DRM；在线歌词仅是用户明确开启后的可选匹配服务。

### 7.7 Build 54–55 骑手健康与 XP400 协议证据

Build 54–55 继续保持营销版本 `2.0.8`，只递增工程 Build。新增能力均在稳定 BLE/OBD 核心之外运行：普通骑行能力只消费 `PTVehicleConnectivityCoordinator` 的真实遥测投影；协议实验和固件相关内容继续限制在现有 Dev 入口。

| 工作包 | 状态 | 当前产品能力 | 入口与边界 |
| --- | --- | --- | --- |
| B54-01 | 🟨 | 12V 电瓶静置/启动/运行阶段摘要及每车 365 天有界历史；Mock 只演示、不入库 | 车库/诊断报告；真实 Data2、长时间耗电和真车阈值待验证 |
| B54-02 | 🟨 | 转向灯遗忘提醒和 ABS 异常驻留提醒，均有真实来源、速度、持续时间、去重和断开重置门槛 | 系统通知；真实仪表状态和误报率待验证 |
| B54-03 | 🟨 | 按车辆保存手机支架三秒静止校准的横滚/俯仰/偏航零点 | 安全中心；需要真实 iPhone、安装方向和道路验证 |
| B54-04 | 🟨 | 仪表颜色/单位/语言配置增加真实仪表、实时低速三秒、用户确认和 Data3 回读确认 | 设置页；只允许已验证的 EN/FR/DE/ES/IT，不改变核心发送实现 |
| B54-05 | 🟨 | 诊断中心合并电瓶、轮速一致性、连接质量、DTC、Mode 6、DID、Freeze Frame 和只读 ECU 指纹，并支持脱敏报告导出 | 只读诊断中心；OBD 检测仍须用户主动启动 |
| B54-06 | 🟨 | TipKit 上下文提示覆盖首次绑定、支架校准和仪表配置确认 | 车库/安全中心/设置；由系统记录用户关闭状态 |
| B55-01 | 🧪 | 官方颜色、单位和五种已验证仪表语言的 A→B→A 实验向导，自动记录基线、时间点、Data3 读取和 CAN 前后窗口 | Dev CAN Lab；不自动发送设置，不自动生成协议命令 |
| B55-02 | 🧪 | 按 40/25/20/15 规则评分，达到 80 分只进入候选；窗口摘要和 JSON/CSV 报告可导出 | Dev Evidence；候选必须人工复核，未知字段只记录 |
| B55-03 | 🧪 | 关联同一车辆时间相近的 BLE/OBD 被动会话，展示通道和会话范围；导出不包含 VIN/坐标 | Dev Evidence；不新增抓包传输层 |
| B55-04 | 🧪 | 只读 ECU/仪表指纹、软件版本、协议、已确认 DID 目录；Bootloader/Calibration 仅登记只读状态 | Dev/诊断报告；不开放固件、Logo、语言写入 |

Build 54–55 不修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 或 `PTOBDCommand.swift`，不把未知观察结果自动提升为可执行命令，也不改变 QWeather 现有链路。

### 7.8 Build 56 骑行数据专业分析

Build 56 继续保持营销版本 `2.0.8`，只递增工程 Build。骑行历史列表改为紧凑摘要，点击记录后进入只读专业分析页；分析只消费已经持久化的 `PTTripReport`，不新增车辆通信、不修改 BLE/OBD 核心，也不改变原有 GPX 回放入口。

| 工作包 | 状态 | 当前产品能力 | 入口与边界 |
| --- | --- | --- | --- |
| B56-01 | ✅ | 骑行历史摘要卡与详情页导航；地图缩略图仍直接进入回放 | 骑行数据；列表索引使用稳定报告 ID，详细页面异步生成快照 |
| B56-02 | ✅ | 只读事实分析：时间、里程来源、速度、转速、倾角、G 值、俯仰、海拔、胎压和打滑/事件统计 | 骑行分析详情；无数据显示不可用，不虚构车辆或路线信息 |
| B56-03 | ✅ | 轨迹图表按类别切换并限制为最多 600 个公共采样点，保留有限极值和端点 | 骑行分析详情；兼容旧报告的不同轨迹长度和缺失轨迹 |
| B56-04 | ✅ | 同一辆车最近最多 10 次有效骑行对比，至少 3 次历史才展示基线 | 骑行分析详情；未绑定车辆、历史不足或数据无效时明确隐藏对比 |
| B56-05 | ✅ | 事件时间线可跳转至对应回放位置；支持分享脱敏摘要卡和分析 JSON | 骑行分析详情；分享内容不包含坐标、VIN、设备标识、GPX 文件名或原始轨迹 |
| B56-06 | ✅ | 数据质量区显示报告版本、轨迹样本数、时间轴估算和缺失/不一致警告 | 骑行分析详情；分析失败不影响历史记录和原有回放 |
| B56-07 | ✅ | 分析构建器、极值保留、同车历史筛选和脱敏导出纯数据测试已加入；`build-for-testing` 通过 | 测试与发布流程；XCTest 实际执行受当前真机签名配置阻断，签名发布、真机和大数据量验证待补 |

Build 56 不计算综合骑行评分，不自动给出驾驶能力或安全结论；它只展示可追溯的事实、数据来源和质量边界。

### 7.9 Build 57–61 架构收口状态

Build 57–61 继续保持营销版本 `2.0.8`，只递增工程 Build。以下状态区分代码静态检查、自动测试、目标编译和真实设备/车辆验证，不把其中一种证据冒充另一种证据。

| Build | 主题 | 静态 | 测试 | 编译 | 真机/实车 |
| --- | --- | --- | --- | --- | --- |
| 57 | OBD Architecture 2.0、YMOBD/Jieli 外围隔离 | ✅ | 🟨 | ✅ | ⬜ |
| 58 | Unified Vehicle Telemetry + Replay | ✅ | 🟨 | ✅ | ⬜ |
| 59 | CrazyDashboard Instruments Provider 前置能力 | ✅ | 🟨 | ✅ | ⬜ |
| 60 | Protocol Evidence 2.0、CAN Discovery、Vehicle Passport | ✅ | 🟨 | ✅ | ⬜ |
| 61 | Architecture Consolidation：Unified Consumer、Projection、Provider Registry、Evidence 边界 | ✅ | 🟨 | ✅ | ⬜ |

Build 61 新增的边界：

- `PTVehicleTelemetryConsumerHub` 发布不可变 Unified 快照，正式 Dashboard 已迁移到 Consumer + Projection 路径。
- Instruments 通过 `PTInstrumentProviderRegistry` 聚合 XP400 BLE、OBD、YMOBD、Jieli OTA、CAN、Telemetry、GPS、Motion 和 System Provider；原快照字段与导出入口保持兼容。
- Evidence V2 将 CAN Discovery、Correlation、Passport Resolver、Export 和 UserDefaults State Codec 提取为独立架构组件；Evidence storage key 与 schemaVersion 2 保持不变。
- 新组件均为只读；未知协议、真实仪表固件写入和 OTA 仍不从普通 UI 暴露。

Build 61 的完整依赖审计记录已归档；当前遥测架构见 [`../architecture/TELEMETRY_ARCHITECTURE.md`](../architecture/TELEMETRY_ARCHITECTURE.md)。

### 7.10 Build 62 持久化研究存储与回放测试平台

Build 62 继续保持营销版本 `2.0.8`，只递增工程 Build。Evidence 数据库、CrazyTrace 数据包和回放断言均为只读研究基础设施，不新增 BLE、ELM327、YMOBD 或 Jieli 传输路径；三个稳定核心文件保持零字节变化。

| 工作包 | 状态 | 当前实现 | 验证边界 |
| --- | --- | --- | --- |
| B62-01 | ✅ | 原生 SQLite Evidence schema，覆盖车辆、ECU、会话、Capture、Evidence、CAN 候选、Passport 和适配器身份表，并建立研究查询索引 | 数据库独立类型检查、SQLite 模拟器插入/去重验证通过；完整工程构建受 SmartCodable 依赖网络阻断，真实数据规模和迁移前备份待设备验证 |
| B62-02 | ✅ | `PTProtocolEvidenceRepository` 作为 Evidence V2 的持久化边界，重复证据按稳定指纹合并并保留重复次数 | 纯数据测试；不向任何传输核心发送迁移数据 |
| B62-03 | ✅ | UserDefaults 旧快照事务迁移、校验、失败回退和一版兼容镜像 | 迁移/回滚与旧库 Schema 升级测试已加入；旧设备升级与异常断电待补 |
| B62-04 | ✅ | 有界低价值证据清理、VACUUM 和 DB/Trace/CAN/Instrument 空间统计 API；默认不猜测生产目录执行删除 | 数据库与空间统计测试；设置页可视化和真实容量策略待补 |
| B62-05 | ✅ | CrazyTrace Schema 2 `.crazytrace` 目录包：manifest、timeline、按域 JSONL、metadata、CAN 占位文件、附件目录和 SHA-256 校验 | 包读写、完整性、脱敏和模拟器回放测试通过；iCloud 多设备冲突待补 |
| B62-06 | ✅ | `PTCrazyTraceExpectedResult`、Snapshot Assertion 和无计时器纯状态回放评估器 | 确定性回放测试；不替代真实 BLE/OBD/车辆验证 |
| B62-07～B62-09 | ✅ | XP400、ELM327/UDS/CAN、YMOBD/OTA/组合离线样本目录与固定样本工厂；OTA 只回放状态，不执行 Jieli SDK | Fixture 回归测试；真实原始包仍需脱敏后人工导入 |
| B62-10 | ✅ | `Scripts/build62_checks.sh` 与 GitHub Actions：版本门禁、主 App build-for-testing、纯数据回放和数据库测试入口 | CI 执行受 Pods/Xcode 环境影响时需保留日志；真机不放 CI |
| B62-11 | ✅ | 空库、迁移、重复/去重、损坏库、事务回滚、Schema 升级、过期 Capture 清理和 100,000 条 Evidence 索引查询测试 | SQLite 模拟器验证通过；目标为 10,000 条常用查询小于 100 ms，仍需真机实测确认 |
| B62-12 | ✅ | 本节、回放样本说明、持久化边界和核心文件保护记录已同步 | 文档检查；后续 schema 变更必须增加 migration version |

Build 62 的数据库文件位于本地 Application Support，不同步到 iCloud；Trace 导出保留现有 flat JSON 兼容入口，新增目录包 API，不改变旧 UI 调用。UserDefaults 旧 Evidence blob 在本版本不删除，迁移失败时继续可读。真实 XP400 BLE、ELM327 CAN 和 OTA 仍需单独的人工设备验收。

### 7.11 Build 63 Protocol Research Lab 3.0

Build 63 继续保持营销版本 `2.0.8`，只递增工程 Build。Protocol Research Lab 只消费已经保存的 CAN Capture、Evidence 和 Unified Telemetry，不新增 BLE、ELM327、YMOBD、UDS、OTA 或车辆写入路径；三个稳定核心文件保持零字节变化。

| 工作包 | 状态 | 当前实现 | 验证边界 |
| --- | --- | --- | --- |
| B63-01 | ✅ | `PTCANExperiment` 与有界 `PTCANExperimentTrial`，支持多次激活/解除标记、Capture、会话、控制窗口和来源 | 纯数据构造与重复 Trial 回放验证；真实车辆动作仍由开发者人工执行 |
| B63-02 | ✅ | `PTProtocolResearchStore` Actor 以原子 JSON 保存 Experiment、Trial、Analysis Report 和每车 Signal Catalog；复用现有 ProtocolResearch Application Support 目录 | 持久化重开、Trial 恢复和写入串行化测试；跨设备同步和异常断电仍待真机验证 |
| B63-03 | ✅ | 透明权重的 Repeatability Score V2，输出激活/解除命中率、背景变化、延迟、跨会话重复性和来源一致性 | 固定两 Trial 模拟器验证；权重不使用黑盒 ML |
| B63-04 | ✅ | 每个 CAN ID/Byte/Bit 输出统计、Median/P95 延迟、Sessions、Confidence、Background Isolation 和 False Positive 报告 | 确定性离线报告验证；大规模真实 Capture 性能仍待设备验证 |
| B63-05 | ✅ | `PTVehicleSignalCatalog` 与候选状态流转；自动插入只允许 `candidate`，`probable/confirmed/rejected` 必须显式人工操作 | 自动发现不会晋级；真实证据审查流程和 UI 入口仍需开发者现场验证 |
| B63-06 | ✅ | CAN、XP400 BLE、OBD 和 Unified Telemetry 合并为可追溯 Timeline，记录时间接近、重复次数、状态一致性和 Evidence ID | 已验证模型级 Evidence 可追溯；各协议真实时钟偏差仍待多设备测试 |
| B63-07 | ✅ | 事件→Marker→协议信号/Telemetry 的 Relationship Graph，节点与边携带 Evidence 关联 | 图构建确定性验证；不提供任何自动发送命令 |
| B63-08 | ✅ | 左/右转向、双闪、远光、刹车、支架、点火、TCS、ABS、发动机、骑行模式和燃油变化只读研究模板 | 模板只指导被动采集；安全动作、车辆状态和语言由现场人员确认 |
| B63-09 | ✅ | 背景窗口 False Positive 检测；背景突变率越高，Background Isolation 和 Confidence 越低 | 固定无背景突变样本通过；噪声强度、不同适配器和真实道路场景待补 |
| B63-10 | ✅ | Experiment 可导出为 CrazyTrace Schema 2，离线重建 Capture 并重新运行分析，输出稳定 ID 和稳定排序 | 同一输入两次输出一致，回放不执行任何 SDK；真实导入包仍需脱敏 |
| B63-11 | ✅ | Build 63 XCTest、版本门禁、工程引用和自动化入口已接入 | 当前环境若再次被 SmartCodable/swift-syntax 网络依赖阻断，以静态检查和独立离线测试结果为准；真机/实车验收待补 |

Build 63 的研究资料默认保存在本地 Application Support；CrazyTrace 导出沿用 Build 62 的隐私裁剪和校验机制。研究候选永远不会自动变成可执行指令，OTA 相关内容仍只允许状态回放。真实 XP400、ELM327/CAN、BLE/OBD 时间关联和人工确认必须在开发者工具中单独验收。

### 7.12 Build 64 XP400 Electronic Identity Platform

Build 64 继续保持营销版本 `2.0.8`，只递增工程 Build。Electronic Identity Platform 只解析已保存的 Evidence、已知身份档案和既有只读结果，不新增 BLE、ELM327、YMOBD、UDS 或 OTA 传输路径；`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 与 `PTBluetoothManager.swift` 保持冻结、零字节变化。

| 工作包 | 状态 | 当前实现 | 验证边界 |
| --- | --- | --- | --- |
| B64-01 | ✅ | `PTElectronicControlUnit` 和 `PTECURole` 建模 dashboard、connectivity box、engine、ABS、body 与 unknown；YMOBD 单独建模为 `PTDiagnosticAdapterIdentity` | 纯模型和解析测试；真实 ECU 地址仍需人工实车证据 |
| B64-02 | ✅ | `PTEvidenceBackedValue` 为每个身份字段保存 value、source、confidence、evidenceIDs、updatedAt 和 evidence tier | 来源优先级与空值边界有测试；置信度仍由采集/导入流程提供 |
| B64-03 | ✅ | `PTXP400ReadOnlyDIDCatalog` 只允许有证据的 official/capturedRepeatable DID；candidate 必须显式选择，未知 DID 不自动宽扫 | 目录与显式候选测试；真实 DID 可读性仍需现场确认 |
| B64-04 | ✅ | `PTReadOnlyECUEnumerationPolicy` 和 `PTReadOnlyECUEnumerationPlan` 只允许 TesterPresent/ReadDataByIdentifier；SecurityAccess、Reset、Write、Routine、Download、Transfer 全部拒绝 | 只读/危险服务分类测试；计划只生成审计请求，不执行传输 |
| B64-05 | ✅ | `PTVehicleIdentityResolver` 按 Official → Live captured → Repeated captured → Stored profile 解析仪表 reference、HW、SW、Boot、Serial；缺失保持 Unknown | 官方证据优先、Passport 投影和 evidence 追溯测试；不猜测未知字段 |
| B64-06 | ✅ | connectivity box 与 dashboard 分离，支持 HW、SW、Boot、Reference、Serial、BLE fingerprint 和 protocol fingerprint | 结构化模型测试；真实盒子边界需真实设备证据 |
| B64-07 | ✅ | engine、ABS、body 只读身份字段和诊断地址可进入身份快照；没有任何刷写执行器 | 解析/拓扑测试；不启用 SecurityAccess 或固件操作 |
| B64-08 | ✅ | `PTVehicleElectronicTopology` 保存 XP400 车辆、ECU、YMOBD 诊断适配器和 Jieli OTA capability 的证据关联图 | 拓扑保存与 YMOBD 非 ECU 测试；真实网络拓扑待实车确认 |
| B64-09 | ✅ | Passport 继续作为兼容投影，新增身份字段 evidenceIDs；每个值可回溯到 Evidence | 旧 Passport 编解码保持兼容；暂不新增 Passport UI |
| B64-10 | ✅ | `PTVehicleIdentityDiff` 对比旧/新身份、软件变化、首次/最近时间和 Evidence IDs；`PTVehicleIdentityStore` Actor 原子保存快照、拓扑与差异 | 存储重开、稳定 ID 和软件差异测试；跨设备同步与真机容量待补 |
| B64-11 | ✅ | Build 64 版本门禁、工程引用、主 App/Test 构建脚本和 GitHub Actions 已接入 | 当前环境若被 Pods/模拟器架构阻断，保留静态检查和目标构建证据；XCTest 真正执行与签名发布待补 |

Build 64 的身份资料默认保存在本地 Application Support；YMOBD/Jieli OTA 只作为诊断适配器能力证据，不被提升为 XP400 ECU 固件身份。所有候选 DID 和 ECU 观察都必须保留 Evidence ID。Build 64 不开放 SecurityAccess、写入、Reset、RoutineControl、固件下载或刷写操作。

### 7.13 Build 65 Swift 6 + Release Hardening

Build 65 继续保持营销版本 `2.0.8`，只递增工程 Build。重点是并发归属、纯模型隔离、分阶段 Swift 6、后台生命周期、长时间运行、存储压力、崩溃恢复、Release 安全和默认隐私；不修改 `PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 或 `PTBluetoothManager.swift`。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B65-01 | ✅ | `PTBuild65ConcurrencyOwnershipMatrix` 固化 UIKit、XP400、ELM327、Telemetry、Evidence、Trace、Instruments 和 UI Store 的唯一归属 | 静态；冻结核心只登记不迁移 |
| B65-02 | ✅ | 重点遥测、Instruments、Evidence、CAN、Signal、ECU 和 CrazyTrace 模型显式 `Sendable` | Swift 6 泛型约束编译检查 |
| B65-03 | ✅ | 纯错误/结果/Trace/Safety/Evidence DB 外围模型显式 `nonisolated`，UI Store 保持 `@MainActor` | 只改外围模型，未改变传输状态归属 |
| B65-04 | 🟨 | `PTSpeedTests` 先启用 Swift 6 + complete strict concurrency；主 App、Widget、Watch 维持分阶段迁移 | 目标编译；全 Target warnings 清零待后续阶段 |
| B65-05 | 🟨 | 17 项前后台、锁屏、蓝牙/网络、低电量、热、内存、终止恢复和 XP400/OBD 场景矩阵 | 真机/实车执行待补 |
| B65-06 | 🟨 | 30 分钟、2 小时、4 小时 XP400/OBD/并存/骑行/PTT/Instruments/CAN soak 协议 | Instruments + 真机证据待补 |
| B65-07 | ✅ | Evidence 有界分页；CrazyTrace 与 CAN Capture 均使用有界写入/批量读取，避免新增全量读接口 | 纯逻辑与存储路径已接入 |
| B65-08 | ✅ | SQLite 事务、Trace staging 原子发布、临时文件恢复、既有 Ride/OTA checkpoint 保持 | 自动恢复测试；断电/崩溃真机待补 |
| B65-09 | ✅ | Release 默认策略关闭危险 Dev surface、未知 mutation、CAN injection、SecurityAccess 自动化，Jieli OTA 限 YMOBD | 静态 Safety Gate；TestFlight Dev 仍需显式开关 |
| B65-10 | ✅ | Trace 默认脱敏 VIN、MAC、精确位置、联系人、PTT 音频和通知文本 | 默认 Trace 导出测试；旧兼容导出继续单独审计 |
| B65-11 | ✅ | 版本门禁、冻结核心检查、Swift 解析、build65 脚本、CI 和验收文档同步 | 当前代码/工程；签名与真机待补 |

Build 65 的详细验收、长时间运行、存储压力、崩溃恢复、隐私字段和回滚记录见 [`../history/builds/BUILD_065_RELEASE_HARDENING.md`](../history/builds/BUILD_065_RELEASE_HARDENING.md)。本版本所有“真机/实车待补”不得因静态或编译通过而改为 `✅`。

### 7.14 Build 66 GPS Speed Fallback + Unified Speed Resolver

Build 66 继续保持营销版本 `2.0.8`，只递增工程 Build。速度展示统一经过 `PTVehicleTelemetryBridge`：XP400 BLE 优先，OBD 次之，经过质量校验和平滑的 GPS 作为回退；CrazyTrace Replay 在回放时显式覆盖实时来源。`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 在本版本保持零字节变化。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B66-00 | ✅ | 工程和所有 Target 统一到 `MARKETING_VERSION = 2.0.8`、`CURRENT_PROJECT_VERSION = 66` | 静态版本门禁；签名发布待补 |
| B66-01 | ✅ | 新增 `PTVehicleSpeedSource`、`PTVehicleSpeedSample`、质量、解析结果、原因和诊断模型 | Swift 6 解析与单元测试 |
| B66-02 | ✅ | 固化 XP400 1.5s、OBD 2s、GPS 3s、30m 水平精度、3m/s 速度精度、2km/h 静止阈值、3 点中值、EMA 0.45 和两次接管策略 | 纯逻辑测试；道路噪声待补 |
| B66-03 | ✅ | `PTGPSSpeedProvider` 复用 `PTLocationEngine/AMap` 已有 CLLocation，拒绝负速度、过期和低精度样本，不创建第二套定位服务 | 单元测试；真实定位权限/弱信号待补 |
| B66-04 | ✅ | `PTVehicleSpeedResolver` 按来源优先级、独立新鲜度、接管滞回、断开清理和 Replay 覆盖输出唯一速度 | 单元测试；车辆切源实测待补 |
| B66-05 | ✅ | 过期即时回退、优先来源两次有效样本接管、合法 0 与不可用 `nil` 分离 | 单元测试与诊断字段 |
| B66-06 | ✅ | GPS 位置适配只把非速度信号交给原 Resolver，GPS 速度交给专用 Provider，保留 CrazyTrace 原始速度 | Replay/纯数据检查 |
| B66-07 | ✅ | 在既有 `PTVehicleTelemetryBridge` 接入专用速度路径，不改 BLE/ELM327 传输、协议或 PID | 主 App 目标构建 |
| B66-08 | ✅ | 主 Dashboard 删除 Location 直接写速路径，只消费统一 Projection；速度失效时清除旧指针 | 代码路径检查；CarPlay/真机待补 |
| B66-09 | ✅ | Peugeot 仪表兼容页和 `PTMotoInfoViewController` 统一消费 Hub 的速度，保留 RPM、温度等未迁移字段的既有兼容路径 | 主 App 构建；真车显示待补 |
| B66-10 | ✅ | Dev Instruments 增加 Unified Speed 面板、GPS 质量、来源、原因、年龄、接管计数和时间轴 | JSON/旧快照兼容测试 |
| B66-11 | ✅ | 新增速度 Resolver、GPS Provider 边界测试，覆盖优先级、回退、滞回、0/nil 和质量校验 | PTSpeedTests 编译；实际 XCTest 受环境影响时单独记录 |
| B66-12 | ✅ | CrazyTrace 位置 0 速保留与旧 Instruments 快照缺省字段回放兼容测试 | 离线 Replay；真实道路回放待补 |
| B66-13 | 🟨 | Build66 检查脚本、迁移记录和发布门禁已接入；需完成 iPhone GPS-only、GPS→OBD、OBD→XP400、断开回退和后台验证 | 静态/目标构建完成；真机/实车和签名发布待补 |

Build 66 的实现记录、速度来源诊断和真机验收矩阵见 [`../history/builds/BUILD_066_GPS_SPEED_FALLBACK.md`](../history/builds/BUILD_066_GPS_SPEED_FALLBACK.md)。静态检查、单元测试和目标编译不等价于真实车辆道路验证。

### 7.15 Build 67 XP400 Dashboard Protocol Correction

Build 67 继续保持营销版本 `2.0.8`，只递增工程 Build。此次修正仅发生在外围仪表协议解码、诊断模型、Mock 和开发者抓包界面；`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 均保持零字节变化。Data2 的前三个字节正式解码为仪表 RTC，原先未经证实的背光、电瓶显示和边撑高位不再传播；Control 修复 TCS Ready 位运算并保留滚动计数器；ABS 保留前轮速度和原始字节，但警告灯状态暂标记为未知。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B67-00 | ✅ | 所有 Target 统一到 `MARKETING_VERSION = 2.0.8`、`CURRENT_PROJECT_VERSION = 67` | 静态版本门禁；签名发布待补 |
| B67-01 | ✅ | 新增 `PTDashboardClock`，按 `B0>>2/B1>>2/B2>>3` 解码 `HH:mm:ss`，非法 RTC 返回 `nil` | 纯数据单元测试；仪表 RTC 真车矩阵待补 |
| B67-02 | ✅ | Data2 移除错误高位状态传播，保留低位原始值和既有发动机/电压/温度/保养字段 | 主 App 目标构建；背光、边撑和电瓶显示专项采样待补 |
| B67-03 | ✅ | Control 从完整 `controlFlagsRaw` 读取 TCS Ready，保持 `0x00/0x02/0x04` 模式映射 | 纯数据回归；三种 TCS 模式真车验证待补 |
| B67-04 | ✅ | 新增 `rollingCounterRaw`、模 256 delta、重复/跳变诊断和有界 Packet Snapshot | 单元测试与日志检查；精确计时单位待 Build68 |
| B67-05 | ✅ | ABS 保留 `0x0310 → 7.84 km/h` 前轮速度，新增三个原始字节，警告灯默认 `unknown` | 纯数据测试；ABS 自检灯真车标记待补 |
| B67-06 | ✅ | 新增 normal/protocolDebug/rawHex 分级诊断；开发者控制台展开时显示索引字节 | 静态与日志路径检查；长时间抓包待补 |
| B67-07 | ✅ | CAN Lab 手动标记背光、边撑、ABS、TCS 的可逆实验事件 | 开发者界面静态检查；实车 A/B 采样待补 |
| B67-08 | ✅ | Mock Data2 使用当前 RTC、Mock Control 使用 `+5` 滚动计数器，增加协议回归测试 | Mock/Tests 编译；真实车辆行为待补 |
| B67-09 | 🟨 | Build67 检查、真实停车/骑行、ABS/TCS/边撑/背光实验和 Release 签名验收 | Debug `build-for-testing` 已通过；真机/实车和签名发布待补 |

Build 67 的实施记录、协议证据和回滚边界见 [`../history/builds/BUILD_067_DASHBOARD_PROTOCOL_CORRECTION.md`](../history/builds/BUILD_067_DASHBOARD_PROTOCOL_CORRECTION.md)。Build 67 不实现 Build68 预留的背光、边撑、电瓶显示、ABS 警告灯正式映射、RTC 对时和滚动计数器时间单位推断。

### 7.16 Build 68 OBD Diagnostic Deep Mining

Build 68 继续保持营销版本 `2.0.8`，只递增工程 Build。新增能力围绕现有 ELM327 会话和 YMOBD 扩展建立只读诊断证据链：DTC 异常升级、Freeze Frame、Mode 01/02/06/09 能力发现、ECU 身份与 CALID/CVN 指纹、发动机运行时间、每 PID 可靠性、电压与油门语义、基线统计、轮询建议和日志脱敏。`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`、`PTBluetoothManager.swift` 保持冻结，不复制 CoreBluetooth、ELM327 分帧或轮询引擎。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B68-00 | ✅ | 所有 Target 统一到 `MARKETING_VERSION = 2.0.8`、`CURRENT_PROJECT_VERSION = 68` | 静态版本门禁；签名发布待补 |
| B68-01 | ✅ | `0101` 发现 Confirmed DTC 后，有界读取 `03`、`07`、`0A`；统一 Confirmed/Pending/Permanent 模型，不发送 `04` | 纯解析与 Mock；XP400 真车回传待补 |
| B68-02 | ✅ | 读取 `0202`～`020D` Freeze Frame，绑定触发 DTC，保存原始 Payload 和已解码字段 | 多帧、无数据和真实 Freeze Frame 待补 |
| B68-03 | ✅ | Session 阶段分离 Mode 01/02/06/09 capability discovery；单次 `NO DATA` 仅为临时不可用，避免进入高频 Runtime Loop | 纯状态测试；适配器时序和长时间占用待补 |
| B68-04 | ✅ | 读取 `0904`、`0906`、`0908`、`090A`，支持多个 CALID/CVN、ECU 名称和确定性 Firmware Fingerprint | XP400 固件矩阵待补 |
| B68-05 | ✅ | Mode 06 从 `0600` 有界发现到 `0620` 等 continuation，保留 MID/TID 原始证据 | 真实 Mode 06 数据待补 |
| B68-06 | ✅ | 拆分 PID 42/`ATRV` 电压，Relative Throttle 优先，合法 `0 km/h` 保持有效，统一遥测记录 source/confidence/freshness | 真车切源和电气噪声待补 |
| B68-07 | ✅ | 从 `011F` 推导 Engine Start Time；记录冷怠速、热怠速、巡航、加速、减速的有界基线统计 | 多次骑行趋势待补 |
| B68-08 | ✅ | 按能力、成功率、延迟和重要性生成 Tier A–D 轮询建议；不改写冻结核心的既有安全轮询队列 | 带宽/延迟 soak 待补 |
| B68-09 | ✅ | 默认对 Trace/Evidence 的 MAC 中段、crypt/SETCRYPT 脱敏，CALID/CVN 作为研究证据保留 | 导出审计与真实敏感数据矩阵待补 |
| B68-10 | ✅ | Diagnostic Center 摘要、脱敏 JSON 导出、车库报告、Protocol Evidence/Vehicle Passport 和 Trip 接入 | 真机 UI 与跨会话恢复待补 |
| B68-11 | 🟨 | Build68 检查、纯数据回归、Cold/Warm Idle、DTC、Mode 06、Mode 09、断连恢复和 Release 验收 | 静态/目标构建已接入；真机/实车和签名发布待补 |

Build 68 的实施记录、代码边界和真实验收矩阵见 [`../history/builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md`](../history/builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md)。本版本不开放清码、写 DID、ECU Coding、SecurityAccess、RoutineControl、固件刷写或任意 CAN 注入。

### 7.17 Build 69 Protocol Semantic Evidence Intelligence

Build 69 继续保持营销版本 `2.0.8`，只递增工程 Build。新增能力位于 BLE/OBD 稳定传输核心之外：XP400 语义 Schema/Decoder、RTC/TCS/ABS/sentinel/rolling tick 纠偏、Discovery 降噪、ELM/OBD2/UDS 分层、DTC 状态、Passport reducer、BLE/OBD/GPS/Motion 统一观察与关联、Evidence v3、v2 迁移、历史回放和 Dev Frame Inspector。`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`、`PTBluetoothManager.swift` 保持冻结。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B69-00 | ✅ | 所有 Target 统一到 `MARKETING_VERSION = 2.0.8`、`CURRENT_PROJECT_VERSION = 69`，新增语义/OBD/证据/回放源码与测试 Target 接入 | 静态门禁和 Debug `build-for-testing`；签名发布待补 |
| B69-01 | ✅ | XP400 11-byte 状态帧 Schema、Data2 RTC `B0>>2/B1>>2/B2>>3`、Engine low bits、Control TCS Ready、ABS 前轮速度和未知位 raw 保留 | Swift 纯逻辑测试；多固件真车字段矩阵待补 |
| B69-02 | ✅ | rolling tick 模 256 锚点、sentinel 规则、TX `01` status poll、Discovery 分类与候选/异常降噪 | 离线分类与回放测试；长时间 BLE 丢帧现场待补 |
| B69-03 | ✅ | ELM transport normalizer、OBD-II Mode 02/03/07/0A、UDS `62`/`7F`/NRC、多帧重组和 DTC 状态分离 | 纯数据测试；真实适配器/车型矩阵待补 |
| B69-04 | ✅ | Passport reducer、Connectivity Box/Dashboard/ECU 身份域分离、Evidence domain 规范 | 模型迁移测试；真实 ECU 地址和身份仍需独立证据 |
| B69-05 | ✅ | BLE、OBD、GPS、Motion 统一 Observation、来源/新鲜度/可用性、Speed/RPM/Voltage/Acceleration/Lean 关联 | 纯模型关联测试；多设备时钟偏差待补 |
| B69-06 | ✅ | Evidence schema v3、v2 migration、历史 JSONL/JSON re-analysis、Dev 分组面板、Frame Inspector、JSON/CSV 导出 | 编译和离线回放；大文件/真机分享待补 |
| B69-07 | 🟨 | MotoHex 与既有 Discovery/Evidence 样本的真实回放、候选率 `<10%`、前后台/断连/性能和 Release/TestFlight 验收 | 当前方案不提供可用具体 Simulator destination；真机/实车待补 |

Build 69 的实施记录和验收边界见 [`../history/builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md`](../history/builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md)。候选字段仍是研究证据，不会自动变成可执行指令；本 Build 不开放 ECU 写入、SecurityAccess、固件刷写、任意 CAN 注入或 ID 7 主动探针。

### 7.18 Build 77 Crazy Black Box Pro / CrazyTrace 2.0

Build 77 继续保持营销版本 `2.0.8`，工程 Build 为 `77`。它把统一 Vehicle State Projection、Motion、GPS、适配器和协议事件保存为可回放的 CrazyTrace 2.0，并让 Build 76 Digital Twin 通过既有 Telemetry Bridge/Consumer Hub 支持 2D/3D 离线复现。三个稳定核心 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持冻结，ELM327 仍是 OBD 底层，YMOBD 仍是其扩展。

| 工作包 | 状态 | 内容 | 验证边界 |
| --- | --- | --- | --- |
| B77-01～B77-03 | ✅ | Trace Schema 2、统一 Recorder、60 秒/20,000 事件有界 Ring Buffer | 离线模型/目标编译；长时间真机待补 |
| B77-04 | ✅ | Incident Trigger：事件前最多 60 秒、事件后最多 30 秒、Incident Marker | 异步回归；真实触发策略待补 |
| B77-05～B77-07 | ✅ | Reader、Replay Source 和 Digital Twin `.crazytrace` 导入；继续复用既有回放时钟和状态总线 | 包回读/构建；真机交互待补 |
| B77-08～B77-09 | ✅ | 结构化目录包、后台编码、staging 原子发布、默认 redacted 隐私导出 | Checksum/脱敏回归；真实分享待补 |
| B77-10～B77-11 | ✅ | 复用固定 Replay Fixture，兼容旧 flat JSON、legacy streams 和没有结构化流的旧包 | 确定性回放与兼容测试 |
| B77-12 | 🟨 | XP400/XP400 GT 真车、后台/断连、2D/3D 一致性、无写入证明和 Instruments/Release 验收 | 现场证据待补 |

详细实施和现场清单见 [`../history/builds/BUILD_077_CRAZYTRACE_2.md`](../history/builds/BUILD_077_CRAZYTRACE_2.md) 与 [`../history/builds/BUILD_077_REAL_VEHICLE_VALIDATION.md`](../history/builds/BUILD_077_REAL_VEHICLE_VALIDATION.md)。Build 77 不新增第二套 BLE、ELM327、YMOBD、UDS、CAN 或遥测研究管线，也不开放未知写入、SecurityAccess、CAN injection 或刷写。

## 8. 已退役功能

当前没有需要登记的已退役功能。后续移除功能时，在下表保留原 ID、最后可用 Build、移除原因和替代路径。

| ID | 状态 | 功能 | 最后可用 Build | 移除原因 / 替代路径 |
| --- | --- | --- | --- | --- |
| — | — | — | — | — |

## 9. 当前主要验证缺口

这些缺口不会否定已有代码，但在完成前对应能力不得从 `🟨` 提升为 `✅`：

- XP400 原车 BLE 与 OBD BLE 同时运行时的扫描、重连、后台和资源竞争。
- PTT 两台及以上真机的加入、退出、异常断线、VOX、人数、位置和 Live Activity 生命周期。
- Apple Watch 离线后恢复、后台/锁屏导航更新、触觉去重、停车链接和不同表径布局。
- CarPlay 真实车机连接、重连、导航结束与 iPhone/车机双屏状态一致性。
- iCloud 无网络、冲突、容量不足、换机恢复与容器不可用场景。
- CAN Capture 的不同 ELM327 适配器、11-bit / 29-bit Header、多帧、异常断电和大文件。
- UDS 节点与 DID 的 XP400 实车证据；未知指令默认不执行。
- 路线天气风险的 WeatherKit 权限、QWeather 整路线回退、168 小时边界、网络异常、长路线采样和真实骑行提醒阈值。
- 防盗位移/震动来源、通知确认回写和后台耗电；当前时间轴记录不替代系统级防盗保证。
- 车队点位的多真机中继、身份可信度、恶意内容处理和离线重连策略。
- XP400 证据库的真实 ECU/固件版本覆盖，以及证据从“观察”晋级为“确认”的人工审查流程。
- 固件升级状态机仍缺少经实车验证的 Bootloader、Seed-Key、CRC、ACK、断点恢复、备份和回滚协议。
- 碰撞、防盗和安全提醒的误报率、耗电和用户确认流程。

## 10. 功能变更记录模板

每次新增、修改、隐藏或删除功能时，在对应表格更新，并在提交说明或工作包中补齐：

```text
功能 ID：
变更类型：新增 / 修改 / 隐藏 / 退役
用户入口：
支持平台：iPhone / Widget / Watch / CarPlay / Siri / Dev
数据来源：
受影响模块：
验证：静态 / 测试 / 编译 / 真机
回滚方式：
文档同步：本文件 / [`../planning/ACTIVE_WORK.md`](../planning/ACTIVE_WORK.md) / [`../history/BUILD_HISTORY_2026.md`](../history/BUILD_HISTORY_2026.md) / `README.md`
```

## 11. 总纲审计记录

| 日期 | 仓库基线 | 内容 |
| --- | --- | --- |
| 2026-09-01 | `b6d39a0` | 建立首版功能总纲，覆盖 iPhone、Widget、Watch、CarPlay、Siri、PTT、OBD、Dev 和候选功能 |
| 2026-09-01 | 当前工作区 | IDEA-003 已接入 Watch 只读导航、Roadbook 提示、转向触觉和停车寻车；保留真实设备与道路验证缺口 |
| 2026-09-01 | 当前工作区 | IDEA-004 已接入设置页车库入口、车辆档案切换、里程管理、保养记录、只读 OBD 摘要和配件档案；行程历史归属与 iCloud 冲突同步暂留后续 |
| 2026-09-01 | 当前工作区 | IDEA-004 保养提醒已支持每车预警距离、仪表 `distToMaintenance` 实时比较、保养状态展示和按车辆/状态通知限频；保留真实车辆数据验证 |
| 2026-09-01 | 当前工作区 | IDEA-006～IDEA-010 已完成第一版外围实现：路线天气风险、防盗事件时间轴、PTT 点位分享、只读 XP400 证据库和 Dev 固件前置状态机；保留 WeatherKit/PTT/实车协议验证缺口，未修改 BLE 与 OBD 稳定核心 |
| 2026-09-02 | 当前工作区 Build 40 | NAV-013、RIDE-007、RIDE-009、RIDE-012、RIDE-013、OBD-006、OBD-014、OBD-015 已完成代码接入；iOS、Widget、Watch 和测试 Target 已完成编译，纯数据单元测试已登记但因当前 Simulator destination 与工程支持平台不匹配尚未执行；真实设备/车辆验证仍待补，受保护核心未修改 |
| 2026-09-02 | 当前工作区 Build 41 | IDEA-006 路线天气改为 WeatherKit 首选、单点失败后整路线 QWeather 回退；报告记录唯一提供方，QWeather 复用 App 启动时已初始化的实例；新增取消、无备用服务、双服务失败和 168 小时边界处理；主 App Debug 编译通过，真实天气权限/网络与设备验证仍待补 |
| 2026-09-02 | 当前工作区 Build 42 | DEV-012 已完成开发者浮层三态、显式退出/生命周期撤销、全局紧凑按钮、触摸穿透、可拖动边界、门禁通知同步和 CAN Lab 自动停止接入；Debug/Release 目标构建和测试构建已通过，XCTest 实际运行、真实设备与适配器验证待补 |
| 2026-09-02 | 当前工作区 Build 43 | SYS-013 已接入设置页的 iOS 通知权限状态、公开通知设置跳转、本地测试通知和 XP400 系统 ANCS 配置指引；后续修正为 10 秒 iPhone 本地测试，并新增真实仪表验证入口。真车已确认仅连接 PTSpeed、退出 Peugeot 官方 App 时真实来电和短信可显示；第三方通知、锁屏/专注模式与断连重连仍待验证 |
| 2026-09-02 | 当前工作区 Build 44 | CORE-011 已接入独立 Siri、App Shortcuts 与 URL Scheme 说明页；设置入口改为页内导航，Scheme 示例仅复制不执行，保留真实 Siri、Shortcuts 和外部 Scheme 真机验证 |
| 2026-09-03 | 当前工作区 | IDEA-004 车库自动同步已接入：按仪表序列号优先、Central UUID 兜底进行车辆关联；Data1 里程、Data2 保养标志和 Data3 保养剩余里程按车持久化，首次/每 60 秒/退后台/断开自动保存，身份冲突必须用户确认；PTT 昵称只用于默认名称。主 App 与测试构建已通过，真实仪表和多车切换验证待补 |
| 2026-09-04 | `8c51ee8` / Build 45 | Build 45 已完成 RIDE-014～RIDE-017、NAV-014、SYS-014、SYS-015、DEV-013 的外围代码接入：出发检查、轮胎/悬挂档案、加油与续航校准、综合路线风险、Watch 摘要、保养费用闭环、BLE 证据导入和多车库 iCloud；当前统一标记为部分完成，实施证据和验证缺口见升级计划第 27 节 |
| 2026-09-04 | 当前工作区 | SYS-013 新增 `PTDashboardANCSProvider`：复用现有 `CBPeripheralManager` 提供 App 自有 ANCS 风格测试通道，设置页可发送固定英文消息；系统电话/短信链路不变，服务注册、XP400 订阅和仪表显示仍待真机验证 |
| 2026-09-05 | 当前工作区 Build 46 | RIDE-018 已接入前台 LiDAR 三区测距、低速车速门禁、置信度/中值平滑、报警驻留、车库冻结保存与 JSON/CSV 导出；PTT-009 已移除启动时 AudioSession 初始化，加入中断/媒体重置后的显式音频恢复；CallKit/PushKit 保留未来评估边界。主 App、Widget、Watch 与 Tests 目标构建通过，XCTest 实际执行、签名发布和真实设备/车辆验证待补 |
| 2026-09-06 | 当前工作区 Build 48 | B48-01～B48-09 已完成外围代码接入：只读 OBD 取消/进度、十语言资源、Dev 固件文件预检、App Intents/Scheme NFC-ready、车库资料、行程照片和 Roadbook SharePlay；主 App、Widget、Watch generic build 与 Tests `build-for-testing` 通过，XCTest 实际执行、签名发布、真实 NFC/SharePlay/Watch/车辆验证待补；三个 BLE/OBD 核心文件零字节变化 |
| 2026-09-06 | 当前工作区 Build 49 | B49-01～B49-04 已接入 CAN 原始解析/监听协调、适配器恢复、日语/俄语运行时 locale 修复和回归测试；启动时会重新应用 Build48 已保存的日语/俄语选择；iOS 工作区 Debug 构建与 `build-for-testing`、Widget/Watch 包资源检查通过，XCTest 实际运行、签名发布、真实语言/ELM327/XP400 验证待补；三个 BLE/OBD 核心文件零字节变化 |
| 2026-09-07 | 当前工作区 Build 50 | B50-00～B50-04 已实施：新增统一导航会话协调器，收口 AMap 代理、手机/CarPlay 导航表面、Live Activity、Watch 和仪表导航输出；PTMotoInfoViewController 增加可滚动自适应仪表首页、车辆摘要、可见性门禁和断连重置；新增导航进度与首页状态测试。PTSpeed iOS Debug generic build 已通过；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；XCTest 实际执行、签名发布、真机/真车验证待补 |
| 2026-09-07 | 当前工作区 Build 52 | B52-00～B52-05 已接入：Now Playing 内嵌歌词优先、用户同意后的 LRCLIB 回退、LRC/纯文本解析、骑行安全门禁、只读完整歌词页、设置开关、十语言资源和解析测试；主 App Debug generic build、独立 Watch target build 与 Tests `build-for-testing` 通过；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；XCTest 实际运行受当前 scheme/目标仅支持真机配置限制，签名发布、真实 Apple Music/网络/骑行验证待补 |
| 2026-09-08 | 当前工作区 Build 53 | B53-00～B53-06 已接入：统一只读车辆遥测投影与来源/新鲜度边界、车库自动同步和里程/保养数据隔离、真实数据轮速一致性与电瓶阶段摘要、PTT 会话/头像生命周期收口、开发者嗅探器按需挂载、MetricKit 诊断、LiDAR MainActor 修正和仪表配置请求档案；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；主 App Debug generic build 与 Tests `build-for-testing` 通过，XCTest 实际执行、签名发布、真实设备/车辆验证待补 |
| 2026-09-08 | 当前工作区 Build 55 | B54-01～B54-06 与 B55-01～B55-04 已接入：电瓶趋势、转向灯/ABS 安全提醒、支架校准、仪表配置安全门禁、统一诊断健康报告、TipKit 上下文提示、A/B/A 协议证据向导、窗口评分、BLE/OBD 会话关联和只读 ECU 指纹；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；主 App Debug generic build 已通过，XCTest 实际执行、签名发布、真实设备/车辆和 Dev 实验仍待补 |
| 2026-09-08 | 当前工作区 Build 56 | B56-01～B56-07 已接入：骑行历史紧凑摘要、专业事实分析、限量遥测图表、同车历史基线、事件跳转、脱敏摘要/JSON 分享和数据质量提示；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；主 App Debug generic build 与 Tests build-for-testing 已通过，XCTest 实际执行被 Pods 真机签名配置阻断，签名发布、真机与大数据量验证待补 |
| 2026-09-14 | 当前工作区 Build 61 | B61-00～B61-15 已接入：版本/Blueprint 门禁、Telemetry Consumer/Projection、Instruments Provider Registry、Evidence/CAN/Passport 边界与兼容编解码；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；静态检查、主 App Debug generic build 与 Tests build-for-testing 已通过，XCTest 实际运行受当前模拟器架构/Pods 产物环境阻断，签名发布、真实设备/车辆验证待补 |
| 2026-09-14 | 当前工作区 Build 62 | B62-01～B62-12 已接入：SQLite Evidence 数据库、UserDefaults 事务迁移与回滚、保留策略/空间统计、CrazyTrace Schema 2 目录包、确定性回放断言、XP400/OBD/YMOBD/OTA 离线样本和 CI 检查；营销版本仍为 2.0.8，三个 BLE/OBD 核心文件零字节变化；版本门禁、工程文件校验、Swift 语法解析、数据库/Trace/Retention 独立类型检查和模拟器验证通过；完整 `build-for-testing` 被现有 SmartCodable 宏插件拉取 `swift-syntax` 的网络超时阻断，XCTest 实际运行、签名发布、真实设备/车辆验证待补 |
| 2026-09-15 | 当前工作区 Build 63 | B63-01～B63-11 已接入：多 Trial Experiment 与原子研究存储、可解释重复性/背景误报评分、统计报告、候选 Signal Catalog 与显式晋级、CAN/BLE/OBD/Telemetry 时间线关联、Evidence 可追溯关系图、12 个只读研究模板和 CrazyTrace 确定性回放；三个 BLE/OBD 核心文件零字节变化；Swift 解析、类型检查、固定离线回放、项目版本/工程文件检查和主 App/Tests `build-for-testing` 通过；XCTest 实际运行受当前 Pods 排除 arm64 Simulator 且可用模拟器为 arm64 的环境限制，真机/实车验证待补 |
| 2026-09-15 | 当前工作区 Build 64 | B64-01～B64-11 已接入：XP400 ECU/诊断适配器身份模型、证据优先级、只读 DID 目录、只读 ECU 枚举策略、拓扑图、Passport 兼容投影、身份差异和本地 Actor 存储；三个 BLE/OBD 核心文件零字节变化；版本门禁、Swift 解析、身份模型/目录/解析器/存储测试编译与主 App `build-for-testing` 已接入，XCTest 实际执行仍受当前 Pods/模拟器架构限制，真机/实车验证待补 |
| 2026-09-15 | 当前工作区 Build 65 | B65-01～B65-11 外围能力已接入：并发归属矩阵、目标模型 Sendable/nonisolated、PTSpeedTests Swift 6 strict concurrency 入口、Trace 有界流式写入/批量读取、Evidence 分页、原子临时文件恢复、Release Safety/Privacy 策略、确定性异常语料、版本门禁、CI 与验收文档；三个 BLE/OBD 核心文件零字节变化；主 App 完整编译、XCTest 实际运行、签名发布、4 小时 soak、OTA 和 XP400+YMOBD 真机验证待补 |
| 2026-09-15 | 当前工作区 Build 66 | B66-00～B66-12 已接入：GPS 速度质量校验与平滑、XP400/OBD/GPS 统一速度 Resolver、过期即时回退、两次有效样本接管、Replay 覆盖、主仪表、`PTMotoInfoViewController` 和 Peugeot 仪表单一消费路径、Unified Speed Instruments、回滚开关和离线测试；三个 BLE/OBD 核心文件零字节变化；静态检查与 Debug 目标构建已通过，真实 iPhone/GPS/OBD/XP400 切源、后台和签名发布验证待补 |
| 2026-09-15 | 当前工作区 Build 67 | B67-00～B67-08 已接入：Data2 RTC/Engine 位纠偏、未知高位停止传播、TCS Ready 修复、Control rolling counter、ABS raw/unknown 安全模型、分级协议日志、有界快照、命名 Marker、Mock 和纯数据回归；三个 BLE/OBD 核心文件零字节变化；Build67 静态门禁已接入，真实仪表/道路、专项 A/B 采样和签名发布验证待补 |
| 2026-09-16 | 当前工作区 Build 68 | B68-00～B68-10 已接入：只读 DTC/Freeze Frame、Mode 01/02/06/09 能力、ECU CALID/CVN/Firmware Fingerprint、011F 发动机运行时间、PID42/ATRV 电压、Relative Throttle、NO DATA 语义、基线/轮询建议、地址证据、Trace 脱敏、Diagnostic Center/车库/Evidence 接入与纯数据回归；三个 BLE/OBD 稳定核心文件保持零字节变化；主 App Debug `build-for-testing` 已通过，五类实车 Trial、断连恢复、签名发布和 TestFlight 验收待补 |
