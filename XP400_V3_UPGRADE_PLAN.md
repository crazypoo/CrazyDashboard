# XP400 Ride 2.0.8 Build 持续升级计划

> 当前 App 功能、入口、平台和完成状态以 [APP 功能总纲](APP_FEATURE_BLUEPRINT.md) 为唯一事实源；本文件只保留工作包、实施证据、验证缺口和回滚记录。
>
> 本文件中出现的 Build 数字可能是对应工作包开始时的历史基线，项目当前 Build 以功能总纲和工程配置为准。
>
> 适用项目：`/Users/jax/ST/CrazyDashboard`
>
> 发布方式：只维护现有 `PTSpeed` TestFlight 版本，不新增 Lab Scheme、App Target、Bundle ID 或第二发布渠道；当前没有 App Store 上架计划。
>
> 版本规则：`MARKETING_VERSION` 固定为 `2.0.8`，以后只递增 `CURRENT_PROJECT_VERSION`（Build）。当前主 App、Widget、Watch 和 Tests 为 Build 44，下一次 TestFlight 从 Build 45 开始。
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

- [x] `PTSpeed`、Widget 和 Watch 的 `MARKETING_VERSION` 保持 `2.0.8`。
- [x] 当前主 App、Widget、Watch 和 Tests Build 已统一为 `44`；下一次 TestFlight 使用 Build `45`。
- [x] 每次上传 TestFlight 只将 `CURRENT_PROJECT_VERSION` 加一：44、45、46……
- [x] App、Widget、Watch 和 Tests 每次使用完全相同的 Build 号；Build 44 Debug 目标构建已核验，Release/Archive 仍按对应验收记录。
- [x] Tests Target 已同步到主 App Build `44`，此后与主 App、Widget 和 Watch 一起递增。
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

> 车库自动同步工作只对 `PTBluetoothManager.swift` 增加了只读的当前仪表身份出口（Central UUID 与已有 ID1 序列号回调），不改变认证、传输、分片、轮询或 Data1/Data2/Data3 解码逻辑；如果后续要求三份文件严格零字节变化，应先提供不读取核心内部身份的替代接口。

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
- [x] App 新场景启动、显式退出 `PTECUSnifferOverlay`、进入后台或 OBD 断开时自动关闭开关；单纯收起浮层不撤销当前前台会话。
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
| 🟨 | `B208-11` | 隐私、Archive 与 TestFlight 发布 | B208-00、B208-03～B208-08、B208-12 | Test Plan、UI Test Target、核心 Debug 构建和静态隐私检查已接入；Release、Archive、真机和 B208-12 运行时回归待补。 |
| 🟨 | `B208-12` | String Catalog 本地化与语言文案 | B208-00 | String Catalog、四语言资源和 `languageFunc` 中文硬编码清理已完成；语言切换真机回归和发布验收待补。 |

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

- B208-01 本身不修改 `AppDelegate`、`PTWeatherManager`、Secrets 配置或 QWeather SDK 初始化。
- 其他工作包不得顺手重构天气代码。
- 除非用户重新开启该项，否则不做检查、修复或验收。

Build 41 的路线天气回退属于独立的天气业务工作：只复用 App 已完成初始化的 QWeather 实例，并将实例安全注入当前天气和路线风险服务；不迁移凭据来源、不改动 SDK 初始化参数、不更新 Package resolution，因此不改变本项“凭据与依赖范围忽略”的结论。

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

- [ ] Dev 会话已显式开启，`PTECUSnifferOverlay` 可展开或收起且高风险开关已开启。
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
- [ ] 覆盖 Dev 高风险开关默认关闭、开启、收起/展开 Overlay、显式退出、退后台和 OBD 断开，确保撤销后零帧发送。
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
- [ ] Dev 高风险开关默认关闭，显式退出、退后台和断连后不会保留开启状态；单纯收起只保留当前前台会话。
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

- [x] 以现有 `Localizable.strings` 的稳定 Key 为基础创建 `Localizable.xcstrings`，不随意重命名已有 Key。
- [x] 按当前工程的 `developmentRegion = zh-Hans` 保留简体中文开发基准，并将英文、繁体中文和土耳其语完整迁移到同一个 String Catalog。
- [x] 保留 `%@`、`%d`、`%.1f` 等格式占位符及换行、标点和特殊字符；迁移后执行占位符一致性检查。
- [x] 从 `CrazyDashboard.xcodeproj/project.pbxproj` 移除 `Localizable.strings` 的旧 `PBXVariantGroup` 资源引用，避免旧资源与 `Localizable.xcstrings` 重复加载。
- [x] 保持 `PTDashboardConfig.languageFunc(text:)` 的公开签名和现有调用方不变；内部改为通过 Foundation 的 String Catalog API（如 `String(localized:table:bundle:locale:)`）和当前选中语言解析文本。
- [x] 保留 `zh` → `zh-Hans`、`tw` → `zh-Hant`、`en` → `en`、`tr` → `tr` 的映射，不新增第二套语言状态或资源查找逻辑。
- [x] `PTDashboardConfig.language(key:_:)` 继续复用 `languageFunc`，确保带参数文案仍按当前语言格式化。
- [x] 全仓库审查 `PTDashboardConfig.languageFunc(text:)` 的中文字面量，只将真正显示给用户的中文替换为稳定本地化 Key。
- [x] 将 `Global/Location/PTLocationEngine.swift` 中的 `停车定位已更新` 替换为本地化 Key，例如 `parking_location_updated`。
- [x] 将 `Global/Dashboard/Views/PTPeugeotDashBoardNavView.swift` 中的 `导航中`、`下段路名称:`、`当前路段:` 替换为本地化 Key，例如 `navigation_in_progress`、`next_road_name_prefix`、`current_road_name_prefix`。
- [x] 为以上新增 Key 补齐简体中文、繁体中文、English 和 Turkish 四种翻译。
- [x] 仅保留 `PTDashboardConfig.languageFunc` 的兼容门面；业务界面不直接读取 `.lproj`、不自行解析 `.strings` 或 `.xcstrings` 文件。

### 完成条件

- [x] `Localizable.xcstrings` 包含旧 `Localizable.strings` 的全部 140 个有效 Key，并新增 4 个导航/停车文案 Key；工程运行时不存在重复的 `Localizable` 资源。
- [ ] 四种现有 App 语言均能加载完整翻译；String Catalog 结构和编译产物已静态验证，切换语言、冷启动、后台恢复、PTT 状态播报、导航提示和错误提示的真机回归待补。
- [x] `PTDashboardConfig.languageFunc(text:)` 的现有调用无需修改即可正常工作，未找到 Key 时保留以 Key 为结果的安全回退，不发生崩溃。
- [x] Swift 源码中传给 `PTDashboardConfig.languageFunc(text:)` 的中文用户文案字面量为零；注释、协议原始数据和本地化资源中的翻译文本不计入此项。
- [x] 所有带参数文案的占位符数量和类型一致，中文、英文、繁体中文和土耳其语均通过静态格式化检查。
- [x] App、Widget、Watch 和 Tests 的构建资源没有误引用旧 `Localizable.strings`；Storyboard 本地化仍保持现状。
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
- Commit：基线 `82b57ab2c3badc8e# XP400 Ride / PTSpeed APP 功能总纲

> 本文件是项目功能、入口、平台覆盖和完成状态的唯一事实源（Single Source of Truth）。
>
> 快照日期：2026-09-01
>
> 仓库基线：`b6d39a0952f6d027811cb8cb2720af3ff905a05c`
>
> 发布版本：`MARKETING_VERSION = 2.0.8`，主 App / Widget / Watch `CURRENT_PROJECT_VERSION = 42`
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

本文件不代替实施记录。[XP400_V3_UPGRADE_PLAN.md](XP400_V3_UPGRADE_PLAN.md) 继续记录工作包、实施证据、验证缺口与回滚方法；本文件只维护“当前产品是什么”。当两者不一致时，以当前代码和本文件最近一次核验结果为准。

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
| CORE-006 | 🟨 | 按需启动服务 | 已减少无条件启动；需持续防止 PTT、Live Activity、OBD 等在冷启动时误激活 |
| CORE-007 | 🟨 | 运动数据统一来源 | 俯仰、倾角、G 值等已接入；仍需不同安装角度和真车校准 |
| CORE-008 | 🟨 | 四语言基础 | App 已支持简中、繁中、英语、西班牙语；仍需清理动态文案和遗漏硬编码 |

### 5.2 仪表与车辆状态

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| DASH-001 | ✅ | 机车首页 | 展示车辆连接和核心骑行状态，并进入各仪表页面 |
| DASH-002 | ✅ | 原车状态指示 | 转向灯、远光、警告、连接等基础状态展示 |
| DASH-003 | ✅ | 普通专业仪表 | 速度、转速、油量、里程等常用数据仪表 |
| DASH-004 | ✅ | Peugeot 风格仪表 | 模拟 XP400 风格的 LED / 数字仪表展示 |
| DASH-005 | 🟨 | 动态骑行组件 | 倾角、俯仰、G 值、颠簸等组件已存在，需实车校准与异常值治理 |
| DASH-006 | 🟨 | 摔车与碰撞预警 | 已有运动阈值和警告链路；不能替代专业救援设备，需道路误报验证 |
| DASH-007 | 🟨 | 媒体与设备状态 | Now Playing、手机电量等辅助信息已有接入，需后台权限与空状态验证 |
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
| NAV-013 | ⬜ | 自定义路线编辑 | `PTCustomRouteManager` 尚未形成正式入口和完整闭环 |

### 5.4 行程、回顾、安全与维护

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| RIDE-001 | ✅ | 自动行程记录 | 按连接和骑行状态记录行程基础数据 |
| RIDE-002 | ✅ | 行程历史 | 浏览已保存行程和基础摘要 |
| RIDE-003 | ✅ | 骑行指标与回顾 | 统计距离、时间、速度等并生成回顾信息 |
| RIDE-004 | 🟨 | GPX 导入导出 | 已有 GPX 能力，需覆盖大文件、异常轨迹和跨 App 分享 |
| RIDE-005 | ✅ | 行程快照 | 保存关键时刻或行程摘要快照 |
| RIDE-006 | 🟨 | 行程 iCloud 同步 | 已有云端保存链路，需冲突、离线、容量和多设备恢复验证 |
| RIDE-007 | 🟨 | 骑行黑匣子 | 已有事件与骑行数据记录，仍需定义事故窗口、保留策略和恢复流程 |
| RIDE-008 | 🟨 | 骑行故事 | 可基于行程生成分享内容；模板与隐私裁剪仍需完善 |
| RIDE-009 | 🟨 | 续航估算 | 根据油量与历史数据估算；需油耗样本和车型差异校准 |
| RIDE-010 | 🟨 | 维护提醒 | 已有维护数据与提醒能力，需明确周期来源和用户确认 |
| RIDE-011 | 🟨 | 组群安全 | 已有车友状态和安全事件基础，需真实多车、弱网和退出组群验证 |
| RIDE-012 | 🟨 | 防盗监控 | 已有入口和通知链路，需后台限制、误报与耗电验证 |
| RIDE-013 | 🟨 | 诊断与安全通知 | 可通知部分车辆、维护和安全事件，需统一去重和权限状态 |

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

### 5.6 OBD、UDS 与 CAN

| ID | 状态 | 功能 | 当前能力与边界 |
| --- | --- | --- | --- |
| OBD-001 | ✅ | 标准 PID 实时数据 | 使用稳定命令层读取并解码支持的标准车辆数据 |
| OBD-002 | ✅ | 故障码 | 读取已确认、待定和永久故障码并支持清晰展示 |
| OBD-003 | ✅ | ECU / 协议信息 | 展示支持的 ECU、协议和模块信息 |
| OBD-004 | ✅ | Mode 6 报告 | 读取并展示支持的车载监测测试结果 |
| OBD-005 | ✅ | VIN | 支持标准 VIN 读取和解码 |
| OBD-006 | 🟨 | 只读 UDS 服务 | 支持 DID、VIN、节点和否定响应结构化解析；车型证据仍有限 |
| OBD-007 | 🧪 | ECU 节点扫描 | 仅 Dev 显式开启，必须支持超时、取消、速率限制和轮询恢复 |
| OBD-008 | 🧪 | 内存读取与深度 Dump | 只读、限地址和限长度；无车型证据时不得扩大扫描范围 |
| OBD-009 | 🟨 | CAN Capture | 支持开始/停止、Header 过滤、流式保存和事件标记，需更多适配器实测 |
| OBD-010 | 🟨 | Capture 历史与导出 | 支持恢复、历史、JSON / JSONL / CSV；需异常退出与大文件验证 |
| OBD-011 | 🟨 | CAN 分析 | 支持 Capture diff、Byte / Bit diff、事件窗口和变化统计 |
| OBD-012 | 🟨 | Capture 离线回放 | 已有回放基础，可辅助无实车 UI 与回归测试，样本库仍需扩充 |
| OBD-013 | 🧪 | XP400 诊断证据目录 | 记录已确认请求、响应与适用 ECU；当前普通读取证据以 F190 VIN 为主 |
| OBD-014 | ⬜ | 独立只读诊断中心 | 计划统一 VIN、ECU、DTC、Freeze Frame、Mode 6、DID 与报告导出 |
| OBD-015 | ⬜ | 完整 CAN 实验室 UI | 计划完善实时统计、双 Capture 比较、候选 CAN ID 推荐和事件分析 |

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
| DEV-002 | 🧪 | OBD / CAN Sniffer | 只供开发诊断；退出、失败或断线后必须恢复 Header、轮询与 Sniffer 状态 |
| DEV-003 | 🧪 | 高风险功能总开关 | 默认关闭；开发者必须在 Dev 页面明确开启后才能进入实验流程 |
| DEV-004 | 🧪 | DID Fuzz | 必须限制范围、速率、超时和取消，不允许无边界全车扫描 |
| DEV-005 | 🧪 | 节点与深度读取 | 只读、结构化返回并保留失败节点，不得依赖日志作为数据接口 |
| DEV-006 | 🧪 | 仪表配置 / 开机画面实验 API | 仅保留受控研究入口；无真实协议证据、Seed-Key 和回滚方案时拒绝危险帧 |
| DEV-007 | ⬜ | 真实 OTA 更新 | 当前不具备可交付 Bootloader、CRC、ACK、断点续传与恢复闭环 |
| DEV-008 | ⬜ | ECU 固件刷写 | 当前不具备真实固件格式、分块传输、校验与失败回滚闭环 |
| DEV-009 | ⬜ | 原固件备份与完整性校验 | 空备份或固定成功结果不能视为功能完成 |
| DEV-010 | 🧪 | 刷写前置检查 | 计划校验电压、连接、车型、文件签名、备份、用户确认和恢复资源 |
| DEV-011 | ⬜ | LiDAR 碰撞辅助 | `PTLiDARCollisionManager` 尚未接入正式功能链路 |

高风险操作统一规则：

1. 仅可从现有 Dev 模块开关进入，普通 UI、Widget、Watch、Siri 和 URL Scheme 不得调用。
2. 默认关闭；每次 App 启动后不得静默继承危险执行许可。
3. 开发者开关只是入口授权，不代表协议已验证；执行前仍需车型、ECU、会话、电压、文件和回滚检查。
4. 未确认 Seed-Key、Bootloader、签名、CRC、ACK、备份和恢复时，只允许生成报告或拒绝执行。
5. 所有实验必须保留原始请求/响应、时间、目标地址、固件标识和中止原因，并对导出内容脱敏。

## 7. 后续候选功能池

以下功能用于保存想法，不代表已承诺排期；进入实施前应先建立对应 B208 工作包或后续 Build 工作包。

| ID | 状态 | 候选功能 | 最小可交付范围 |
| --- | --- | --- | --- |
| IDEA-001 | 🟨 | ADV Roadbook | 已支持 GPX 导入、路点列表、逐点仪表导航、连续偏航检测/返回和 GPX 分享；待真实 GPX、定位与仪表验收 |
| IDEA-002 | 🟨 | 完整行程回放 | 已支持 GPX 地图轨迹、速度/转速/倾角/三轴 G 值同步播放、事件时间轴和地图标记；待大文件、异常 GPX 与真机验证 |
| IDEA-003 | 🟨 | Watch 骑行助手 | 已支持 Roadbook / 普通导航只读提示、转向触觉和停车寻车；待真实配对、后台/锁屏及不同表径验证 |
| IDEA-004 | 🟨 | 多车库 | 已支持多辆摩托档案、当前车辆切换、里程、按车保养预警距离、实时保养状态、保养记录、只读 OBD 摘要和配件记录；待行程历史按车辆归属、iCloud 冲突同步与真实车辆验证 |
| IDEA-005 | ⬜ | 轮胎与悬挂档案 | 胎压建议记录、冷热胎观察、预载与阻尼设置日志 |
| IDEA-006 | 🟨 | 路线天气风险 | Roadbook 已接入 WeatherKit 路线采样、降雨/横风/温度/能见度/风暴风险分级；待真实路线与网络权限验收 |
| IDEA-007 | 🟨 | 防盗事件时间轴 | 已记录防盗启停、停车点、断连、报警、恢复和宽限期事件，并支持有界 JSON/CSV 导出；位移/震动传感器证据和通知闭环待真机验收 |
| IDEA-008 | 🟨 | 车队危险点与停车分享 | 已基于现有 PTT 可靠通道分享停车、路障、湿滑、施工、加油和集合点，支持 TTL、中继跳数、去重、过期和导出；待多真机验收 |
| IDEA-009 | 🧪 | XP400 指令证据库 | 已将只读 DID 结果按车辆、ECU 地址、原始响应、状态和观察等级保存，并对 VIN 导出脱敏；真实车型样本与证据晋级规则待补齐 |
| IDEA-010 | 🧪 | 安全固件升级状态机 | 已接入 Dev 面板的固件前置检查、阻断原因、审计和明确确认状态；未验证 Bootloader/CRC/ACK/恢复协议前始终拒绝发送字节 |

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
- 路线天气风险的 WeatherKit 权限、网络异常、长路线采样和真实骑行提醒阈值。
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
文档同步：APP_FEATURE_BLUEPRINT.md / XP400_V3_UPGRADE_PLAN.md / README.md
```

## 11. 总纲审计记录

| 日期 | 仓库基线 | 内容 |
| --- | --- | --- |
| 2026-09-01 | `b6d39a0` | 建立首版功能总纲，覆盖 iPhone、Widget、Watch、CarPlay、Siri、PTT、OBD、Dev 和候选功能 |
| 2026-09-01 | 当前工作区 | IDEA-003 已接入 Watch 只读导航、Roadbook 提示、转向触觉和停车寻车；保留真实设备与道路验证缺口 |
| 2026-09-01 | 当前工作区 | IDEA-004 已接入设置页车库入口、车辆档案切换、里程管理、保养记录、只读 OBD 摘要和配件档案；行程历史归属与 iCloud 冲突同步暂留后续 |
| 2026-09-01 | 当前工作区 | IDEA-004 保养提醒已支持每车预警距离、仪表 `distToMaintenance` 实时比较、保养状态展示和按车辆/状态通知限频；保留真实车辆数据验证 |
| 2026-09-01 | 当前工作区 | IDEA-006～IDEA-010 已完成第一版外围实现：路线天气风险、防盗事件时间轴、PTT 点位分享、只读 XP400 证据库和 Dev 固件前置状态机；保留 WeatherKit/PTT/实车协议验证缺口，未修改 BLE 与 OBD 稳定核心 |

---

## 20. Build 40 指定功能实施记录（2026-09-02）

本节是本轮实施的收口记录，覆盖 `APP_FEATURE_BLUEPRINT.md` 中锁定的 `NAV-013`、`RIDE-007`、`RIDE-009`、`RIDE-012`、`RIDE-013`、`OBD-006`、`OBD-014` 和 `OBD-015`。营销版本保持 `2.0.8`，本轮只将 PTSpeed、Widget、Watch 及测试 Target 的 Build 统一到 `40`。

### 20.1 已完成的代码工作

- [x] `NAV-013`：新增地图+有序路点编辑页，支持当前位置/坐标添加、路点重排、删除、重命名和保存到 `PTCustomRouteManager`；不自动规划路线。
- [x] `RIDE-007`：黑匣子事件片段固定为事件前 60 秒、后 30 秒；加入实时检查点、异常恢复、事件来源、90 日保留和数量/内存边界；支持 JSON、CSV、GPX 导出入口。
- [x] `RIDE-009`：续航估算优先使用仪表数据；XP400 GT 默认油箱容量为 13.5 L；无有效实时油耗时使用按距离加权的历史样本，并限制样本与输入边界。
- [x] `RIDE-012`：防盗监控改为用户主动开启；冷启动不使用旧缓存自动布防；新鲜熄火数据经过宽限期、断连定位有效性和距离校验后才报警，并加入确认、暂缓、冷却和状态时间线。
- [x] `RIDE-013`：维护、DTC、电瓶/低温、防盗和骑行安全事件统一经过类型化本地通知、分类动作、权限请求和持久去重。
- [x] `OBD-006`：复用 `PTOBDiagnosticAddress`、现有稳定传输和独占轮询；新增只读 DID、VIN、节点、内存边界、批量、取消、进度、`62` 正响应及 `7F`/NRC 结构化解析。
- [x] `OBD-014`：新增只读诊断中心，整合 DTC、VIN、Freeze Frame、Mode 6、确认 DID、失败原因、进度/取消和车库报告保存；普通入口不暴露写入、Fuzz 或刷写。
- [x] `OBD-015`：新增 CAN 实验室 UI；公开入口仅查看离线历史、JSONL 恢复、分析、Byte/Bit diff、事件窗口、候选 ID、比较、分享、删除和回放；实时 Sniffer 仅保留 Dev 门禁入口。
- [x] 未修改稳定核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`。
- [x] 未修改 QWeather、B208-01 和 B208-02 范围；高风险写入/OTA/刷写仍由现有 Dev 开关控制。

### 20.2 已完成的静态验证

- [x] 新增和修改 Swift 文件通过 `swiftc -frontend -parse` 语法扫描。
- [x] `Global/Localizable.xcstrings` 通过 JSON 结构检查。
- [x] 工程能够被 `xcodebuild -list` 正确读取，新增页面已登记到 PTSpeed Sources。
- [x] `git diff --check` 无空白错误。
- [x] 保护文件 SHA-256 与实施前基线一致。

### 20.3 尚未声称通过的验收

- [x] PTSpeed iOS Debug、`xp400WidgetExtension`、`xp400watch Watch App` 的工作区构建通过（`CODE_SIGNING_ALLOWED=NO`）。
- [x] PTSpeed 的 iOS Simulator `build-for-testing` 通过，包含 `PTSpeedTests` 和 `PTSpeedUITests` 的编译。
- [ ] XCTest 实际执行：当前 Xcode 运行配置没有提供与工程支持平台匹配的可运行 Simulator destination；待使用匹配的 iOS Simulator 或真机执行。
- [ ] iPhone/Apple Watch/真实 OBD 适配器/XP400 GT 联机验证：需要真实硬件和对应车型协议证据。
- [ ] 防盗后台耗电、定位误报、通知动作和 PTT/Live Activity 生命周期真机回归。
- [ ] CAN 不同 ELM327、11-bit/29-bit、多帧和异常断电样本回归。

### 20.4 回滚与发布门禁

如需回滚，只回退本轮新增/修改的外围文件和工程登记，保留用户已有的计划文档修改；禁止对三个稳定核心文件执行回退或重写。Build 40 在完成依赖恢复、Target 编译、测试和真实设备验证前，相关功能继续保持 `🟨`/`🧪` 状态，不升级为“已验证可用”。

---

## 21. Build 41 路线天气双提供方回退实施记录（2026-09-02）

本轮继续使用营销版本 `2.0.8`，仅将工程的 App、Widget、Watch 和 Tests Build 统一推进到 `41`。目标是修复路线天气风险中 WeatherKit 经常失败时没有可靠备用数据的问题，同时不改变 QWeather 的凭据来源、SDK 版本和三个稳定核心文件。

### 21.1 已实施内容

- [x] `PTRouteWeatherRiskService` 保留 WeatherKit 首选路径；任意采样点失败后丢弃 Apple 半成品，并从第一个采样点完整重试 QWeather。
- [x] `PTRouteWeatherRiskReport` 新增唯一 `provider` 字段，兼容没有该字段的历史 JSON 报告；单个报告不会混用两个提供方的数据。
- [x] 复用 `QWeather.weather168h`，将温度、降水概率、风速、天气文本和时间转换为既有路线天气模型；缺失能见度时保留为空，并对雾/霾类文本作谨慎风险提示。
- [x] 统一执行 90 分钟最近预报容差和 QWeather 168 小时边界检查。
- [x] 新增无备用服务、双提供方失败、超出 QWeather 预报范围和取消等结构化错误；取消不会触发备用请求。
- [x] QWeather 启动初始化后，将同一个已配置实例注入 `PTWeatherManager` 和 `PTRouteWeatherRiskService`；没有新增网络层、响应拼接器或依赖。
- [x] Roadbook 天气报告显示实际提供方和是否发生回退；加载提示改为不绑定具体提供方的中性文案。
- [x] 保留 B208-01 的凭据与 SDK 范围：不迁移 Secrets、硬编码凭据或 Package resolution；本轮只增加已初始化服务的安全注入。
- [x] 增加路线提供方回退、取消、历史报告兼容和 QWeather 条件映射测试。
- [x] 未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift`。

### 21.2 验证记录

- [x] 当前 Xcode 下 `PTSpeed` Debug generic iOS 工程编译通过：`CODE_SIGNING_ALLOWED=NO`、`ENABLE_PREVIEWS=NO`。
- [ ] `PTSpeedTests` 的新增测试完成实际执行；如运行环境仍存在 Simulator 架构或设备不可用问题，只记录编译结果，不把它表述为测试通过。
- [x] Widget、Watch、Tests 的 Build 41 Debug 目标构建/测试构建已通过。
- [x] `PTSpeed` Build 41 Release generic iOS 构建通过；完整 Archive、签名和导出校验仍待补。
- [ ] WeatherKit 成功、单点失败回退、双服务失败、权限拒绝和长路线边界需要真实 iPhone 网络环境验证。
- [ ] 四语言 Roadbook 提示、WeatherKit 权限、QWeather 真实返回和后台行为需要真机回归。

### 21.3 回滚与发布门禁

如需回滚，仅回退路线天气服务、PTWeatherManager 的 QWeather 注入、Roadbook 本地化、测试、工程 Build 号和本节记录；不回退三个稳定核心文件，不修改 B208-01/B208-02 的既定范围。只有真实天气回退和相关 Target/Archive 验证完成后，才能把 IDEA-006 或本记录从 `🟨` 提升为 `✅`。

---

## 22. Build 42 开发者会话与 ECU Sniffer 浮层优化实施记录（2026-09-02）

本轮继续使用营销版本 `2.0.8`，仅将 PTSpeed、Widget、Watch 和 Tests 的 Build 统一推进到 `42`。目标是解决 App 启动或进入其他开发者页面后，`PTECUSnifferOverlay` 作为全屏窗口层阻碍操作，以及收起界面错误撤销高风险开发者授权的问题。三个稳定核心文件保持不变。

### 22.1 已实施内容

- [x] `PTECUSnifferOverlay` 改为 `hidden`、`compact`、`expanded` 三态；收起只隐藏控制台，保留紧凑 `DEV` 按钮和当前前台会话。
- [x] 新增独立的“收起”和“退出开发者会话”操作；兼容旧 `hideSniffer()` API，并将其定义为完整退出。
- [x] 紧凑 `DEV` 按钮限制在安全区域内，可拖动调整位置；浮层未占用的区域向下透传触摸，避免阻碍普通页面。
- [x] 高风险授权继续只由 `PTDeveloperSafetyGate` 持有；显式退出、进入后台或 OBD 断开时撤销，收起时不撤销。
- [x] 增加门禁状态通知，浮层、CAN Lab 和高风险控件同步同一状态；生命周期撤销后停止浮层 Fuzz 和活动 CAN 抓包。
- [x] 高风险门禁失效后 CAN Lab 自动停止实时抓包并显示停止原因；重新授权后由开发者明确点击开始，不自动恢复。
- [x] 新场景启动清除旧的 `BleTestDataGet`，不恢复上一次开发者界面或高风险权限；天气浮层先挂载，确保开发者按钮层级正确。
- [x] 浮层日志待渲染队列增加上限；定时器使用弱引用，接收回调统一切换到 `MainActor`，降低长时间运行的内存和数据竞争风险。
- [x] 开发者浮层新增和补齐四种现有语言的按钮、状态、前置检查和 CAN Lab 停止文案。
- [x] 新增开发者浮层收起/展开/显式退出、门禁生命周期重置和冷启动不可见性测试。
- [x] 未修改 `Global/BLE/PTBluetoothManager.swift`、`Global/OBD/Function/PTHiddenOBDConnector.swift` 和 `Global/OBD/Function/PTOBDCommand.swift`。

### 22.2 验证记录

- [x] `git diff --check` 通过。
- [x] `Global/Localizable.xcstrings` JSON 结构检查通过。
- [x] 本轮修改 Swift 文件通过 `swiftc -frontend -parse` 语法扫描。
- [x] PTSpeed、Widget、Watch 和 Tests 的 Build 42 目标构建已完成：PTSpeed Debug/Release、Widget Debug/Release、Watch Debug/Release，以及 PTSpeed `build-for-testing` 均通过；构建均使用 `CODE_SIGNING_ALLOWED=NO`、`ENABLE_PREVIEWS=NO`，仅保留既有第三方依赖警告。
- [ ] XCTest 实际运行待匹配的 iOS Simulator 或真机环境执行；本轮 `build-for-testing` 已通过，但 `xcodebuild test` 因当前 PTSpeed Scheme 与本机 iOS 27 arm64 Simulator 的支持平台不匹配而退出，测试用例未执行。
- [ ] 真实 iPhone 验证四指进入、收起后操作其他 Dev 页面、拖动按钮、退后台、断车和重新授权。
- [ ] 真实 OBD/CAN 适配器验证门禁撤销后不残留 Sniffer、Header、轮询或活动抓包。

### 22.3 回滚与发布门禁

如需回滚，只回退本节新增的浮层状态、门禁通知、CAN Lab 观察、冷启动处理、测试、本地化和 Build 42 工程配置；不回退、不覆盖三个稳定核心文件。未完成真机/适配器回归前，`DEV-012` 继续保持 `🧪`，普通用户入口不得暴露高风险操作。

---

## 23. Build 43 XP400 电话、短信与系统通知实施记录（2026-09-02）

本轮继续使用营销版本 `2.0.8`，仅将 PTSpeed、Widget、Watch 和 Tests 的 Build 统一推进到 `43`。目标是验证并引导 XP400 使用 iOS 系统通知中心与标准 ANCS 的原生链路，不在 App 内读取其他 App 通知，也不新增第二套 BLE 通知传输层。

### 23.1 已实施内容

- [x] `PTMotoSettingViewController` 新增“电话、短信和通知”设置入口，展示当前仪表连接状态与 PTSpeed 自身的通知授权状态。
- [x] 仅在用户明确操作后请求 PTSpeed 通知权限；拒绝时只跳转 iOS 公开通知设置页。
- [x] 新增 5 秒延迟本地测试通知和 XP400 系统通知配置指引，测试内容不包含车辆敏感数据。
- [x] `PTNotificationCenter` 成功日志改为准确表述“已提交给 iOS 通知中心”；是否由 XP400 显示取决于 iOS 配对、系统设置和 XP400 固件能力。
- [x] 新增英语、土耳其语、简体中文和繁体中文文案。
- [x] 未新增自定义 ANCS 服务、通知队列、CallKit、通知扩展或私有蓝牙设置 URL。
- [x] 未启用 `PTBluetoothManager.swift` 中未完成的 ANCS 原型，未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift`。

### 23.2 验证记录

- [x] `Global/Localizable.xcstrings` JSON 结构检查通过。
- [x] 本轮修改 Swift 文件通过 `swiftc -frontend -parse` 语法扫描。
- [x] `git diff --check` 通过。
- [x] PTSpeed、Widget、Watch 和 Tests 的 Build 43 目标编译、`build-for-testing` 与 Release 目标构建已完成（使用 `.xcworkspace`、`CODE_SIGNING_ALLOWED=NO`、`ENABLE_PREVIEWS=NO`）；完整 Archive、签名和导出校验仍待补。
- [ ] XCTest 实际执行仍需匹配的 iOS Simulator 或真机环境；`build-for-testing` 不等同于测试已执行。
- [ ] 真实 XP400 GT 硬件验证：来电、短信、第三方通知、锁屏/解锁、前后台、Focus、显示预览、断连/重连、重复与过期通知。
- [ ] P0 能力门禁：只有在 iPhone 的 XP400 蓝牙详情出现系统通知分享能力，或抓包确认标准 ANCS 交互后，才可评估 `SYS-013` 是否能够提升状态。

### 23.3 边界、隐私与回滚

- iOS App 只能查询和安排自己的本地通知，不能读取电话、短信或其他 App 的通知正文；本功能依赖 iOS 与 XP400 之间的系统 ANCS。
- PTSpeed 通知权限被拒绝不会代表 XP400 的电话/短信 ANCS 被拒绝，两者状态必须分开说明。
- 不持久化、不记录和不导出电话、短信或第三方通知正文；第一版不支持通知动作、UID 缓存或回复。
- 若真实 XP400 不支持系统 ANCS，只保留设置引导和本地测试，不伪造“已连接/已激活”状态。
- 如需回滚，只回退本节设置入口、通知日志、本地化和 Build 43 工程配置；不得回退或覆盖三个稳定核心文件，也不改变既有 OBD、BLE、Widget、Watch 和 iCloud 数据链路。

---

## 24. Build 44 Siri、App Shortcuts 与 URL Scheme 说明页实施记录（2026-09-02）

本轮继续使用营销版本 `2.0.8`，将 PTSpeed、Widget、Watch 和 Tests 的 Build 统一推进到 `44`。目标是把设置页中的快捷操作说明升级为独立的只读引导页面，集中展示当前 6 个 App Intent 和 6 条 URL Scheme，并避免在说明页误触发车辆或导航操作。

### 24.1 已实施内容

- [x] 设置页快捷操作入口改为导航到独立的 Siri、App Shortcuts 与 URL Scheme 说明页。
- [x] 使用 Apple 官方 `ShortcutsUIButton` 打开 XP400RIDE 在快捷指令中的专属页面。
- [x] 使用 `SiriTipUIView` 展示 6 个已注册 App Shortcut 的系统 Siri 说法。
- [x] 展示 `checkFuel`、`antiTheft`、`openHUD`、`openSafety`、`confirmGasStationRoute` 和 `navigate` 的参数、条件、风险与复制示例。
- [x] Scheme 示例仅复制到剪贴板，不在说明页直接执行；保留规范 `xp400://route` 和旧格式兼容说明。
- [x] 新增 App Shortcuts 四语言短语资源和说明页四语言文案。
- [x] 未修改 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`、路由执行语义或 App Intent 执行逻辑。

### 24.2 验证记录

- [x] `Localizable.xcstrings` 和 `AppShortcuts.xcstrings` JSON 结构检查。
- [x] 已添加说明页目录与 `PTRoutingManager.parse` 的 XCTest 覆盖，包含合法 Scheme、布尔参数和编码目的地；实际执行仍单独记录。
- [x] PTSpeed Debug 构建、PTSpeed `build-for-testing`、Widget Debug 构建和 Watch Debug 构建均已完成；Release 验证因 Xcode beta 构建服务无输出卡住而停止，未伪报成功。
- [ ] XCTest 实际执行；当前 Xcode beta 将现有 PTSpeed Scheme 拒绝为可运行的 iOS Simulator destination，只能确认测试已编译。
- [ ] 真机验证 Shortcuts 按钮、Siri Tip、四种语言短语、复制 Scheme 和从 Shortcuts/外部 App 调用路由。
- [ ] 验证说明页打开、返回、大字体、VoiceOver、小屏布局以及复制操作不产生任何车辆动作。

验证备注：`jq empty` 已通过两个 String Catalog；`git diff --check` 已通过；主 App 和测试构建使用 `CrazyDashboard.xcworkspace`、`CODE_SIGNING_ALLOWED=NO`、`ENABLE_PREVIEWS=NO`。Widget 与 Watch target 的构建返回成功，输出中的弃用和 Swift 6 并发提示来自现有依赖/既有代码，不是本工作包新增编译错误。

### 24.3 边界与回滚

- App Shortcuts 继续由 `PTMotoAppShortcuts` 注册；说明页不维护第二套执行系统。
- 说明页不提供任意 URL 编辑器、不直接执行防盗切换、加油站搜索或导航。
- 如需回滚，只回退本节新增说明页、设置入口、App Shortcuts 资源、文案、测试和 Build 44 工程配置；不得回退或覆盖三个稳定核心文件，也不改变既有 OBD、BLE、Widget、Watch 和 iCloud 数据链路。

---

## 25. 车库按仪表身份自动同步实施记录（当前工作区，下一 TestFlight Build）

本轮继续使用营销版本 `2.0.8`，不改变现有发布渠道、Bundle ID 或 BLE 握手参数。目标是让车库和保养页面在仪表连接后自动获得正确车辆的数据，不要求用户先打开车库页面；手动同步保留为强制刷新和身份确认入口。

### 25.1 已实施内容

- [x] `PTMotorcycleProfile` 增加仪表 Central UUID、仪表序列号、Data2/Data3 保养快照和最后同步时间，并将车库文档 schema 提升到 `4`。
- [x] 仪表身份按“上报序列号优先、Central UUID 兜底”匹配；两种身份指向不同车辆时停止自动写入。
- [x] 首次只收到 UUID 时仅候选当前未绑定车辆，并等待最多 2 秒的序列号；未解决或冲突时要求用户在车库页面显式关联。
- [x] 连接后自动接收 Data1 里程、Data2 保养标志和 Data3 保养剩余里程；内存只保留最新样本，避免高频回调无限增长。
- [x] 自动保存策略统一为首次收到数据后保存、之后最多每 60 秒一次，并在退后台和断开时做最后一次刷新。
- [x] 里程只允许单调增加；保养距离和保养标志独立更新；自动写入只作用于已确认归属的车辆。
- [x] `PTMotoSafteyMileValue` 继续作为当前车辆的兼容阈值，同时每辆车保存自己的保养预警距离；`distToMaintenance` 与对应车辆阈值比较后更新页面和通知。
- [x] PTT 自定义昵称只在默认 XP400 GT 档案首次关联时作为建议名称；车库名称可独立编辑，不会反向修改 PTT 身份。
- [x] 手动同步复用自动同步路径；车辆身份冲突、连接到另一辆车或未解析时，不自动覆盖数据，需用户确认后才可重新关联。
- [x] 主 App 启动阶段显式初始化协调器，自动同步不依赖打开车库或其他业务页面。
- [x] `PTBluetoothManager.swift` 仅增加只读仪表身份回调和当前身份出口；未改动认证、传输、分片、轮询及 Data1/Data2/Data3 解码语义。`PTHiddenOBDConnector.swift` 与 `PTOBDCommand.swift` 未修改。

### 25.2 验证记录

- [x] `git diff --check` 通过。
- [x] `Global/Localizable.xcstrings` JSON 结构检查通过，新增车库同步文案覆盖英语、土耳其语、简体中文和繁体中文。
- [x] 新增身份优先级、UUID 候选与显式重新关联、里程单调性和保养快照更新测试；测试目标已完成 `build-for-testing` 编译。
- [x] 使用 `CrazyDashboard.xcworkspace` 完成 PTSpeed Debug generic iOS 构建，结果为 `BUILD SUCCEEDED`。
- [x] 使用 generic iOS 目标完成 PTSpeed `build-for-testing`，结果为 `TEST BUILD SUCCEEDED`。
- [x] `PTHiddenOBDConnector.swift` SHA-256 仍为 `23ea459f87a4003248cc2c303f25a42c23a24909aa777b21b93ae2a99c41cd99`；`PTOBDCommand.swift` SHA-256 仍为 `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66`。
- [ ] XCTest 尚未在当前 iOS 27 Simulator 实际执行：Xcode beta 将当前测试产物与可用 Simulator destination 判定为不兼容；不能把测试构建表述为测试通过。
- [ ] 需要真实配对 iPhone、XP400 GT 仪表验证序列号读取、首次绑定、重连、退后台、断开刷新和 Data1/Data2/Data3 时序。
- [ ] 需要两辆车档案的真机回归：正确车辆自动写入、身份冲突阻断、显式重新关联和切换当前车辆后不串写。

### 25.3 边界与回滚

- 自动同步只处理仪表的只读 Data1/Data2/Data3；不发送任何新增车辆控制、配置写入、OBD 写入或刷写命令。
- 仅有 Central UUID 且没有序列号时，不会把数据静默写入已有车辆；只有“当前未绑定档案候选”或用户显式确认可以完成关联。
- 如果身份冲突、车辆档案不存在或样本越界，保留旧档案数据并显示待确认/不可用状态。
- 如需回滚，只回退车库 schema4 字段、身份协调、自动保存、保养关联、车库文案、测试和本节记录；不覆盖 OBD 两个稳定核心，也不回退 BLE 核心既有认证和传输逻辑。

---

## 26. XP400 BLE 协议一致性审计与外围完善实施记录（2026-09-03）

本轮以 `/Users/jax/Desktop/Peugeot/Peugeot_Motocycles_BLE_Protocol.md` 的已确认内容为协议基线，对当前导航发送边界、TIO 分片约束、车辆状态帧与认证帧边界进行了审计。由于 `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 是稳定核心，本轮不修改其连接、认证、传输、分片、轮询或标准解码逻辑。

### 26.1 已实施内容

- [x] 新增 `Global/BLE/PTXP400BLEProtocolContract.swift`，以纯数据契约形式集中记录 FEFB/TIO UUID、20 字节分片、25 个 Credits、车辆状态固定 11 字节、认证连接帧固定 15 字节及已确认的帧 ID。
- [x] 新增出站帧长度、前导字节、结束字节和车辆状态帧校验；认证帧只接受 12 位十六进制 Connectivity Box 身份，避免把认证帧误判为普通 Data1 状态帧。
- [x] 导航发送边界统一过滤未在协议文档中确认的动作码；重算路线使用已确认的 `0x2E`，GPS 无有效动作使用已确认的 `0x2F`，未知动作安全回退为直行 `0x01`。
- [x] 复用现有 `PTFrameBuilder`，没有新增第二套 BLE 传输、发送队列、响应拼接或 Credits 引擎。
- [x] 新增配置帧、TIO 分片、状态/认证帧区分和未知导航动作回退测试，并将新源文件加入 PTSpeed 的 BLE 分组和 Sources 阶段。
- [x] 未实现协议文档没有给出完整字段的电话、短信和第三方通知自定义通道；继续沿用系统 ANCS 设置引导，不伪造协议已支持状态。

### 26.2 明确保留的待验证项

- [ ] 真实 XP400 GT 抓包确认广播匹配、认证时序、完整 Credits 重置/恢复和异常断开后的状态清理。
- [ ] 真实抓包确认主动断开帧的 Frame ID；文档只确认 payload `[01 01]`，本轮不把当前核心中的候选 ID 提升为协议事实。
- [ ] 在稳定核心允许独立工作包后，再针对状态帧严格长度、空 Credits 写入、认证帧长度校验、分片恢复和队列边界补真车回归；本轮不绕过核心保护直接改动这些路径。
- [ ] 用真实仪表验证 `0x2E`、`0x2F` 和全部环岛动作码的显示效果；模拟器、单元测试和工程构建不能替代车辆验收。
- [ ] 当前 Xcode beta 的 PTSpeed 构建在依赖和系统模块预编译阶段超过验证时限；新增 XCTest 尚未实际执行，不能将本轮结果表述为完整构建或测试通过。

### 26.3 验证与回滚边界

- [x] 已完成纯 Swift 协议契约类型检查、工程文件解析和差异检查；外围导航适配层只发送文档已确认的动作码，XCTest 实际执行仍待环境恢复。
- [ ] 真车验证、不同车型/固件版本兼容性和 BLE 长时间运行稳定性仍待执行；不得仅凭构建成功宣称协议完全兼容。
- [x] 本轮没有新增写入、刷写、固件升级、通知动作或任意裸指令 UI 入口。
- [x] 如需回滚，只回退 `PTXP400BLEProtocolContract.swift`、非核心导航调用点、测试和本节记录；不得覆盖三个稳定核心文件，也不改变现有认证和传输行为。
