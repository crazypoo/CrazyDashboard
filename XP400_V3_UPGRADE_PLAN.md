# XP400 Ride 2.0.8 Build 持续升级计划

> 适用项目：`/Users/jax/ST/CrazyDashboard`
>
> 发布方式：只维护现有 `PTSpeed` TestFlight 版本，不新增 Lab Scheme、App Target、Bundle ID 或第二发布渠道；当前没有 App Store 上架计划。
>
> 版本规则：`MARKETING_VERSION` 固定为 `2.0.8`，以后只递增 `CURRENT_PROJECT_VERSION`（Build）。当前主 App、Widget、Watch 为 Build 36，下一次 TestFlight 从 Build 37 开始。
>
> 文件名中的 `V3` 仅为保留现有路径和链接，不代表需要修改 App 大版本号。
>
> 本文件是实施清单。开始编码前可以直接增加、删除或调整条目；实施后只有在对应验收全部通过时才勾选 `✅`。

## 0. 状态规则与想法编辑区

### 状态

- `⬜`：未开始。
- `🟨`：正在实施。
- `✅`：代码、测试和对应验证全部完成。
- `⛔`：缺少硬件、协议、权限或其他外部条件。
- `🗑️`：由项目负责人明确取消，不再实施。

静态检查、单元测试、目标编译、完整 Archive、真机、Apple Watch、实车和台架验证必须分别记录，不能互相替代。

### 新想法暂存

- [ ] 新想法：
- [ ] 新想法：
- [ ] 待讨论或准备删除：

---

## 1. 2.0.8 Build 升级目标

全部功能继续在版本 `2.0.8` 下通过不同 Build 逐步交付：

- **稳定与诊断 Builds**：性能优化、连接协调层、只读诊断和 CAN 实验室。
- **骑行体验 Builds**：行程回放、续航预测、维护建议、PTT、Watch 和组队骑行增强。
- **仪表增强 Builds**：普通界面只加入已经反复验证、可逆、具有恢复路径的 XP400 GT 仪表操作。
- **开发者实车测试**：同一 `PTSpeed` TestFlight 包内提供受控开发者模式，用于调用高风险仪表指令和刷写流程。

### 版本与 Build 规则

- [ ] `PTSpeed`、Widget 和 Watch 的 `MARKETING_VERSION` 永久保持 `2.0.8`。
- [ ] 当前主 App、Widget、Watch Build 基线为 `36`；下一次 TestFlight 使用 Build `37`。
- [ ] 每次上传 TestFlight 只将 `CURRENT_PROJECT_VERSION` 加一：37、38、39……
- [ ] App、Widget 和 Watch 每次使用完全相同的 Build 号，避免嵌入扩展版本不一致。
- [ ] Tests Target 当前 Build 35，在首次实施时同步到主 App Build，此后一起递增。
- [ ] 不允许脚本、Archive 或 CI 自动修改 `MARKETING_VERSION`。
- [ ] 设置页和诊断报告显示格式统一为 `2.0.8 (Build N)`。
- [ ] 不把 Build 号加入仪表 BLE 认证、握手、广播或配置数据。
- [ ] 每个新 Build 都与 Build 36 的仪表 BLE 握手和连接结果做回归对比。

### 单渠道发布约束

- 只保留现有 `PTSpeed` Scheme、App Target 和 `com.yd.PTSpeed` Bundle ID。
- 不创建 `PTSpeedLab`、实验 App、第二套签名或第二个发布包。
- 现有 Widget 和 Watch App 继续作为 `PTSpeed` 的扩展维护，不建立另一套 Companion 配置。
- 普通 TestFlight 使用界面保持只读；未确认的仪表命令、主动 Fuzz、Seed-Key、固件写入和内存写入不进入普通 UI。
- 高风险方法由开发者在现有 `PTECUSnifferOverlay` 工具界面打开开关后调用，不新增开发者中心或授权系统。
- 继续复用四指长按入口和 `PTMotoUserDefaultStruct.BleTestDataGet` 开发者模式状态。
- 本计划不实现发动机 ECU 动力调校。

---

## 2. 不可修改的核心文件

以下三个文件的逻辑、格式和注释均不得修改：

| 文件 | 当前 SHA-256 |
|---|---|
| `Global/BLE/PTBluetoothManager.swift` | `8a1ce464f87076041b7d1c2af0940f0a014bad7d0479ae6d108914cb81d270d7` |
| `Global/OBD/Function/PTHiddenOBDConnector.swift` | `23ea459f87a4003248cc2c303f25a42c23a24909aa777b21b93ae2a99c41cd99` |
| `Global/OBD/Function/PTOBDCommand.swift` | `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66` |

实施要求：

- [ ] 在第一条代码变更前再次记录三个文件的哈希。
- [ ] 每个工作包完成后检查三个文件 Git diff 为零。
- [ ] 每次合并或发布前复核 SHA-256。
- [ ] 任一核心文件发生变化时立即停止当前工作包，先恢复核心文件，再继续外围修改。
- [ ] 不复制核心内部的连接、分片、认证、轮询、ISO-TP 或 PID 解码逻辑。

---

## 3. CoreBluetooth 逻辑合拼方案

### 结论

不把三个核心文件物理合并：

- `PTBluetoothManager.swift` 内的 `PTBluetoothServerManager` 使用 `CBPeripheralManager`，iPhone 向 XP400 仪表提供 BLE 外设服务。
- `PTHiddenOBDConnector.swift` 使用 `CBCentralManager`，iPhone 主动扫描并连接 OBD 适配器。
- `PTOBDCommand.swift` 不使用 CoreBluetooth，只负责命令定义、单位和车辆数据解码。

Apple 将 Central 与 Peripheral 定义为不同角色和状态机，因此只做协调层合拼，不创建第三套 Bluetooth Manager：

- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth/)
- [CBCentralManager](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager)
- [CBPeripheralManager](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager)

### 新增统一协调层

新增 `@MainActor PTVehicleConnectivityCoordinator`：

- [ ] 内部只包装 `PTBluetoothServerManager.shared` 和 `PTMotoTelemetryManager.shared`。
- [ ] 不直接创建 `CBCentralManager` 或 `CBPeripheralManager`。
- [ ] 统一提供仪表连接、OBD 连接、断开、前后台恢复和自动连接状态。
- [ ] 仪表 BLE 与 OBD BLE 可同时工作；一方失败不得清理另一方。
- [ ] App 启动时不自动扫描 OBD，除非用户明确开启 OBD 自动连接。
- [ ] 仪表广播只在已配对、导航、行程或用户明确连接时启动。
- [ ] 新 UI 通过协调层连接；旧公开 API 暂时保留兼容。
- [ ] 迁移完成后，静态搜索确保普通 UI 不再直接调用核心连接方法。

新增只读状态模型：

```swift
public struct PTVehicleSnapshot: Sendable, Equatable
public enum PTDashboardLinkState: Sendable, Equatable
public enum PTOBDLinkState: Sendable, Equatable
```

`PTVehicleSnapshot` 统一承载仪表连接、OBD 连接、车速、燃油、里程、更新时间和数据来源，供 Dashboard、CarPlay、Widget、Watch 和 Live Activity 使用。

### 高级 OBD 串行门禁

复用现有 `PTAdvancedOBDCoordinator`，不新增第二个协调器：

- [ ] 改为串行 actor，确保同一时刻只有一个高级 OBD 任务。
- [ ] 内部继续调用稳定核心现有的 `performExclusiveTask`。
- [ ] 禁止嵌套总线独占任务。
- [ ] 取消、超时或断连后只恢复一次 Header、Sniffer 和轮询。
- [ ] 所有任务返回结构化结果、进度、取消状态和失败原因。
- [ ] 不新增传输层、轮询器或响应拼接器。

### 复用现有 Dev 工具界面

现有开发者链路已经完整存在：

- `PTMotoInfoViewController` 使用四指长按 1.5 秒打开开发者模式。
- `SceneDelegate` 已挂载 `PTECUSnifferOverlay`。
- `PTMotoUserDefaultStruct.BleTestDataGet` 已记录开发者工具显示状态。
- `PTECUSnifferOverlay` 已包含日志、过滤、导出和自动 Fuzz 控件。

本计划只在现有界面增加一个“允许高风险 OBD/仪表操作”开关：

- [ ] 开关默认关闭，打开前显示一次明确的仪表损坏风险确认。
- [ ] 在 `PTMotoUserDefaultStruct` 增加 `DevHighRiskOBDEnabled`，默认值为 `false`；`BleTestDataGet` 继续只负责 Overlay 显示状态。
- [ ] 开关状态直接读写 `DevHighRiskOBDEnabled`，不新增 Keychain、CryptoKit、授权文件、安装 ID 或第二个开发者中心。
- [ ] App 每次启动、关闭 `PTECUSnifferOverlay`、进入后台、OBD 断开或刷写任务结束时自动关闭开关。
- [ ] `writeDashboardConfig`、`testPSABootLogoCommands`、OTA 和仪表 Flasher 在执行前检查该开关。
- [ ] 开关关闭时保持当前只读拒绝行为，不发送任何高风险帧。
- [ ] 开关打开后，开发者可以直接从 Dev 工具按钮调用，也可以在测试代码中调用现有高风险方法。
- [ ] 原始 Hex、Fuzz 和刷写分别使用独立按钮，避免误触“一键全部执行”。
- [ ] 现有 `Find commond` 自动 Fuzz 按钮也必须受高风险开关控制，并补充停止状态提示。
- [ ] 继续复用 `PTAdvancedOBDCoordinator` 串行执行任务，不新增高风险调用网关。

每次真实发送前必须通过：

- [ ] App 位于前台并保持屏幕常亮。
- [ ] 车辆速度为零、发动机转速为零，目标 ECU 身份与授权一致。
- [ ] OBD/CAN 适配器已通过该操作需要的流控、延迟、吞吐和最大块长度测试。
- [ ] 供电达到协议档案中的厂商要求；档案没有阈值时禁止进入擦除阶段。
- [ ] 已保存当前配置、原始数据或可用固件，并完成读取校验。
- [ ] 所有普通 OBD 轮询、CAN Sniffer、导航指令和其他总线任务已经暂停。
- [ ] 固件、分区、地址范围和预期 ECU 版本完全匹配。
- [ ] 开发者进行第二次确认，并看到当前步骤是否可取消及失败恢复方式。

执行过程中：

- [ ] 记录每个发送帧、响应、耗时、NRC、重试和状态转换，敏感 Key 只记录摘要。
- [ ] 擦除前允许安全取消；擦除后使用阶段化恢复流程，不提供会造成半写入的普通取消按钮。
- [ ] App 退到后台、连接质量下降、供电异常或 ECU 身份变化时按当前阶段停止或进入恢复流程。
- [ ] 结果明确区分 dry-run、已发送、已写入、已校验、已回滚和未知状态。
- [ ] 任何未知状态都禁止继续下一个写入步骤。

---

## 4. 工作包总表

只有“完成条件”全部满足后，才能将对应项目改为 `✅`。

| 状态 | ID | 工作包 | 依赖 | 完成条件摘要 |
|---|---|---|---|---|
| ⬜ | `B208-00`` | 基线、计划与核心保护 | 无 | 建立性能基线、测试矩阵和核心哈希门禁。 |
| 🗑️ | `B208-01` | QWeather | 无 | 用户确认当前实现可用，本计划不检查、不修改。 |
| 🗑️ | `B208-02` | 依赖与 Swift 版本 | 无 | 由项目负责人独立处理，本计划不实施、不验收。 |
| ⬜ | `B208-03` | 车辆连接统一协调层 | B208-00 | 双 BLE 角色并行且互不干扰，核心零修改。 |
| ⬜ | `B208-04` | 冷启动与运行性能 | B208-03 | 无非必要启动任务，CarPlay 和列表卡顿明显下降。 |
| ⬜ | `B208-05` | Trip、GPX、iCloud 与缩略图 | B208-00 | 无主线程云端/大文件 I/O，保存和恢复可靠。 |
| ⬜ | `B208-06` | PTT、Live Activity、Widget、Watch | B208-00 | 零成员零 Activity，有成员最多一个，状态来源统一。 |
| ⬜ | `B208-07` | 普通诊断、Dev 高风险开关与 CAN 实验室 | B208-03 | 普通界面只读；高风险操作只能在现有 Dev 工具开关打开后调用。 |
| ⬜ | `B208-08` | 骑行体验功能 | B208-03、B208-05、B208-06 | 完成座舱、续航、回放、维护和组队功能。 |
| ⬜ | `B208-09` | XP400 仪表指令证据库 | B208-07 | 普通界面只用 Confirmed 指令；开发者可通过 Dev 开关测试 DevTest。 |
| ⬜ | `B208-10` | 开发者固件与开机画面实车测试 | B208-07、B208-09 | 同一 TestFlight 包内通过现有 Dev 工具执行，具有前置检查、日志和恢复步骤。 |
| ⬜ | `B208-11` | 隐私、Archive 与 TestFlight 发布 | B208-00、B208-03～B208-08、B208-12 | 完整构建、真机、Watch、BLE、普通模式和开发者模式验证通过。 |
| ⬜ | `B208-12` | String Catalog 本地化与语言文案 | B208-00 | 使用新 Xcode 多语言方式，四种现有语言完整覆盖，`languageFunc` 不再接收中文硬编码。 |

普通功能发布不等待 `B208-10`；开发者刷写仍可在同一个 TestFlight 包中逐步验证，但其失败不得阻塞普通功能交付。

---

## 5. `B208-00` 基线与实施门禁

- [ ] 记录当前 Git commit、Xcode、Swift、iOS SDK 和依赖版本。
- [ ] 记录 App、Widget、Watch、Tests 当前构建结果。
- [ ] 使用 Instruments 记录冷启动、主线程、内存、卡顿和能耗基线。
- [ ] 记录仪表 BLE 与 OBD 蓝牙/Wi-Fi 的连接时间、成功率和断连恢复行为。
- [ ] 记录 PTT、Live Activity、Widget、Watch 和 iCloud 当前行为。
- [ ] 所有新写代码注释使用英语、西班牙语、中文三语。
- [ ] 只补充当前修改范围中的旧注释，不做全仓库注释翻译。

完成证据：

- Commit：
- 测试结果：
- 性能基线：
- 真机/车辆状态：

---

## 6. `B208-01` QWeather（🗑️ 本计划忽略）

用户已确认当前 QWeather 使用方式可以正常工作。

- 本计划不修改 `AppDelegate`、`PTWeatherManager`、Secrets 配置或 QWeather SDK 初始化。
- 其他工作包不得顺手重构天气代码。
- 除非用户重新开启该项，否则不做检查、修复或验收。

---

## 7. `B208-02` 依赖与 Swift 版本（🗑️ 用户自行处理）

- 该项由项目负责人独立实施。
- 本计划不修改 `Podfile`、`Podfile.lock`、`Package.resolved`、SwiftDate、`SWIFT_VERSION` 或严格并发配置。
- `B208-03` 及后续工作包不依赖本项。
- 项目负责人完成相关调整后，只刷新构建基线；不由本计划代为标记本工作包完成。

---

## 8. `B208-03` 车辆连接协调层

- [ ] 实现 `PTVehicleConnectivityCoordinator` 和 `PTVehicleSnapshot`。
- [ ] 建立仪表 BLE、OBD BLE/Wi-Fi/Mock 的独立状态机映射。
- [ ] App 启动不再隐式启动 OBD 扫描。
- [ ] 只有用户设置允许时才执行 OBD 自动连接。
- [ ] 仪表 BLE 与 OBD BLE 同时运行时互不停止、重置或复用对方状态。
- [ ] 一个连接失败只更新自己的错误状态。
- [ ] 前后台切换按照实际功能需求恢复，不无条件重连全部服务。
- [ ] 页面离开后正确释放 delegate、Timer 和观察者。
- [ ] Dashboard、CarPlay、Widget、Watch 使用同一车辆快照。

完成条件：

- [ ] 三个核心文件哈希不变。
- [ ] 50 次仪表 BLE 连接/断开循环无状态泄漏。
- [ ] 50 次 OBD 连接/断开循环无重复扫描或重复轮询。
- [ ] 30 次仪表 BLE 与 OBD BLE 并行循环通过。

---

## 9. `B208-04` 性能优化

### 冷启动

- [ ] 移除 `AppDelegate` 对 Trip、GPX、Location、PTT 和诊断 Manager 的无条件实例化。
- [ ] 功能由用户进入页面、开始导航、连接车辆或明确后台设置时按需启动。
- [ ] PTT 默认不恢复组网；新增“恢复上次对讲状态”设置，默认关闭。
- [ ] OBD 默认不扫描；仪表 BLE 遵循已配对和用户设置。

### CarPlay 与 Dashboard

- [ ] 删除静止状态下 60 Hz 强制 `setNeedsDisplay()`。
- [ ] 优先使用地图 SDK 原生刷新。
- [ ] 必须使用补偿刷新时最高 15 FPS，并在静止、后台、断开和退出导航时销毁。
- [ ] Dashboard 根据数据变化刷新，不重复构建完整界面。
- [ ] Tab 控制器只创建一次，语言和主题变化只更新配置。

### 长列表与图片

- [ ] Trip Cell 不创建地图实例。
- [ ] 删除固定等待一秒的缩略图生成流程。
- [ ] 使用可取消任务和缓存，Cell 复用时校验记录 ID。
- [ ] 图片解码、轨迹简化和文件写入离开主线程。

性能目标：

- [ ] 冷启动 p95 较基线至少改善 25%。
- [ ] 启动后无非用户授权的 OBD 扫描或 PTT 组网。
- [ ] 行程列表超过 100 ms 的卡顿较基线减少 80%。
- [ ] 静止 CarPlay 不再持续触发 60 Hz 重绘。
- [ ] BLE/OBD 连接成功率和数据正确性不低于基线。

---

## 10. `B208-05` Trip、GPX、iCloud 与缩略图

- [ ] 使用串行 actor 管理 Trip、GPX、Widget 快照和 iCloud 文件写入。
- [ ] 采用临时文件加原子替换，防止中途写入损坏 JSON。
- [ ] iCloud 文件未下载完成时等待状态变化，不立即复制占位文件。
- [ ] 提供 iCloud 不可用、下载超时、冲突和损坏数据错误。
- [ ] 保留最后一份有效本地数据，云端失败不得覆盖本地。
- [ ] 大型 JSON 编解码和文件操作不占用主线程。
- [ ] 删除、恢复、迁移和旧格式兼容都有单元测试。
- [ ] Widget、Watch 和主 App 使用同一状态模型和同一字段含义。

完成条件：

- [ ] 离线、iCloud 关闭、延迟下载、损坏 JSON 和冲突场景不丢数据。
- [ ] 一千条行程加载和滚动达到性能目标。
- [ ] 快速滚动无错图、重复图片或 Cell 状态串线。

---

## 11. `B208-06` PTT、Live Activity、Widget 与 Watch

### PTT 与 Live Activity

- [ ] `PTLiveActivityManager` 的可变状态统一在 `@MainActor` 管理。
- [ ] 只有 `connectedPeersCount > 0` 才能创建 PTT Live Activity。
- [ ] 零成员时立即结束所有遗留 PTT Activity。
- [ ] 有成员时系统中最多存在一个 PTT Activity。
- [ ] App 重启先对系统 Activity 做一次状态协调，不盲目新建。
- [ ] 成员加入、离开、掉线和重新连接都触发同一个同步入口。
- [ ] PTT 未运行、权限拒绝或音频会话失败时不显示虚假在线状态。
- [ ] 移除只依赖 `print` 的观测，增加结构化状态和错误记录。

### Widget 与 Watch

- [ ] `PTWidgetDataManager`、Widget、Watch 继续使用同一 `PTWidgetSharedStatus`。
- [ ] WatchConnectivity 未激活时只保留最新状态。
- [ ] Watch 离线后重连只接收最新快照，不积累过期队列。
- [ ] Watch App 重启恢复最近一次 application context。
- [ ] Widget 与 Watch 无数据时显示明确占位状态。
- [ ] 不改变现有 Watch Companion Bundle ID 和嵌入关系。

完成条件：

- [ ] 0 个成员时始终 0 个 PTT Activity。
- [ ] 1 个以上成员时始终最多 1 个 PTT Activity。
- [ ] 覆盖 App 重启、权限拒绝、成员抖动和系统禁止 Live Activity。
- [ ] 真机与配对 Apple Watch 完成前台、后台、离线和重启验证。

---

## 12. `B208-07` 普通诊断、Dev 高风险开关与 CAN 实验室

### 普通使用模式

普通 TestFlight 使用界面只允许：

- 标准 OBD 实时数据。
- 已确认、待定和永久 DTC。
- VIN、Freeze Frame、Mode 6 和 ECU 身份信息。
- 已验证节点上的白名单 DID 读取。
- 被动 CAN Capture、导出和离线分析。

普通使用模式禁止：

- UDS 写入、内存写入、SecurityAccess、RoutineControl 和固件下载。
- 主动 Fuzz、自动未知命令扫描和无范围限制的全车 Dump。
- UI 直接调用裸 Hex 写命令。
- 使用模拟返回值宣称车辆或固件已经受支持。

### Dev 高风险模式

开发者在 `PTECUSnifferOverlay` 打开高风险开关后可以测试：

- DID/配置写入与读取回验。
- 已定义范围内的 SecurityAccess 流程。
- 已定义 RoutineControl、内存操作和恢复例程。
- 仪表固件升级的会话切换、擦除、下载、分块传输、校验和复位。
- 开机画面预设值或固件资源替换实验。
- 单次原始 Hex 指令、受限 Fuzz 和故障注入。

这些能力继续经过 `PTAdvancedOBDCoordinator` 串行执行，并保留车辆状态、供电、适配器能力、地址范围、固件哈希、日志和恢复检查。

实施条目：

- [ ] `PTOBDiagnosticAddress` 成为诊断地址唯一模型来源。
- [ ] `PTUDSReadService` 统一解析 `62` 正响应、`7F` 否定响应和 NRC。
- [ ] 批量读取支持进度、取消、超时、速率限制和失败节点记录。
- [ ] 所有只读任务经过 `PTAdvancedOBDCoordinator` 串行门禁。
- [ ] CAN Frame 正确区分 Header、DLC、Payload 和 ISO-TP 元数据。
- [ ] 修正 29-bit Header 数值范围验证。
- [ ] JSONL 实时写入错误可传回 UI，不只记录日志。
- [ ] CAN 内存使用固定容量环形缓存，完整 Frame 流式写盘。
- [ ] 支持 Capture 历史、事件标记、JSON/CSV、Capture Diff、Byte/Bit Diff 和事件窗口。
- [ ] 使用现有 Mock 连接和 Capture 文件做离线回放。
- [ ] 继续使用现有四指长按手势显示 `PTECUSnifferOverlay`，不创建新入口。
- [ ] 在 Overlay 中增加高风险总开关和各项操作按钮。
- [ ] `PTDashboardHacker` 继续作为兼容门面：只读方法转发到读取服务，高风险方法先检查 Dev 开关。
- [ ] Dev 开关关闭时，高风险方法返回结构化拒绝错误且不发送帧。
- [ ] 受限 Fuzz 默认单次发送；批量测试仍需填写范围、速率、总次数和停止条件。

完成条件：

- [ ] 普通 UI 全流程抓包证明没有写入、解锁、Routine 或下载帧。
- [ ] Dev 模式抓包证明所有高风险帧都发生在开关开启期间，并具有操作记录和恢复状态。
- [ ] 任务取消、失败和断连后轮询只恢复一次。
- [ ] 无遗留 Sniffer、自定义 Header 或暂停状态。
- [ ] 诊断结果不依赖日志，可导出结构化报告。

---

## 13. `B208-08` 骑行体验功能

### 第一批 2.0.8 Builds 功能

- [ ] **统一骑行座舱**：仪表、OBD、导航、天气、行程和 PTT 状态集中展示。
- [ ] **车辆连接中心**：分别显示仪表 BLE、OBD、Watch 和 iCloud 状态及失败原因。
- [ ] **只读诊断中心**：DTC、VIN、Freeze Frame、Mode 6、DID 和报告导出。
- [ ] **CAN 实验室**：过滤、事件标记、对比、离线回放和候选 CAN ID。

### 后续 2.0.8 Builds 功能

- [ ] **Moto Black Box**：保存事件前 60 秒和后 30 秒的 GPS、车辆状态与手动标记；默认本地存储，不自动上传。
- [ ] **智能续航**：根据近期油耗、速度、坡度和路线估算剩余续航与加油建议。
- [ ] **ADV Roadbook**：GPX 路书、岔路备注、越野点位和离线骑行记录。
- [ ] **行程故事**：地图回放、速度/海拔/油耗曲线、照片和事件时间轴。
- [ ] **预测维护**：根据里程、时间、DTC 和电压趋势生成维护提醒，不替代专业检修。
- [ ] **组队骑行**：危险路况标记、成员掉队提醒、低延迟 PTT 状态和停车点共享。
- [ ] **Apple Watch 骑行助手**：连接、燃油、里程、停车位置、导航震动和骑行摘要。
- [ ] **多车库**：为不同摩托保存设置、维护记录、油耗模型和诊断报告。

候选想法，可在实施前删除：

- [ ] 弯道与坡度骑行统计，仅作骑行复盘，不鼓励竞速。
- [ ] 轮胎、胎压和悬挂的手动配置档案。
- [ ] 雨天、低温、大风和低能见度路线提醒。
- [ ] Siri/App Intents 快速开始导航、行程和 PTT。
- [ ] 停车防盗时间轴与最后一次车辆状态快照。

---

## 14. `B208-09` XP400 GT 仪表指令研究

Peugeot 官方资料确认 XP400 GT 使用 5 英寸连接式 TFT 和 i-Connect，但公开产品资料和用户手册没有给出刷写协议、Seed-Key、固件签名或开机画面 DID：

- [XP400 官方页面](https://www.peugeot-motocycles.fr/model/xp-400/27)
- [XP400 用户手册](https://static.peugeot-motocycles.fr/files/documents/6a0b0d18600ca468212172.pdf)

因此每一条仪表指令必须记录证据等级：

- `Confirmed`：重复抓包、响应、效果和还原均一致。
- `Observed`：只观察到一次，不能进入普通 UI。
- `DevTest`：已补齐目标、预期响应、停止条件和恢复步骤，可在 Dev 高风险开关开启时测试。
- `Hypothesis`：根据差异推断，只允许离线分析；进入实车测试前必须先升级为 `DevTest`。
- `Rejected`：已证明无效或风险过高。

研究条目：

- [ ] 整理核心现有颜色、单位、语言、欢迎文字和导航帧行为。
- [ ] 为每项已知配置记录修改前、修改后和恢复后的 BLE/CAN Capture。
- [ ] 建立帧字段、方向、触发条件、响应、超时和恢复方法清单。
- [ ] 研究亮度、主题预设、时钟和维护页面，但初始状态一律标记为 `Hypothesis`。
- [ ] 判断开机画面属于预设 Logo 枚举还是固件资源图片。
- [ ] 至少三次独立会话得到一致结果后，才能从 `Observed` 升为 `Confirmed`。
- [ ] `Observed` 或 `Hypothesis` 只有在补齐测试范围、预期响应、停止条件和恢复步骤后才能成为 `DevTest`。
- [ ] `DevTest` 只能在开发者工具高风险开关开启时调用，不能进入普通 UI。
- [ ] 只有 `Confirmed`、可逆且具备恢复步骤的操作才可进入普通 UI。
- [ ] 所有仪表设置只允许停车状态操作，并显示原值和恢复按钮。

完成条件：

- [ ] 没有臆测的 CAN ID、DID、Key、Checksum 或 Payload。
- [ ] 每个公开操作都有原始证据、响应验证和恢复步骤。
- [ ] 任一失败都不会影响导航、仪表连接或正常骑行显示。

---

## 15. `B208-10` 开发者固件与开机画面真实环境测试

### 允许范围

- 在同一个 `PTSpeed` TestFlight 包中实现开发者刷写入口，不创建第二个 App。
- 开发者可从现有 `PTECUSnifferOverlay` 开启高风险开关，执行仪表配置写入、开机画面实验和固件升级流程。
- 所有高风险方法先检查 Dev 开关，再通过现有 `PTAdvancedOBDCoordinator` 串行执行。
- 普通 TestFlight 使用模式继续保持只读。
- 继续禁止发动机 ECU 动力调校、未知目标盲刷和 Seed-Key 暴力破解。

### 实施步骤

- [ ] 记录仪表 ECU、硬件、软件和协议身份信息。
- [ ] 被动采集合法升级或原厂工具通信，建立可重放的协议状态模型。
- [ ] 对合法取得的固件包做离线容器、分区、资源和字符串分析。
- [ ] 记录原文件 SHA-256、大小、块结构、Checksum、签名和压缩信息。
- [ ] 搜索开机画面资源并判断是否受签名覆盖。
- [ ] 为诊断会话、安全访问、例程、擦除、下载、分块传输、退出、校验和复位建立状态模型。
- [ ] 先用 Mock 和离线 Capture 验证完整状态机、NRC、超时、重试和恢复分支。
- [ ] 在实车上先执行只读身份、会话与适配器能力测试。
- [ ] 对 DID/配置写入先做单字段、可读回、可恢复的小范围测试。
- [ ] 开机画面若为预设值，先读取原值、写入候选值、读取验证并恢复原值。
- [ ] 开机画面若属于固件资源，必须先完成固件重建、Checksum/签名验证和恢复镜像准备。
- [ ] 固件升级按阶段开放：握手 dry-run → 会话验证 → 小块传输测试 → 完整升级 → 启动验证 → 回滚。
- [ ] 每次实车操作自动生成包含授权、车辆、适配器、固件、发送/响应和结果的测试报告。

### 高风险分级

- **Level A：配置写入**。允许对具备原值、读取回验和恢复命令的单个 DID/配置进行实车测试。
- **Level B：安全会话与例程**。允许测试已知 SecurityAccess、Routine 和受限内存范围，必须有明确退出和恢复步骤。
- **Level C：完整仪表固件**。允许擦除和下载，但必须同时具备原始固件、固件兼容性证明、适配器能力证明、稳定供电和独立恢复方式。

### 执行前置条件

- [ ] `PTECUSnifferOverlay` 已显示且高风险开关已开启。
- [ ] 开发者已确认本次 Level、ECU、地址和固件哈希。
- [ ] 原始配置或原始固件已经保存并完成读取校验。
- [ ] 目标硬件/软件版本与操作档案完全匹配。
- [ ] 具备可靠流控的 CAN 设备；ELM327 只有在通过持续吞吐、延迟、流控、分块和断连测试后才能用于对应 Level。
- [ ] 合法原厂固件、服务资料或完整升级抓包。
- [ ] 厂商规定的稳定供电条件。
- [ ] 独立于主刷写路径的恢复方式。
- [ ] 合法 Seed-Key 来源。
- [ ] 先在 Mock/Capture 完成擦除、传输、校验和复位阶段的中断恢复测试。
- [ ] Level C 首次实车执行前至少完成一次恢复路径演练；有备件仪表和台架时优先在台架完成。
- [ ] 开发者明确确认真实环境可能导致仪表无法启动并承担恢复处理。

当前状态：`⬜ 允许开发者模式逐级实车测试；现有 ELM327 必须先通过能力测试，未通过时只能执行该适配器可安全承载的较低 Level。`

---

## 16. `B208-11` 测试、隐私与发布

### 自动化测试

- [ ] 新增明确的 Test Plan 和 UI Test Target。
- [ ] 覆盖 11-bit、29-bit、DLC、非法 CAN Frame 和 ISO-TP。
- [ ] 覆盖 UDS `62` 正响应、`7F` 否定响应、NRC、超时和多帧。
- [ ] 覆盖协调层双连接、断连、取消和前后台恢复。
- [ ] 覆盖 PTT 零成员、有成员、重复 Activity、重启和权限关闭。
- [ ] 覆盖 iCloud 离线、延迟下载、冲突、损坏 JSON 和旧格式迁移。
- [ ] 覆盖 Watch 未配对、断连、重连、重启和过期数据覆盖。
- [ ] 覆盖 Dev 高风险开关默认关闭、开启、关闭 Overlay、退后台和 OBD 断开，确保自动关闭后零帧发送。
- [ ] 覆盖 dry-run、单次写入、读取回验、恢复、阶段化取消、断连和未知结果处理。
- [ ] 覆盖未通过四指长按进入 Dev 工具时无法调用高风险操作。
- [ ] 使用 Thread Sanitizer 验证可确定复现的并发流程。

### 硬件验证

- [ ] iOS 17 最低支持版本。
- [ ] 当前最新正式 iOS。
- [ ] 配对 Apple Watch 真机。
- [ ] XP400 仪表 BLE 前后台连接。
- [ ] OBD Bluetooth、Wi-Fi 和 Mock。
- [ ] 仪表 BLE 与 OBD BLE 同时工作。
- [ ] 普通模式实车只执行被动抓包和白名单读取。
- [ ] 开发者模式在指定测试车辆按 Level A → Level B → Level C 顺序验证，并为每次操作保存完整报告。
- [ ] 当前 ELM327 完成流控、吞吐、延迟、分块、超时和断连能力测试；不满足某一级别时网关拒绝该级别操作。

### 隐私和后台能力

- [ ] 对照实际代码审核 Bluetooth、Location、Audio、CarPlay、iCloud 和 Wi-Fi Info 权限。
- [ ] 更新 Privacy Manifest 和 Required Reason API 声明。
- [ ] 未使用的后台模式和 entitlement 删除前先确认所有调用方。
- [ ] CAN、VIN、位置、行程和语音数据明确本地、iCloud 和导出边界。
- [ ] 日志默认脱敏 VIN、坐标、密钥和用户身份。

### 发布门禁

- [ ] 三个核心文件哈希保持不变。
- [ ] Archive 中 App、Widget、Watch 的 `CFBundleShortVersionString` 全部为 `2.0.8`。
- [ ] Archive 中 App、Widget、Watch 的 `CFBundleVersion` 完全一致，并高于上一个 TestFlight Build。
- [ ] 本次上传只修改 Build 号，没有修改 `MARKETING_VERSION`、Bundle ID、Watch Companion ID 或 App Group。
- [ ] 新 Build 与 Build 36 的 XP400 仪表 BLE 握手、认证、连接和配置结果一致。
- [ ] App、Widget、Watch、Tests 完成 Debug 和 Release 构建。
- [ ] 单元测试、UI Test、Archive 和导出校验通过。
- [ ] 真机、Watch、仪表 BLE、OBD、普通模式和 Dev 高风险模式回归通过。
- [ ] 无启动崩溃、数据损坏、重复 Live Activity 或连接成功率明显退化。
- [ ] Dev 高风险开关默认关闭，关闭工具、退后台和断连后不会保留开启状态。
- [ ] 保留上一稳定构建和可关闭 Live Activity、Watch 同步等非核心功能的开关。

发布顺序：

1. 内部测试。
2. 小范围 TestFlight。
3. 扩大 TestFlight。
4. TestFlight 开发者组单独验证高风险功能。
5. TestFlight 稳定组发布；当前不进入 App Store。

---

## 17. `B208-12` String Catalog 本地化与语言文案

### 目标与现状

将当前工程的 `Localizable.strings` 迁移为新 Xcode 使用的 String Catalog：`Localizable.xcstrings`。只迁移 `Localizable` 资源；`LaunchScreen.strings`、`Main.strings` 等 Storyboard 本地化资源不在本工作包内删除或改造。

当前 `PTDashboardConfig.lauguageModels` 已支持以下四种语言，迁移后必须保持原有设置项和语言选择 Key 不变：

| App 设置 Key | String Catalog Locale | 当前资源 | 显示名称 |
|---|---|---|---|
| `zh` | `zh-Hans` | `Global/zh-Hans.lproj/Localizable.strings` | 简体中文 |
| `tw` | `zh-Hant` | `Global/zh-Hant.lproj/Localizable.strings` | 繁體中文 |
| `en` | `en` | `Global/en.lproj/Localizable.strings` | English |
| `tr` | `tr` | `Global/tr.lproj/Localizable.strings` | Turkish |

### 实施步骤

- [ ] 以现有 `Localizable.strings` 的稳定 Key 为基础创建 `Localizable.xcstrings`，不随意重命名已有 Key。
- [ ] 按当前工程的 `developmentRegion = zh-Hans` 保留简体中文开发基准，并将英文、繁体中文和土耳其语完整迁移到同一个 String Catalog。
- [ ] 保留 `%@`、`%d`、`%.1f` 等格式占位符及换行、标点和特殊字符；迁移后执行占位符一致性检查。
- [ ] 从 `CrazyDashboard.xcodeproj/project.pbxproj` 移除 `Localizable.strings` 的旧 `PBXVariantGroup` 资源引用，避免旧资源与 `Localizable.xcstrings` 重复加载。
- [ ] 保持 `PTDashboardConfig.languageFunc(text:)` 的公开签名和现有调用方不变；内部改为通过 Foundation 的 String Catalog API（如 `String(localized:table:bundle:locale:)`）和当前选中语言解析文本。
- [ ] 保留 `zh` → `zh-Hans`、`tw` → `zh-Hant`、`en` → `en`、`tr` → `tr` 的映射，不新增第二套语言状态或资源查找逻辑。
- [ ] `PTDashboardConfig.language(key:_:)` 继续复用 `languageFunc`，确保带参数文案仍按当前语言格式化。
- [ ] 全仓库审查 `PTDashboardConfig.languageFunc(text:)` 的中文字面量，只将真正显示给用户的中文替换为稳定本地化 Key。
- [ ] 将 `Global/Location/PTLocationEngine.swift` 中的 `停车定位已更新` 替换为本地化 Key，例如 `parking_location_updated`。
- [ ] 将 `Global/Dashboard/Views/PTPeugeotDashBoardNavView.swift` 中的 `导航中`、`下段路名称:`、`当前路段:` 替换为本地化 Key，例如 `navigation_in_progress`、`next_road_name_prefix`、`current_road_name_prefix`。
- [ ] 为以上新增 Key 补齐简体中文、繁体中文、English 和 Turkish 四种翻译。
- [ ] 仅保留 `PTDashboardConfig.languageFunc` 的兼容门面；业务界面不直接读取 `.lproj`、不自行解析 `.strings` 或 `.xcstrings` 文件。

### 完成条件

- [ ] `Localizable.xcstrings` 包含旧 `Localizable.strings` 的全部有效 Key，且工程运行时不存在重复的 `Localizable` 资源。
- [ ] 四种现有 App 语言均能加载完整翻译；切换语言后 Dashboard、导航、位置、PTT、OBD 提示和系统弹窗不会回退成错误语言。
- [ ] `PTDashboardConfig.languageFunc(text:)` 的现有调用无需修改即可正常工作，未找到 Key 时保留可诊断的安全回退，不发生崩溃。
- [ ] Swift 源码中传给 `PTDashboardConfig.languageFunc(text:)` 的中文用户文案字面量为零；注释、协议原始数据和本地化资源中的翻译文本不计入此项。
- [ ] 所有带参数文案的占位符数量和类型一致，中文、英文、繁体中文和土耳其语均通过格式化测试。
- [ ] App、Widget、Watch 和 Tests 的构建资源没有误引用旧 `Localizable.strings`；Storyboard 本地化仍保持现状。
- [ ] 语言切换、冷启动、后台恢复、PTT 状态播报、导航提示和错误提示完成四语言真机回归。

---

## 18. 最终验收条件

- [ ] `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 零修改。
- [ ] 只维护一个 `PTSpeed` TestFlight 版本，没有 Lab Scheme、第二个 App 或 App Store 发布链路。
- [ ] App 版本始终为 `2.0.8`，后续 TestFlight 只递增 Build 号。
- [ ] App、Widget、Watch 的版本号与 Build 号符合嵌入和安装校验要求。
- [ ] Build 号变化没有改变 XP400 仪表 BLE 连接、认证或协议数据。
- [ ] `B208-12` 已完成 String Catalog 迁移，四种现有语言完整可用，`languageFunc` 不再接收中文硬编码。
- [ ] App 启动不再隐式启动 OBD 扫描或 PTT 组网。
- [ ] 仪表 BLE 与 OBD BLE 可并行工作，状态互不污染。
- [ ] PTT 零成员时不会创建 Live Activity。
- [ ] Trip、GPX、Widget 和 iCloud 不在主线程执行大文件操作。
- [ ] 普通诊断全部只读；主动 Fuzz、写入和刷写只能在现有 Dev 工具高风险开关开启后调用。
- [ ] CAN Capture 可恢复、导出、比较、标记事件和离线回放。
- [ ] 只有经重复验证且可恢复的仪表操作才能进入普通 UI；`DevTest` 只出现在 `PTECUSnifferOverlay`。
- [ ] 固件和开机画面真实写入可在 Dev 高风险开关开启后逐级测试，普通界面保持不可见、不可调用。
- [ ] 完整 Archive、真机、Watch、BLE、普通模式和开发者实车验证通过。

---

## 19. 实施记录

每完成一个工作包，在这里追加结果，不覆盖失败记录。

### `B208-XX` 工作包名称

- 状态：⬜
- 开始日期：
- 完成日期：
- Commit：
- App 版本：2.0.8
- Build：
- 修改文件：
- 静态检查：
- 单元测试：
- Debug/Release 构建：
- Archive：
- 真机：
- Apple Watch：
- 实车/台架：
- 已知限制：
- 回滚方式：
