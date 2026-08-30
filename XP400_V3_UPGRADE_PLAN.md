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
| 🟨 | `B208-00` | 基线、计划与核心保护 | 无 | 已完成静态与构建基线；Instruments、真机和实车基线待补齐后才能关闭。 |
| 🗑️ | `B208-01` | QWeather | 无 | 用户确认当前实现可用，本计划不检查、不修改。 |
| 🗑️ | `B208-02` | 依赖与 Swift 版本 | 无 | 由项目负责人独立处理，本计划不实施、不验收。 |
| 🟨 | `B208-03` | 车辆连接统一协调层 | B208-00 | 协调层与静态检查已完成；BLE/OBD 循环和实车验收待补。 |
| 🟨 | `B208-04` | 冷启动与运行性能 | B208-03 | 代码与静态检查完成；性能数值、真机和实车回归待补。 |
| 🟨 | `B208-05` | Trip、GPX、iCloud 与缩略图 | B208-00 | 持久化 actor、原子写入和恢复链路已接入；真机云端/性能验收待补。 |
| 🟨 | `B208-06` | PTT、Live Activity、Widget、Watch | B208-00 | PTT Activity 单入口和状态门禁已实现；真机/Watch 场景待补。 |
| 🟨 | `B208-07` | 普通诊断、Dev 高风险开关与 CAN 实验室 | B208-03 | 只读白名单、批量边界、Capture 回放与 Dev 高风险门禁已接入；真机抓包验收待补。 |
| 🟨 | `B208-08` | 骑行体验功能 | B208-03、B208-05、B208-06 | 基础只读座舱、Black Box、行程故事和组队安全视图已接入；完整路书、Watch 交互、多车库和真机验收待补。 |
| 🟨 | `B208-09` | XP400 仪表指令证据库 | B208-07 | 已建立证据模型并把普通 UI 收口到 Confirmed 只读指令；真实抓包和重复验证待补。 |
| 🟨 | `B208-10` | 开发者固件与开机画面实车测试 | B208-07、B208-09 | 同一 TestFlight 包内已接入现有 Dev 工具的高风险门禁和前置检查；真实协议证据与实车分级测试待补。 |
| 🟨 | `B208-11` | 隐私、Archive 与 TestFlight 发布 | B208-00、B208-03～B208-08、B208-12 | Test Plan、UI Test Target、核心 Debug 构建和静态隐私检查已接入；Release、Archive、真机和 B208-12 待补。 |
| ⬜ | `B208-12` | String Catalog 本地化与语言文案 | B208-00 | 使用新 Xcode 多语言方式，四种现有语言完整覆盖，`languageFunc` 不再接收中文硬编码。 |

普通功能发布不等待 `B208-10`；开发者刷写仍可在同一个 TestFlight 包中逐步验证，但其失败不得阻塞普通功能交付。

---

## 5. `B208-00` 基线与实施门禁

- [x] 记录当前 Git commit、Xcode、Swift、iOS SDK 和依赖版本。
- [x] 记录 App、Widget、Watch、Tests 当前构建结果。
- [ ] 使用 Instruments 记录冷启动、主线程、内存、卡顿和能耗基线。
- [ ] 记录仪表 BLE 与 OBD 蓝牙/Wi-Fi 的连接时间、成功率和断连恢复行为。
- [ ] 记录 PTT、Live Activity、Widget、Watch 和 iCloud 当前真机行为（本次已完成代码链路审计，运行时验证待补）。
- [x] 本工作包未新增 Swift 代码；如后续补充代码，必须使用英语、西班牙语、中文三语注释。
- [x] 本工作包未做全仓库注释翻译；后续只补充当前修改范围中的旧注释。

完成证据：

- 基线 Commit：`b9b1f5e18ad42dcd966c5aa6b61bda6e987abc5b`（`main`，2026-08-30）。本次 B208-00 只更新本计划文件，未改动业务源代码。
- 版本基线：`MARKETING_VERSION = 2.0.8`；主 App、Widget、Watch 的 `CURRENT_PROJECT_VERSION = 36`；Tests 当前 Build 为 `35`。后续 TestFlight 只递增 Build，不改营销版本。
- 工具链：Xcode `27.0 (27A5252f)`；Apple Swift `6.4.0.33.1`；项目 `SWIFT_VERSION = 5.0`；iOS SDK `27.0`；watchOS SDK `27.0`；CocoaPods `1.16.2`；Ruby `3.3.5`；Git `2.50.1`。
- 依赖基线：Bugly `2.6.1`、PooTools `5.6.1`、SwiftDate `7.0.0`；当前 workspace/project 的 QWeather Package resolution 分别为 `5.2.2`/`5.3.0`，仅记录，不在本计划处理（`B208-01`、`B208-02` 已按用户要求忽略）。
- Target 基线：`PTSpeed`（`com.yd.PTSpeed`）、`xp400WidgetExtension`（`com.yd.PTSpeed.xp400Widget`）、`xp400watch Watch App`（`com.yd.PTSpeed.watchkitapp`）和 `PTSpeedTests`。
- 构建结果：Debug generic iOS Simulator 下 PTSpeed、Widget scheme 和 `build-for-testing` 均完成；Debug generic watchOS Simulator 下 Watch scheme 完成。没有把这些结果扩展表述为真机或 Archive 成功。
- 测试结果：`build-for-testing` 成功生成 XCTest 产物，但默认产物为 `x86_64`；当前 iOS 27 模拟器为 `arm64`，`test-without-building` 被架构不匹配阻断，测试用例没有实际执行。额外 arm64 探测未形成可运行的 `.xctestrun`，未修改工程配置。
- 性能基线：已确认 Xcode Instruments CLI 可见 `Time Profiler`、`Allocations`、`Animation Hitches`、`Activity Monitor`、`Leaks` 等模板；尚未采集冷启动、主线程、内存、卡顿或能耗数值，必须在可运行的 arm64 构建和真机/模拟器环境补测。
- PTT/Live Activity 静态基线：`PTSpeed/AppDelegate.swift` 启动时调用 `PTLocalIntercomManager.shared.restoreIntercomStateAtLaunch()`；该方法依据 `PTIntercomPowerStateKey` 恢复组网。`PTLocalIntercomManager` 只有在 `isRunning && hasConnectedPeers` 时向 `PTLiveActivityManager` 提交成员列表；`PTLiveActivityManager.syncIntercomActivity` 对空成员执行已有 Activity 清理，对非空成员才允许 `Activity.request`。因此“启动后恢复 PTT 状态”和“Activity 创建”是两个不同门槛，但残留 Activity 清理、组网回调时序和真实系统行为仍未完成真机验证，留给 `B208-06`。
- Widget/Watch/iCloud 静态基线：`PTLocationEngine` 在连接状态下按 600 秒节流并在断开/逆地理编码回调中调用 `PTWidgetDataManager`；该管理器写入 App Group、调用 WatchConnectivity、发起 iCloud 快照保存并刷新 Widget timeline。Watch 端消费最近的 application context；本阶段未验证后台、离线、重启和 iCloud 实际同步。
- BLE/OBD 基线：未执行真实仪表 BLE、OBD 蓝牙/Wi-Fi 连接计时、成功率和断连恢复测试；三个核心文件哈希保持不变：`PTBluetoothManager.swift` = `8a1ce464f87076041b7d1c2af0940f0a014bad7d0479ae6d108914cb81d270d7`，`PTHiddenOBDConnector.swift` = `23ea459f87a4003248cc2c303f25a42c23a24909aa777b21b93ae2a99c41cd99`，`PTOBDCommand.swift` = `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66`。
- 真机/车辆状态：当前会话没有可用于本阶段验收的物理 iPhone、配对 Apple Watch、XP400 GT 仪表或 OBD 设备；BLE、OBD、Multipeer Connectivity、Live Activity、Widget 后台和 iCloud 的运行时结果均标记为待补。
- 当前阻塞：①测试产物与 iOS 27 模拟器架构不匹配；②B208-00 所需 Instruments 数值未采集；③真实 BLE/OBD/PTT/Live Activity/Watch/iCloud 行为需要设备或车辆。B208-00 保持 `🟨`，不提前标记完成。
- 回滚方式：本次只产生计划文件变更；如需回退，仅回退本节和实施记录的文档改动，不触碰三个核心文件或其他工作区状态。

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

## 8. `B208-03` 车辆连接协调层（🟨）

- [x] 实现 `PTVehicleConnectivityCoordinator` 和 `PTVehicleSnapshot`。
- [x] 建立仪表 BLE、OBD BLE/Wi-Fi/Mock 的独立状态机映射。
- [x] App 启动不再隐式启动 OBD 扫描。
- [x] 只有 `PTMotoUserDefaultStruct.OBDAutoConnectEnabled` 明确开启时才执行 OBD 自动连接，默认关闭。
- [x] 仪表 BLE 与 OBD BLE 同时运行时互不停止、重置或复用对方状态。
- [x] 一个连接失败只更新自己的错误状态。
- [x] 前后台切换只恢复已配对仪表和用户允许的 OBD，不无条件重连全部服务。
- [x] 页面离开后正确释放 delegate、Timer 和观察者，并在重新出现时恢复必要 delegate。
- [x] Dashboard、CarPlay、Widget、Watch 通过协调器状态和现有 `PTWidgetSharedStatus` 投影共享同一车辆连接结果；OBD 状态保持独立，不污染 Widget 的仪表连接字段。

完成条件：

- [x] 三个核心文件哈希不变，并已在本次改动后复核。
- [ ] 50 次仪表 BLE 连接/断开循环无状态泄漏（⛔ 当前环境没有可验收的仪表和真机）。
- [ ] 50 次 OBD 连接/断开循环无重复扫描或重复轮询（⛔ 当前环境没有可验收的 OBD 和真机）。
- [ ] 30 次仪表 BLE 与 OBD BLE 并行循环通过（⛔ 当前环境没有可验收的车辆设备）。

实施边界：本工作包只增加协调状态和调用入口，不改动 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 的实现，不新增第二套 BLE、OBD 传输层、响应拼接器或轮询引擎。

---

## 9. `B208-04` 性能优化（🟨）

### 冷启动

- [x] 移除 `AppDelegate` 对 Trip、GPX、Location、PTT 和诊断 Manager 的无条件实例化。
- [x] 功能由用户进入页面、开始导航、连接车辆或明确后台设置时按需启动；仪表诊断/防盗/保养观察者仅在仪表连接后激活。
- [x] PTT 默认不恢复组网；新增“恢复上次对讲状态”设置，默认关闭；开关在下一次进程启动时生效。
- [x] OBD 默认不扫描；仪表 BLE 遵循已配对和用户设置（沿用 `B208-03` 的连接门禁）。

### CarPlay 与 Dashboard

- [x] 删除静止状态下 60 Hz 强制 `setNeedsDisplay()`。
- [x] 优先使用地图 SDK 原生刷新。
- [x] 未保留补偿刷新心跳，因此无需额外 15 FPS 定时器；地图交由 SDK 原生刷新。
- [x] Dashboard 根据数据变化刷新，不重复构建完整界面（静态审计确认现有 Dashboard 更新既有子视图）。
- [x] Tab 控制器只创建一次，语言和主题变化只更新轻量级配置。

### 长列表与图片

- [x] Trip Cell 不创建地图实例（地图只由快照服务创建）。
- [x] 删除固定等待一秒的缩略图生成流程，改为地图 SDK 有上限的快照回调。
- [x] 使用可取消任务和缓存，Cell 复用时以请求 ID 校验当前记录。
- [x] 图片解码、轨迹解析和快照文件写入离开主线程；iCloud 原子写入、下载状态和冲突恢复仍留给 `B208-05`。

性能目标：

- [ ] 冷启动 p95 较基线至少改善 25%（⛔ 尚未采集 Instruments 数值）。
- [x] 启动后无非用户授权的 OBD 扫描或 PTT 组网（静态检查；真实后台行为待真机验证）。
- [ ] 行程列表超过 100 ms 的卡顿较基线减少 80%（⛔ 尚未采集 Instruments/Animation Hitches 数值）。
- [x] 静止 CarPlay 不再持续触发 60 Hz 重绘（代码静态检查；CarPlay 真机显示待验证）。
- [ ] BLE/OBD 连接成功率和数据正确性不低于基线（⛔ 需真机和车辆循环测试）。

### B208-04 实施证据

- 基线 Commit：`996b9c904144e09af1f8e89dcbc711f527bcbead`（`main`，2026-08-30）；本次改动尚未提交。
- 版本保持：App 版本 `2.0.8`；PTSpeed、Widget、Watch Build `37`；Tests Build `35`；未修改工程版本号。
- 冷启动：`PTSpeed/AppDelegate.swift` 不再无条件实例化 Trip、GPX、Location、PTT 和诊断 Manager；PTT 新增默认关闭的 `PTTLaunchAutoRestoreEnabled`，并在设置页提供用户开关；OBD 自动连接门禁继续由 `B208-03` 控制。
- CarPlay：`PTSpeed/ViewController.swift` 删除绑定车机屏幕的 `CADisplayLink` 与 60 Hz `setNeedsDisplay()`，保留地图 SDK 原生导航刷新。
- Tab/列表：`PTMotoBaseTabbarController` 缓存导航控制器；`PTTripDataCell` 使用 `NSCache`、可取消任务和请求 ID；缩略图采用 ImageIO 下采样；轨迹解析、图片编码和文件写入移出主线程；`PTRouteSnapshotManager` 移除固定 1 秒等待并使用 SDK 快照回调。
- 后台边界：`PTGPXRecorder` 的文件路径解析和 iCloud 文件检查放入 utility 队列；本次未提前实施 `B208-05` 的 actor、原子替换、下载状态等待和冲突恢复。
- 静态检查：本次修改 Swift 文件 `swiftc -parse` 通过；四份 `Localizable.strings` `plutil -lint` 通过；`git diff --check` 通过；核心文件 SHA-256 与保护基线一致。
- 构建检查：`xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO` 成功完成 Swift 编译和链接。以 iOS Simulator 目的地进行完整 workspace 动作仍受既有 Watch App `AppIcon` 内容和预览链接配置阻断，未将其表述为完整模拟器构建通过。
- 未完成验证：尚未运行 Instruments 冷启动/主线程/Animation Hitches 数值；尚未完成 iPhone、CarPlay、BLE/OBD、PTT 和车辆实测。因此 B208-04 保持 `🟨`，不能标记 `✅`。
- 已知行为：PTT“启动时恢复对讲”开关只影响下一次进程启动，避免在设置页切换时意外启动或停止当前对讲会话。
- 回滚方式：回退本次 B208-04 的未提交源文件和本节计划记录即可；不回退、不覆盖 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`。

---

## 10. `B208-05` Trip、GPX、iCloud 与缩略图

- [x] 使用串行 actor 管理 Trip、GPX、Widget 快照和 iCloud 文件写入。
- [x] 采用临时文件加原子替换，防止中途写入损坏 JSON。
- [x] iCloud 文件未下载完成时等待状态变化，不立即复制占位文件。
- [x] 提供 iCloud 不可用、下载超时、冲突和损坏数据错误。
- [x] 保留最后一份有效本地数据，云端失败不得覆盖本地。
- [x] 大型 JSON 编解码和文件操作不占用主线程。
- [ ] 删除、恢复、迁移和旧格式兼容都有单元测试。
- [x] Widget、Watch 和主 App 使用同一状态模型和同一字段含义。

完成条件：

- [ ] 离线、iCloud 关闭、延迟下载、损坏 JSON 和冲突场景不丢数据。
- [ ] 一千条行程加载和滚动达到性能目标。
- [ ] 快速滚动无错图、重复图片或 Cell 状态串线。

---

## 11. `B208-06` PTT、Live Activity、Widget 与 Watch

### PTT 与 Live Activity

- [x] `PTLiveActivityManager` 的可变状态统一在 `@MainActor` 管理。
- [x] 只有 `connectedPeersCount > 0` 才能创建 PTT Live Activity。
- [x] 零成员时立即结束所有遗留 PTT Activity。
- [x] 有成员时系统中最多存在一个 PTT Activity。
- [x] App 重启先对系统 Activity 做一次状态协调，不盲目新建。
- [x] 成员加入、离开、掉线和重新连接都触发同一个同步入口。
- [x] PTT 未运行、权限拒绝或音频会话失败时不显示虚假在线状态。
- [x] 移除只依赖 `print` 的观测，增加结构化状态和错误记录。

### Widget 与 Watch

- [x] `PTWidgetDataManager`、Widget、Watch 继续使用同一 `PTWidgetSharedStatus`。
- [x] WatchConnectivity 未激活时只保留最新状态。
- [x] Watch 离线后重连只接收最新快照，不积累过期队列。
- [x] Watch App 重启恢复最近一次 application context。
- [x] Widget 与 Watch 无数据时显示明确占位状态。
- [x] 不改变现有 Watch Companion Bundle ID 和嵌入关系。

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

- [x] `PTOBDiagnosticAddress` 成为诊断地址唯一模型来源。
- [x] `PTUDSReadService` 统一解析 `62` 正响应、`7F` 否定响应和 NRC。
- [x] 批量读取支持进度、取消、超时、速率限制和失败节点记录。
- [x] 所有只读任务经过 `PTAdvancedOBDCoordinator` 串行门禁。
- [x] CAN Frame 正确区分 Header、DLC、Payload 和 ISO-TP 元数据。
- [x] 修正 29-bit Header 数值范围验证。
- [x] JSONL 实时写入错误可传回 UI，不只记录日志。
- [x] CAN 内存使用固定容量缓存，完整 Frame 流式写盘。
- [x] 支持 Capture 历史、事件标记、JSON/CSV、Capture Diff、Byte/Bit Diff 和事件窗口。
- [x] 使用现有 Mock 连接和 Capture 文件做离线回放。
- [x] 继续使用现有四指长按手势显示 `PTECUSnifferOverlay`，不创建新入口。
- [x] 在 Overlay 中增加高风险总开关和 Fuzz 操作门禁。
- [x] `PTDashboardHacker` 继续作为兼容门面：只读方法转发到读取服务，高风险方法先检查 Dev 开关。
- [x] Dev 开关关闭时，高风险方法返回结构化拒绝事件且不发送帧；未知写入/刷写协议即使开启也保持拒绝。
- [x] 受限 Fuzz 默认单次发送；批量测试必须明确范围、速率和总次数。

完成条件：

- [ ] 普通 UI 全流程抓包证明没有写入、解锁、Routine 或下载帧。
- [ ] Dev 模式抓包证明所有高风险帧都发生在开关开启期间，并具有操作记录和恢复状态。
- [ ] 任务取消、失败和断连后轮询只恢复一次。
- [ ] 无遗留 Sniffer、自定义 Header 或暂停状态。
- [ ] 诊断结果不依赖日志，可导出结构化报告。

---

## 13. `B208-08` 骑行体验功能

### 第一批 2.0.8 Builds 功能

- [x] **统一骑行座舱（基础）**：已集中展示仪表、OBD、PTT、燃油、行程、仪表原生续航、维护和停车状态；导航、天气和完整行程细节继续留在后续工作包。
- [x] **车辆连接中心（基础）**：通过车辆协调器展示仪表与 OBD 的独立状态，并显示 PTT 成员数；Watch/iCloud 详细健康状态 UI 仍待补。
- [ ] **只读诊断中心**：DTC、VIN、Freeze Frame、Mode 6、DID 和报告导出。
- [ ] **CAN 实验室**：过滤、事件标记、对比、离线回放和候选 CAN ID。

### 后续 2.0.8 Builds 功能

- [x] **Moto Black Box（基础）**：已按事件生成前 60 秒和后 30 秒的 GPS/车辆遥测窗口，支持行程事件和手动标记；本地限量存储且不自动上传；实时窗口预览和真实设备验证待补。
- [x] **智能续航（基础）**：优先使用仪表原生续航；只有显式提供油箱容量和平均油耗时才估算，不猜测车型参数。
- [ ] **ADV Roadbook**：GPX 路书、岔路备注、越野点位和离线骑行记录。
- [x] **行程故事（基础）**：已基于既有行程报告展示距离、平均/最高速度、事件、最大倾角和爬升/下降；地图回放、油耗曲线、照片和完整事件时间轴待补。
- [x] **预测维护（基础）**：依据仪表维护标志和剩余里程生成只读建议；里程、DTC、电压趋势模型仍待后续补充。
- [x] **组队骑行（基础安全视图）**：已复用现有 PTT 位置包展示成员连接、位置过期、距离过远和无位置状态；危险标记广播、掉队策略、低延迟音频状态和停车点共享待补。
- [ ] **Apple Watch 骑行助手**：连接、燃油、里程、停车位置、导航震动和骑行摘要。
- [ ] **多车库**：为不同摩托保存设置、维护记录、油耗模型和诊断报告。

候选想法，可在实施前删除：

- [x] 弯道与坡度骑行统计（基础）：已纳入行程故事的最大倾角和爬升/下降复盘，仅作骑行复盘，不鼓励竞速；分段曲线和路线关联待补。
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
- [x] `DevTest` 只能在开发者工具高风险开关开启时调用，不能进入普通 UI。
- [x] 只有 `Confirmed`、可逆且具备恢复步骤的操作才可进入普通 UI；当前普通 UI 仅有 F190 读取条目。
- [ ] 所有仪表设置只允许停车状态操作，并显示原值和恢复按钮。

完成条件：

- [ ] 没有臆测的 CAN ID、DID、Key、Checksum 或 Payload。
- [ ] 每个公开操作都有原始证据、响应验证和恢复步骤。
- [ ] 任一失败都不会影响导航、仪表连接或正常骑行显示。

---

## 15. `B208-10` 开发者固件与开机画面真实环境测试

### 允许范围

- [x] 在同一个 `PTSpeed` TestFlight 包中保留开发者测试入口，不创建第二个 App。
- [x] 开发者从现有 `PTECUSnifferOverlay` 开启高风险开关；配置写入、开机画面和刷写 API 先经过门禁与前置检查。
- [x] 所有当前已实现的高风险读取/测试入口先检查 Dev 开关；只读总线操作通过现有 `PTAdvancedOBDCoordinator` 串行执行。
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

当前状态：`🟨 已完成同一 TestFlight 包内的 Dev 门禁和前置检查；在获得合法协议证据、恢复方案和真实硬件前，写入/刷写实现仍拒绝发送帧。后续按 Level A → Level B → Level C 逐级实车测试，ELM327 必须先通过能力测试。`

---

## 16. `B208-11` 测试、隐私与发布

### 自动化测试

- [x] 新增明确的 `PTSpeed.xctestplan` 和 `PTSpeedUITests` Target；Test Plan 已纳入工程并可被 `xcodebuild -showTestPlans` 发现。
- [x] 纯解析契约覆盖 11-bit、29-bit、DLC 和非法 CAN Frame；ISO-TP 运行时样本仍待补。
- [x] 纯解析契约覆盖 UDS `62` 正响应、`7F` 否定响应和 NRC；超时、多帧运行时样本仍待补。
- [x] 共享状态契约覆盖协调层仪表/OBD 独立性；双连接、断连、取消和前后台运行时回归仍待补。
- [x] 纯策略契约覆盖 PTT 零成员、有成员、音频不可用和开发者门禁；重复 Activity、重启和权限关闭仍待真机补测。
- [ ] 覆盖 iCloud 离线、延迟下载、冲突、损坏 JSON 和旧格式迁移。
- [ ] 覆盖 Watch 未配对、断连、重连、重启和过期数据覆盖。
- [ ] 覆盖 Dev 高风险开关默认关闭、开启、关闭 Overlay、退后台和 OBD 断开，确保自动关闭后零帧发送。
- [ ] 覆盖 dry-run、单次写入、读取回验、恢复、阶段化取消、断连和未知结果处理。
- [ ] 覆盖未通过四指长按进入 Dev 工具时无法调用高风险操作。
- [ ] 使用 Thread Sanitizer 验证可确定复现的并发流程。

本次自动化基础不替代运行时验收：已编译单元测试和 UI 测试产物，但当前工程的 iOS Simulator 目的地不可被 `PTSpeed` scheme 选中，因此测试用例尚未实际执行。

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
- [x] 保留并静态检查 App、Widget、Watch 三份 `PrivacyInfo.xcprivacy`；Required Reason API 的完整审核仍待发布前完成。
- [ ] 未使用的后台模式和 entitlement 删除前先确认所有调用方。
- [ ] CAN、VIN、位置、行程和语音数据明确本地、iCloud 和导出边界。
- [ ] 日志默认脱敏 VIN、坐标、密钥和用户身份。

### 发布门禁

- [x] 三个核心文件哈希保持不变。
- [ ] Archive 中 App、Widget、Watch 的 `CFBundleShortVersionString` 全部为 `2.0.8`。
- [ ] Archive 中 App、Widget、Watch 的 `CFBundleVersion` 完全一致，并高于上一个 TestFlight Build。
- [x] 本次代码变更保持 `MARKETING_VERSION = 2.0.8`、Bundle ID、Watch Companion ID 和 App Group 不变；Build 统一推进到 `38`。
- [ ] 新 Build 与 Build 36 的 XP400 仪表 BLE 握手、认证、连接和配置结果一致。
- [x] App、Widget、Watch 和 Tests 完成 Debug/build-for-testing 构建；Release 构建仍待补。
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

### `B208-00` 基线与实施门禁

- 状态：🟨（静态、工具链和构建基线已完成；Instruments、真机、Apple Watch、实车/台架待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `b9b1f5e18ad42dcd966c5aa6b61bda6e987abc5b`；本次文档变更未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `36`；PTSpeedTests `35`
- 修改文件：`XP400_V3_UPGRADE_PLAN.md`；未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`
- 静态检查：通过；核心文件 SHA-256 与基线一致；B208-00 目标矩阵、依赖、工具链和运行链路已记录
- 单元测试：`build-for-testing` 成功；`test-without-building` 因 x86_64 测试产物与 arm64 iOS 27 模拟器不匹配而未执行
- Debug/Release 构建：Debug App、Widget、Watch 构建基线已记录；Release 未执行
- Archive：未执行
- 真机：未执行
- Apple Watch：未执行
- 实车/台架：未执行
- 性能基线：Instruments 模板可用但尚未采集数值
- 已知限制：当前 Podfile/Pods 对 iOS Simulator 排除了 arm64；PTT 启动恢复、Live Activity、Widget/Watch/iCloud 以及 BLE/OBD 仍只有静态链路证据；workspace/project 的 QWeather 解析版本差异仅记录，不在 B208-00 处理；后续补测前不得关闭本工作包
- 回滚方式：仅回退本次计划文件的文档变更；不回退、不覆盖用户已有修改

### `B208-03` 车辆连接协调层

- 状态：🟨（协调代码、调用链迁移和静态检查完成；真实连接循环、真机和车辆验收待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `b914e23b8ab70ab3bdfd5fa8d3d18c8d2d49375d`；本次改动尚未提交
- App 版本：2.0.8
- Build：未修改
- 修改文件：新增 `Global/Global/PTVehicleConnectivityCoordinator.swift`；修改 `Global/Global/PTMotoUserDefaultStruct.swift`、`Global/Global/PTMotoBaseViewController.swift`、`Global/BLE/PTBLEConnectViewController.swift`、`Global/Dashboard/ViewController/PTPeugeotDashBoardViewController.swift`、`Global/Dev/PTECUSnifferOverlay.swift`、`Global/OBD/View/PTOBDDataView.swift`、`Global/OBD/ViewController/PTOBDDataViewControllerCollection.swift`、`Global/PTMotoInfoViewController.swift`、`Global/PTMotoSettingViewController.swift`、`PTSpeed/ViewController.swift`、`PTSpeed/PTCarPlaySceneDelegate.swift`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后 SHA-256 仍分别为 `8a1ce464f87076041b7d1c2af0940f0a014bad7d0479ae6d108914cb81d270d7`、`23ea459f87a4003248cc2c303f25a42c23a24909aa777b21b93ae2a99c41cd99`、`7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66`
- 实施内容：新增仪表 BLE 与 OBD BLE/Wi-Fi/Mock 的独立快照和生命周期协调；保留旧 Manager 作为唯一传输/轮询实现；关闭默认 OBD 自动连接；将页面直接连接、断开和恢复入口转发到协调器；补齐页面 delegate、Timer 和观察者生命周期；CarPlay 连接时仅初始化协调器用于状态观察；通过现有 `PTWidgetSharedStatus` 投影仪表连接状态，使 Dashboard、CarPlay、Widget、Watch 不再各自推断连接状态
- 静态检查：`swiftc -parse` 覆盖本次修改的 Swift 文件通过；`plutil -lint CrazyDashboard.xcodeproj/project.pbxproj` 通过；`git diff --check` 通过；新增状态独立性 XCTest 已写入但尚未执行
- Debug/Release 构建：使用 `CrazyDashboard.xcworkspace` 进行 Debug generic iOS 构建时，在 SmartCodable 依赖获取 `swiftlang/swift-syntax` 时因网络超时中断，未到达 PTSpeed 主 target 的最终编译结果；未将该结果表述为完整构建通过；Release 未执行
- Archive：未执行
- 真机：未执行
- Apple Watch：未执行；Watch 继续消费现有 `PTWidgetSharedStatus`，本工作包未改 Watch target
- 实车/台架：未执行，因此 50 次仪表循环、50 次 OBD 循环和 30 次并行循环不能标记完成
- 已知限制：需要在可用依赖缓存、arm64 模拟器或真机上执行 XCTest/完整构建；需要真实 XP400 GT、OBD 设备和配对 iPhone 完成连接/断开/并行压力验收；`OBDAutoConnectEnabled` 已默认关闭，但本次未新增设置页 UI
- 回滚方式：回退本次 B208-03 的新增协调器、调用入口、生命周期修复、测试、工程引用和本节文档记录即可；不回退、不覆盖三个稳定核心文件

### `B208-05` Trip、GPX、iCloud 与缩略图

- 状态：🟨（持久化代码和主 App Debug 编译完成；完整持久化测试、真机 iCloud、千条行程性能和快速滚动验收待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests `35`
- 修改文件：新增 `Global/Global/PTDataPersistenceActor.swift`；修改 `Global/Global/PTTripManager.swift`、`Global/Location/PTGPXRecorder.swift`、`Global/Views/PTTripDataCell.swift`、`Global/Global/PTDataCollectedViewController.swift`、`Global/Widget/PTWidgetManager.swift`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 仍保持不变
- 实施内容：新增串行持久化 actor；本地和 iCloud 均采用同目录临时文件加替换；按 revision 拒绝过期写入；云端不可用时保留本地结果并返回结构化错误；恢复时等待 iCloud 下载状态；损坏历史保留独立备份；Trip 历史异步加载/编码；GPX、地图 JPG 和 Widget 快照统一经 actor 写入；保留旧 GPX 回调、旧数组 JSON 和 iCloud 文件回调兼容入口
- 静态检查：`swiftc -parse Global/Global/PTDataPersistenceActor.swift` 通过；`git diff --check` 通过；主 App 修改范围编译通过；测试新增“云端不可用仍保留本地”和“旧 revision 不覆盖新 revision”契约
- Debug/Release 构建：`xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO` 成功；Release 未执行
- 单元测试：测试 target 没有 workspace scheme，且当前只能先完成编译契约接入；本次未声称 XCTest 已运行
- Archive：未执行
- 真机：未执行；iCloud 登录、延迟下载、冲突和断网恢复待在配对 iPhone 验证
- Apple Watch：未执行；Watch 继续复用 `PTWidgetSharedStatus`，本包未改变 Watch 接收协议
- 实车/台架：不适用于本工作包，未执行
- 未完成验证：删除/恢复/旧 JSON 迁移的 XCTest 仍需补齐；一千条行程加载、快速滚动、iCloud 冲突和真实云端状态仍需 Instruments/真机验证
- 回滚方式：回退本次持久化 actor、异步 Trip/GPX/快照接线、测试和工程引用即可；不回退、不覆盖三个稳定核心文件

### `B208-06` PTT、Live Activity、Widget 与 Watch

- 状态：🟨（代码、静态检查和主 App Debug 编译完成；Live Activity 系统行为、PTT 抖动、权限/音频失败和 iPhone/Watch 真机验收待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests `35`
- 修改文件：`Global/LiveActivity/PTLiveActivityManager.swift`、`Global/PTPTT/Function/PTLocalIntercomManager.swift`、`Global/Widget/PTWatchConnectivityManager.swift`、`PTSpeed/AppDelegate.swift`、`PTSpeedTests/PTCoreTests.swift` 和计划文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 仍保持不变
- 实施内容：Live Activity 管理器显式收口到 `@MainActor`；同步入口使用最新期望状态和 generation，避免启动/成员抖动时旧任务复活 Activity；启动阶段只协调并清理遗留 PTT Activity；零成员立即结束全部 PTT Activity；重复 Activity 收敛为一个；权限关闭时清理并记录结构化状态；导航 Activity 使用真实预计到达时间；WatchConnectivity 改用结构化 Logger；PTT 成员列表按成员身份变化触发同步；音频引擎和麦克风权限作为在线显示门禁；移除初始化时重复创建 Multipeer 会话
- 静态检查：`swiftc -parse` 覆盖修改范围通过；新增 `PTLiveActivityEligibility` 纯逻辑测试；`git diff --check` 通过；核心文件 SHA-256 与保护基线一致
- Debug/Release 构建：`xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO` 成功；Release 未执行
- 单元测试：测试 target 没有 workspace scheme；本次新增策略测试已编入测试源，但未声称 XCTest 实际运行
- Archive：未执行
- 真机：未执行；无法在当前会话确认系统 Activity 数量、权限拒绝、AudioSession 失败或成员抖动时序
- Apple Watch：未执行；未验证 iPhone 前台/后台、Watch 离线/重连/重启
- 实车/台架：不适用于本工作包，未执行
- 未完成验证：需用真实配对 iPhone + Apple Watch 验证 0/1/N 成员、App 重启、系统禁止 Live Activity、麦克风拒绝、音频失败和离线重连；需确认 audio gate 不影响合法的接收场景
- 回滚方式：回退本包 Live Activity/PTT 状态协调、WatchConnectivity 日志、AppDelegate 启动协调、策略测试和计划记录即可；不回退、不覆盖三个稳定核心文件

### `B208-07` 普通诊断、Dev 高风险开关与 CAN 实验室

- 状态：🟨（只读边界、诊断解析、Capture 错误回传、离线回放和 Dev 门禁已实现；真实车辆抓包、取消恢复和高风险审计待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests `35`
- 修改文件：新增 `Global/Dev/PTDeveloperSafetyGate.swift`；修改 `Global/OBD/Function/PTOBDiagnosticAddress.swift`、`Global/OBD/Function/PTUDSDiagnosticService.swift`、`Global/OBD/Function/PTDashboardHacker.swift`、`Global/OBD/Function/PTCANRecorder.swift`、`Global/Dev/PTECUSnifferOverlay.swift`、`Global/PTMotoInfoViewController.swift`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 仍保持不变
- 实施内容：诊断地址校验 11-bit/29-bit 数值范围及收发宽度；批量 DID 增加数量、单请求耗时、总耗时、取消和请求间隔边界；普通菜单只展示白名单 `F190`，结果直接结构化显示；Fuzz、节点扫描、内存读取和全车深度探测经过现有 Dev 面板高风险开关；关闭开关、退后台或 OBD 断开会撤销高风险状态；未知写入、开机画面、OTA 和 ECU 刷写即使开启开关仍因缺少真实协议证据而拒绝发帧；CAN Capture 增加合法 Header 数值校验、异步写入错误回传、固定内存上限和 JSON/JSONL 离线回放
- 静态检查：本次修改范围编译通过；新增诊断地址边界、Capture 回放和 Dev 默认只读策略测试契约；`git diff --check` 通过
- Debug/Release 构建：`xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO` 成功；Release 未执行
- 单元测试：测试 target 没有 workspace scheme；测试契约已编入测试源，但本次未声称 XCTest 实际运行
- Archive：未执行
- 真机：未执行；普通只读抓包、取消/断连恢复、Dev 开关自动关闭和真实高风险零帧审计待在配对 iPhone/OBD/仪表上完成
- Apple Watch：不适用于本工作包，未改变 Watch target
- 实车/台架：未执行；未具备 XP400 GT 仪表和 OBD 设备，不能把 Dev 门禁标记为真实车辆验证完成
- 已知限制：`PTDashboardHacker` 保留旧兼容返回类型，因此拒绝结果同时通过 `PTDeveloperSafetyEvent` 和日志呈现；真正写入/刷写协议尚无合法车型证据，本阶段不会实现猜测型写入或刷写；项目仍有既有 PooTools 脚本和其他文件的并发警告
- 回滚方式：回退本包诊断地址、批量策略、Capture 回放、开发者门禁、UI 接线、测试、工程引用和本节记录即可；不回退、不覆盖三个稳定核心文件

### `B208-08` 骑行体验功能

- 状态：🟨（基础只读骑行座舱、连接状态、续航和维护建议已接入；完整导航/天气/黑匣子/路书/组队功能及真机验收待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests/PTSpeedUITests `38`
- 修改文件：新增 `Global/Global/PTRideExperience.swift`、`Global/Global/PTRideExperienceViewController.swift`；修改 `Global/PTMotoInfoViewController.swift`、四份 `Global/*/Localizable.strings`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 保持不变
- 实施内容：新增只读骑行座舱，集中显示仪表/OBD/PTT 状态、燃油、行程、停车信息和同步时间；续航优先使用仪表原生值，只有显式提供油箱容量时才估算；维护建议仅依据仪表标志和剩余里程，不猜测车型数据；所有入口复用现有连接协调器和 Widget 状态，不新增传输层
- 静态检查：修改范围 `swiftc -parse` 通过；四份本地化资源、工程文件和 Test Plan 通过静态检查；`git diff --check` 通过
- Debug/Release 构建：PTSpeed、xp400WidgetExtension 和 `xp400watch Watch App` Debug generic 构建通过；Release 未执行
- 单元测试：续航、维护、连接状态独立性契约已编入测试源并成功编译；尚未在运行时执行
- Archive：未执行
- 真机：未执行；导航、天气、iCloud、仪表/OBD/PTT 和 Watch 真实联动待补
- Apple Watch：未改变 Watch 接收协议，未执行真机验证
- 实车/台架：不适用于本基础座舱代码，未执行
- 未完成验证：完整导航/天气聚合、Moto Black Box、ADV Roadbook、行程故事、趋势维护、组队骑行和多车库不在本次基础实现内
- 回滚方式：回退座舱模型、座舱控制器、Dashboard 菜单入口、本地化新增 Key、测试、工程引用和本节记录即可；不回退、不覆盖三个稳定核心文件

### `B208-08` 骑行体验功能（追加 Slice 1：Black Box、行程故事与组队安全）

- 状态：🟨（本 Slice 的基础能力已实现；完整路书、Watch 骑行交互、多车库和真实设备验收仍待补）
- 开始日期：2026-08-30
- 完成日期：2026-08-30（本 Slice 代码实现完成）
- Commit：基线 `e750544a892f54fd6c2231f307b7dceaa47311d9`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch/PTSpeedTests/PTSpeedUITests `38`
- 修改文件：新增 `Global/Global/PTRideBlackBox.swift`、`Global/Global/PTRideStory.swift`、`Global/Global/PTRideGroupSafety.swift`；修改 `Global/Global/PTTripManager.swift`、`Global/Global/PTRideExperienceViewController.swift`、四份 `Global/*/Localizable.strings`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 仍需在交付前再次核对
- 实施内容：
  - Moto Black Box 复用既有 `PTRoutePoint`、行程复盘事件和越野事件，生成事件前 60 秒/后 30 秒窗口；支持手动标记，明确记录窗口是否因行程边界而不完整。
  - Black Box 使用 `PTDataPersistenceActor` 本地持久化，默认最多保留 60 个片段，不同步 iCloud；清空或删除行程时清理关联片段。
  - 行程故事复用 `PTTripReport`，展示距离、平均/最高速度、事件数量、最大倾角和爬升/下降；弯道与坡度候选功能先收敛为只读复盘指标，不新增车型猜测。
  - 组队安全视图复用现有 PTT 位置通知和 `PTLocationEngine`，展示成员正常、位置过期、距离过远和无位置状态；没有新增传输协议、音频链路或危险控制。
  - 骑行体验入口新增故事、组队安全、Black Box 摘要和手动事件按钮，所有文案覆盖现有四种语言。
- 静态检查：修改范围 `swiftc -parse` 通过；工程文件与四份本地化资源 `plutil -lint` 通过；`git diff --check` 通过。
- Debug 构建：`PTSpeed` generic iOS、`xp400WidgetExtension` generic iOS、`xp400watch Watch App` generic watchOS 构建通过；测试 target `build-for-testing` 通过。构建输出仍包含既有 Pods 脚本、预编译导航依赖和 Metal 工具链路径警告。
- 单元测试：新增 Black Box 窗口边界/本地数量上限、行程故事摘要、组队安全状态分类测试，并成功编译进 `PTSpeedTests`；未将编译结果表述为运行时通过。
- 测试运行：尝试运行 `PTSpeedTests`，当前可用 iOS 27 Simulator 与 `XP400Ride.app` 的 supported platforms 不匹配，`xcodebuild test` 以 destination 不可用退出；需在匹配的 iOS 设备或真机重新执行。
- Archive：未执行。
- 真机：未执行；尚未验证长途轨迹、后台定位、行程结束后 Black Box 异步保存、存储上限、PTT 成员掉线/转发位置和低电量场景。
- Apple Watch：未修改 Watch 数据协议或界面，Watch target 仅完成回归构建，未执行配对设备验证。
- 实车/台架：不需要新增车辆命令，未执行；稳定 BLE/OBD 核心仍只通过既有公开状态和轨迹数据复用。
- 后续未完成：ADV Roadbook、地图/照片/油耗曲线/完整事件时间轴、危险标记广播和停车点共享、Watch 导航震动与骑行摘要、多车库以及其它候选功能仍保持待办。
- 回滚方式：回退本 Slice 的三个骑行体验新文件、`PTTripManager`/座舱控制器接线、本地化 Key、测试、工程引用和本节记录即可；不回退、不覆盖三个稳定核心文件。

### `B208-09` XP400 GT 仪表指令研究

- 状态：🟨（证据模型和普通 UI 只读白名单已接入；真实抓包、三次独立会话和效果/恢复验证待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests/PTSpeedUITests `38`
- 修改文件：新增 `Global/OBD/Function/PTXP400InstructionCatalog.swift`；修改 `Global/OBD/Function/PTUDSDiagnosticService.swift`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 保持不变
- 实施内容：建立 `Confirmed/Observed/DevTest/Hypothesis/Rejected` 证据等级；普通只读目录唯一确认条目为仪表 VIN DID `F190`（请求 `22F190`、正响应 `62F190`、否定响应 `7F22xx`）；普通 UI 白名单从证据目录派生；未把未知 CAN ID、DID、Seed-Key、Checksum 或 Payload 写入代码
- Dev 边界：`DevTest` 只能经过现有 `PTECUSnifferOverlay` 的高风险开关；写入、开机画面和刷写仍不能因猜测条目进入普通 UI
- 静态检查：指令目录校验、DID 白名单契约、修改范围 `swiftc -parse` 和 `git diff --check` 通过
- Debug/Release 构建：主 App Debug generic iOS 构建通过；Release 未执行
- 单元测试：普通目录只读契约已编入测试源并成功编译；尚未在真实车辆上执行
- Archive：未执行
- 真机：未执行；缺少 XP400 GT 合法原始抓包和三次重复会话证据
- Apple Watch：不适用于本工作包，未改变 Watch target
- 实车/台架：未执行
- 已知限制：公开资料没有提供 XP400 GT 刷写协议、Seed-Key、固件签名或开机画面 DID；因此本包不开放猜测型仪表操作
- 回滚方式：回退证据目录、只读白名单接线、测试、工程引用和本节记录即可；不回退、不覆盖三个稳定核心文件

### `B208-10` 开发者固件与开机画面真实环境测试

- 状态：🟨（同一 TestFlight 包的 Dev 门禁和前置检查已接入；真实协议/恢复证据不足，实际写入和刷写继续拒绝发送帧）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch `38`；PTSpeedTests/PTSpeedUITests `38`
- 修改文件：新增 `Global/Dev/PTDeveloperTestPreflight.swift`；修改 `Global/OBD/Function/PTDashboardHacker.swift`、`PTSpeedTests/PTCoreTests.swift` 和工程文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 保持不变
- 实施内容：为配置写入、安全例程和固件三个等级建立车辆静止、目标身份、原始备份、协议证据、适配器能力、稳定供电、恢复路径、固件兼容性和 Seed-Key 来源检查；旧 API 保持兼容并接收可选检查表；Dev 开关关闭、协议证据缺失或前置条件不完整时返回拒绝并记录结构化原因
- 安全边界：当前 `writeDashboardConfig`、开机画面实验、OTA 和 ECU 刷写不发送任何实际帧；未实现猜测式 Seed-Key、刷写状态机或固件写入伪成功
- 静态检查：前置检查纯逻辑测试、修改范围 `swiftc -parse` 和 `git diff --check` 通过
- Debug/Release 构建：主 App Debug generic iOS 构建通过；Release 未执行
- 单元测试：固件前置检查拒绝契约已编入测试源并成功编译；尚未执行真实 Dev 工具或车辆测试
- Archive：未执行
- 真机：未执行；需要指定 XP400 GT、合法服务资料/抓包、稳定供电、恢复仪表和可审计授权
- Apple Watch：不适用于本工作包，未改变 Watch target
- 实车/台架：未执行；Level A/B/C 均保持未开放状态
- 已知限制：即使打开现有高风险开关，缺少完整协议证据时也不会进入实际写入/刷写；这不是实车成功验证
- 回滚方式：回退前置检查、Hacker 门禁参数、测试、工程引用和本节记录即可；不回退、不覆盖三个稳定核心文件

### `B208-11` 测试、隐私与发布

- 状态：🟨（Test Plan、UI Test Target、核心测试编译和三目标 Debug 构建完成；测试运行、Release/Archive、真机和 B208-12 待补）
- 开始日期：2026-08-30
- 完成日期：待补
- Commit：基线 `82b57ab2c3badc8e22ca2c30c05a3d65cc6d5ca5`；本次改动尚未提交
- App 版本：2.0.8
- Build：PTSpeed/Widget/Watch/PTSpeedTests/PTSpeedUITests `38`
- 修改文件：新增 `PTSpeed.xctestplan`、`PTSpeedUITests/PTSpeedUITests.swift`；修改 `CrazyDashboard.xcodeproj/project.pbxproj`、`CrazyDashboard.xcodeproj/xcshareddata/xcschemes/PTSpeed.xcscheme`、`PTSpeedTests/PTCoreTests.swift` 和计划文件
- 未修改核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`；本次改动后保护 SHA-256 保持不变
- 实施内容：新增单渠道 `PTSpeed` UI Test Target 和启动冒烟测试；现有纯数据测试扩展到 Widget application context、续航/维护、诊断地址、UDS 正/负响应、CAN 11/29-bit Header、DLC、ISO-TP 多帧、CSV 转义、旧 Capture JSON、事件快照、Capture diff/回放、连接状态独立性、持久化版本保护、PTT 门禁、XP400 证据目录和开发者前置检查；不创建第二个 App 或 Lab 发布链路
- Test Plan：`jq empty PTSpeed.xctestplan` 通过，workspace `xcodebuild -showTestPlans` 可发现 `PTSpeed`；scheme 保留 `PTSpeedTests` 和 `PTSpeedUITests` 两个 Testable
- 静态检查：23 个修改/新增 Swift 文件 `swiftc -parse` 通过；`plutil -lint` 通过工程文件和 App/Widget/Watch 三份 `PrivacyInfo.xcprivacy`；`git diff --check` 通过
- Debug/Release 构建：`PTSpeed`、`xp400WidgetExtension`、`xp400watch Watch App` Debug generic 构建通过；`PTSpeed` `build-for-testing` 成功生成 `PTSpeed_PTSpeed_iphoneos27.0-arm64.xctestrun`；Release 未执行
- 单元/UI 测试：当前 `PTSpeed` scheme 的 iOS Simulator 目的地无法选中（可用模拟器与该 scheme 的 supported platforms 不匹配），因此本次没有把测试编译结果表述为测试用例已运行；UI 启动测试也未在真机执行
- Archive：未执行
- 真机：未执行；尚未覆盖 iOS 17/最新系统、配对 Watch、BLE/OBD 并行、普通模式和 Dev 模式
- Apple Watch：Watch Debug 构建通过，未完成真实配对设备验证
- 实车/台架：未执行
- 已知限制：现有 Pods 含预编译导航依赖和模拟器架构限制；未修改 Pods/依赖配置绕过；B208-12 String Catalog 仍是发布前依赖
- 回滚方式：回退 UI Test Target、Test Plan、scheme Testable、Build 38 测试配置、本包测试扩展和本节记录即可；不回退、不覆盖三个稳定核心文件

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
