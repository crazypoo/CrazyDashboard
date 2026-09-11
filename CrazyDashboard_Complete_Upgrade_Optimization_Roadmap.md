# CrazyDashboard 完整升级、重构与优化路线图

> 项目：CrazyDashboard  
> 仓库：https://github.com/crazypoo/CrazyDashboard  
> 目标平台：iOS / UIKit / CoreBluetooth / OBD-II / ELM327 / XP400  
> 基线日期：2026-09-09  
> 依据：CrazyDashboard 当前 `main` 分支 + Peugeot Motocycles 官方 Android APK（`com.facomsa.peugeotscooters.peugeot335`）反编译/字符串/协议对照结果 + 当前 XP400 实车研究结论  
> 文档定位：**后续可直接按阶段执行的工程升级清单，不是单纯研究笔记**

---

# 0. 结论先行

CrazyDashboard 当前已经不是“协议验证 Demo”。

目前仓库已经具备：

- XP400 作为 BLE Central / iPhone 作为 BLE Peripheral 的正确角色模型；
- Telit Terminal I/O（TIO）`FEFB` Service；
- 四个 TIO Characteristic；
- Credits 流控；
- Peugeot/FACOMSA 双向 Challenge/Response Authentication；
- BLE 入站分片重组；
- 仪表 Data1 / Data2 / Data3 / Control / ABS 等数据解析；
- Navigation 下发；
- Navigation 去重与合并；
- ANCS 相关实现；
- ELM327 Bluetooth / Wi-Fi OBD；
- CAN Monitor / `ATMA` 被动抓包；
- JSONL / JSON / CSV 抓包持久化；
- UDS/DID 只读探测框架；
- DID Evidence Store；
- Developer operation 前置检查；
- 当前写入/刷写入口默认仍然关闭。

当前最大的工程问题已经从：

> “协议缺不缺”

变成：

> **核心 Manager 过大、职责混杂、BLE 生命周期缺少精确状态机/超时、系统 ANCS 与自定义 ANCS 边界不够清楚、OBD 原始命令入口风险模型不够严格、研究工具与日常业务还没有彻底解耦。**

因此下一阶段不建议继续往 `PTBluetoothManager.swift` 和 `PTHiddenOBDConnector.swift` 里面堆功能。

应优先完成：

1. **BLE 核心拆分**
2. **BLE 生命周期状态机**
3. **官方 APK 行为对齐**
4. **CoreBluetooth State Restoration**
5. **发送队列 / Credits / MTU 进一步收紧**
6. **ANCS 正式路径与实验路径解耦**
7. **OBD Transport / ELM327 / Diagnostic / Sniffer 分层**
8. **Raw Command 风险分类**
9. **CAN Evidence / TEP2020 对比分析工具**
10. **Firmware / Bootloader 研究模块独立化**

---

# 1. 官方 Peugeot APK 已确认的协议基线

下面这些不是猜测，而是当前官方 Android APK 中能够确认的核心行为。

## 1.1 BLE 角色

官方 Android App 的模型是：

```text
XP400 Connectivity Box
        │
        │ BLE Central / GATT Client
        ▼
Phone
BLE Peripheral / GATT Server
```

因此 CrazyDashboard 现在让 iPhone 使用 `CBPeripheralManager` 是正确方向。

不要为了“模拟 Android”再额外增加：

```text
CBCentralManager 主动连接 XP400 Connectivity Box
```

作为正式连接逻辑。

`CBCentralManager` 只应出现在：

- Developer BLE Scanner；
- DFU Fingerprint Scanner；
- 被动研究工具；

而不应该进入 XP400 正常连接链路。

---

## 1.2 TIO Service

官方 APK 使用：

```text
Service
0000FEFB-0000-1000-8000-00805F9B34FB
```

Characteristic：

```text
UART Data RX
00000001-0000-1000-8000-008025000000

UART Data TX
00000002-0000-1000-8000-008025000000

UART Credits RX
00000003-0000-1000-8000-008025000000

UART Credits TX
00000004-0000-1000-8000-008025000000
```

CCCD：

```text
00002902-0000-1000-8000-00805F9B34FB
```

CrazyDashboard 当前 `PTXP400BLEProtocolContract.swift` 和 `PTBluetoothManager.swift` 已经基本完成这一层。

### 结论

**不要重写 UUID 层。**

后续应把 UUID、properties、permissions、credits 参数全部继续收拢到：

```text
PTXP400BLEProtocolContract
```

而不是散落在 Manager。

---

# 2. 官方 APK Credits 行为

官方实现的核心参数：

```text
MAX_CREDITS = 25
LOW_THRESHOLD = 4
```

CrazyDashboard 当前已经存在：

- remote credits 校验；
- 超限拒绝；
- local credits；
- `<= 4` 自动 refill；
- send credits 为 0 时挂起队列；
- Central 补充 Credits 后恢复；
- session reset 时清理 Credits。

这一部分已经从“待实现”变成：

> **需要补测试与拆分，而不是重做。**

---

# 3. 当前 BLE 代码的最大结构问题

当前 `PTBluetoothManager.swift` 已超过 2000 行。

里面同时包含：

```text
UI / UIKit
通知权限
协议常量
配置模型
Telemetry Models
ANCS Model
Navigation Model
Maneuver Map
Authentication
Frame Builder
BLE Peripheral Lifecycle
GATT Service
Subscription
Credits
Send Queue
Navigation Coalescing
Incoming Reassembly
Authentication State Machine
Dashboard Parser
Configuration Command
Delegate / Notification
Session Reset
```

这已经明显超过一个 Manager 应承担的职责。

## 3.1 必须拆分

建议最终结构：

```text
Global/
└── XP400/
    ├── BLE/
    │   ├── Core/
    │   │   ├── PTXP400PeripheralServer.swift
    │   │   ├── PTXP400BLELifecycle.swift
    │   │   ├── PTXP400BLESession.swift
    │   │   └── PTXP400BLEState.swift
    │   │
    │   ├── TIO/
    │   │   ├── PTXP400TIOProfile.swift
    │   │   ├── PTXP400TIOCreditController.swift
    │   │   ├── PTXP400TIOSendQueue.swift
    │   │   └── PTXP400BLEInboundReassembler.swift
    │   │
    │   ├── Authentication/
    │   │   ├── PTXP400Authenticator.swift
    │   │   ├── PTXP400AuthState.swift
    │   │   └── PTXP400AuthCodec.swift
    │   │
    │   ├── Protocol/
    │   │   ├── PTXP400BLEProtocolContract.swift
    │   │   ├── PTXP400Frame.swift
    │   │   ├── PTXP400FrameBuilder.swift
    │   │   ├── PTXP400FrameParser.swift
    │   │   └── PTXP400FrameType.swift
    │   │
    │   ├── Navigation/
    │   │   ├── PTXP400NavigationEncoder.swift
    │   │   ├── PTXP400NavigationScheduler.swift
    │   │   └── PTXP400ManeuverMap.swift
    │   │
    │   ├── Telemetry/
    │   │   ├── PTXP400TelemetryDecoder.swift
    │   │   ├── PTXP400TelemetrySnapshot.swift
    │   │   └── PTXP400TelemetryPublisher.swift
    │   │
    │   ├── ANCS/
    │   │   ├── PTXP400ANCSCoordinator.swift
    │   │   └── PTDashboardANCSProvider.swift
    │   │
    │   └── Diagnostics/
    │       ├── PTXP400BLETraceRecorder.swift
    │       └── PTXP400BLEFingerprintScanner.swift
    │
    └── OBD/
        ...
```

---

# 4. `PTBluetoothManager` 拆分具体计划

## P0：先不改行为，只搬代码

第一阶段不能边拆边改协议。

先完成：

```text
PTBluetoothManager
    ↓
Facade
```

让旧调用方继续：

```swift
PTBluetoothServerManager.shared
```

但内部转发到：

```text
PeripheralServer
Session
Authenticator
TIOCreditController
SendQueue
FrameParser
NavigationScheduler
```

### Facade 最终只保留

```text
startAdvertising()
stopAdvertising()

sendNavigation(...)
sendConfiguration(...)

connectionState
authenticationState
latestTelemetry

delegate / publisher
```

### 不应该继续留在 Facade

```text
UInt8 frame decoding
Challenge 算法
Credits 运算
chunk queue
ANCS protocol
DID/CAN
UILabel / UIColor mapping
Notification helper
```

---

# 5. BLE 生命周期状态机必须升级

当前代码已经有：

```text
PeripheralLifecycleState
authState
isTioSubscribed
isCreditsSubscribed
authenticated
connectedCentral
```

但这些仍然是多个 Bool + enum 的组合。

组合状态容易产生非法状态：

```text
authenticated == true
但
isTioSubscribed == false
```

或者：

```text
connectedCentral != nil
但 service 尚未 configured
```

## 5.1 建议统一成显式状态

```swift
enum PTXP400BLEState: Equatable, Sendable {
    case idle
    case bluetoothUnavailable
    case configuringService
    case advertising
    case centralConnected
    case waitingForSubscriptions
    case authenticating(PTXP400AuthState)
    case ready
    case disconnecting
    case failed(PTXP400BLEFailure)
}
```

所有 UI 和业务只观察：

```text
PTXP400BLEState
```

而不是同时观察 5~10 个属性。

---

# 6. 增加官方 APK 对应的阶段超时

当前 CrazyDashboard BLE Manager 内没有形成完整的 BLE phase timeout abstraction。

官方 Android 实现中存在明确的连接/MTU阶段超时思路。

iOS 虽然没有 Android `requestMtu()` 同构流程，但仍然需要对以下阶段设置 watchdog：

```text
Service configuration
Advertising startup
Central subscription
Authentication phase
Connection frame
Idle session
Send queue stall
```

建议：

```swift
struct PTXP400BLETimeouts {
    let subscription: Duration = .seconds(30)
    let authPhase: Duration = .seconds(6)
    let connectionFrame: Duration = .seconds(6)
    let sendQueueStall: Duration = .seconds(5)
    let sessionIdle: Duration = .seconds(60)
}
```

> 数值应作为可配置值，不要散落 magic number。

## 超时后行为

不要只：

```text
print timeout
```

而要明确：

```text
cancel pending work
clear queue
clear credits
clear reassembler
clear central
reset auth
return advertising
```

---

# 7. CoreBluetooth State Restoration

这是当前值得补的可靠性能力。

创建 `CBPeripheralManager` 时增加：

```swift
CBPeripheralManagerOptionRestoreIdentifierKey
```

并实现：

```swift
peripheralManager(
    _ peripheral: CBPeripheralManager,
    willRestoreState dict: [String : Any]
)
```

目标：

- iOS 杀进程/系统回收后恢复 BLE Peripheral；
- 恢复 Service；
- 恢复 advertising intent；
- 不恢复上一辆车的 session/auth/credits；
- 恢复后必须重新走 authentication。

### 原则

恢复：

```text
Peripheral infrastructure
```

不恢复：

```text
Authentication session
Credits
Pending Navigation
Connected Central identity
```

---

# 8. TIO Chunk Size 优化

官方协议本身以 20-byte UART chunk 为核心兼容基线。

CrazyDashboard 当前 `sendChunkedData` 应继续保持：

```text
protocolMaximum = 20
```

但实现最好不要把 BLE transport capability 完全忽略。

建议：

```swift
let transportMaximum =
    connectedCentral?.maximumUpdateValueLength ?? 20

let chunkSize = min(
    PTXP400BLEProtocol.maxUARTChunkSize,
    transportMaximum
)
```

### 为什么仍然不能直接用更大 MTU

因为：

```text
CoreBluetooth 可发 185 bytes
```

不等于：

```text
XP400 TIO application 接受 185-byte UART packet
```

因此：

> **协议上限仍然固定 20，CoreBluetooth 最大长度只用于避免设备/系统更小限制。**

---

# 9. Send Queue 重构

当前 Send Queue 已经有：

- Credits gating；
- `updateValue == false` backpressure；
- `peripheralManagerIsReady` 恢复；
- Navigation 合并。

下一步应从 Manager 移出成为：

```text
PTXP400TIOSendQueue
```

## Job 类型

建议：

```swift
enum PTXP400SendPriority {
    case authentication
    case control
    case navigation
    case background
}
```

以及：

```swift
enum PTXP400SendKind {
    case auth
    case navigation
    case configuration
    case credits
    case system
}
```

### 队列策略

Authentication：

```text
不可 coalesce
最高优先级
```

Navigation：

```text
只保留最新状态
可 coalesce
```

Configuration：

```text
FIFO
```

Credits：

```text
立即
```

---

# 10. Send Queue 增加 Session Token

当前异步 callback 很容易在：

```text
旧 session
disconnect
新 session connect
```

后错误执行。

建议每次建立新的 session：

```swift
let sessionID = UUID()
```

每个 Job 保存：

```text
sessionID
```

发送前：

```swift
guard job.sessionID == currentSession.id else {
    drop
}
```

这样可以彻底避免 stale jobs。

---

# 11. Authentication 从 Manager 完全拆走

当前 `PTScooterAuth` 应升级为：

```text
PTXP400Authenticator
```

职责只包含：

```text
Challenge generation
Challenge validation
Key ID
Response generation
State transition validation
```

不要知道：

```text
CBPeripheralManager
Characteristic
Navigation
UI
```

## 11.1 Auth State

建议：

```swift
enum PTXP400AuthState {
    case waitingForKeyConfiguration
    case challengeSent
    case waitingForRemoteChallenge
    case responseSent
    case waitingForConnectionFrame
    case authenticated
}
```

并由：

```text
Authenticator
```

生成：

```text
AuthAction
```

例如：

```swift
enum PTXP400AuthAction {
    case send(Data)
    case authenticated
    case reject(reason: String)
}
```

BLE 层只负责执行 action。

---

# 12. Authentication 数据生命周期

Challenge / Response 属于 session 数据。

完成认证或断开后应：

```text
clear randomNumbers
clear pending challenge
clear temporary response
```

Swift 不能保证绝对安全擦除内存，但至少不要让 session 数据长期存活于 singleton。

---

# 13. `PTXP400BLEInboundReassembler`

当前这个模块是正确方向，并且应该保留。

下一步主要补：

- 最大 buffer 长度；
- malformed packet 统计；
- resync 次数；
- session reset；
- fuzz tests；
- 多帧一次 Write；
- 一帧拆成 N 次 Write；
- junk + valid frame；
- duplicated frame；
- truncated frame；
- oversized payload。

建议增加：

```swift
struct PTXP400ReassemblyMetrics {
    var bytesReceived: Int
    var framesProduced: Int
    var droppedBytes: Int
    var resyncCount: Int
}
```

这些信息对以后抓不同 firmware 的 Box 很有价值。

---

# 14. Frame Parser 从 Manager 拆离

当前 Manager 中的数据解析已经很多：

```text
Control
Data1
Data2
Data3
ABS
Configuration
...
```

建议：

```text
PTXP400TelemetryDecoder
```

输入：

```swift
Data
```

输出：

```swift
PTXP400TelemetryEvent
```

例如：

```swift
enum PTXP400TelemetryEvent {
    case control(PTDashboardControl)
    case data1(PTDashboardData1)
    case data2(PTDashboardData2)
    case data3(PTDashboardData3)
    case abs(PTAbsStatus)
    case unknown(raw: Data)
}
```

BLE Manager 不应该知道：

```text
fuelLevelPct
engineTempC
odoKm
TCS mode
```

---

# 15. 保留 Raw Payload

当前项目已经开始为数据模型保存：

```text
rawPayload
availability
```

这是非常正确的方向。

不要为了 UI 方便改回：

```text
解析失败 = 0
```

例如：

```text
0 km/h
```

和：

```text
该字段当前未提供
```

必须是两个状态。

后续所有 Telemetry Model 应统一：

```text
decoded value
+
availability
+
raw payload
+
decode confidence/evidence
```

---

# 16. Telemetry Snapshot

不要让 UI 同时监听：

```text
Data1
Data2
Data3
ABS
Control
```

建议聚合：

```swift
struct PTXP400TelemetrySnapshot {
    var speed: ...
    var rpm: ...
    var odometer: ...
    var trip: ...
    var fuel: ...
    var range: ...
    var batteryVoltage: ...
    var engineTemperature: ...
    var outsideTemperature: ...
    var abs: ...
    var tcs: ...
    var lights: ...
    var configuration: ...
    var lastUpdatedAt: ...
}
```

所有 ViewController 观察 snapshot。

---

# 17. Navigation Scheduler

当前已经有：

```text
fingerprint
minimum send interval
pending navigation
remove queued navigation jobs
```

这部分应独立成：

```text
PTXP400NavigationScheduler
```

职责：

```text
coalesce
rate limit
latest-state delivery
welcome message bypass
destination reached
reroute
GPS lost
```

以后地图模块不应该直接接触 BLE Credits。

---

# 18. Maneuver Map

当前代码中部分 maneuver 标记仍然有：

```text
推测
```

例如 Ferry 等。

建议给每个值增加证据等级：

```swift
enum PTProtocolEvidence {
    case officialAPK
    case captured
    case crossValidated
    case inferred
    case unknown
}
```

例如：

```swift
struct PTManeuverDefinition {
    let rawValue: UInt8
    let semantic: PTManeuver
    let evidence: PTProtocolEvidence
}
```

避免未来“推测值”逐渐被当成“官方确认值”。

---

# 19. ANCS：必须重新划清边界

这是 BLE 模块下一阶段最需要整理的一部分。

iOS 正式路径应该优先依赖：

> **系统 ANCS**

而不是让 CrazyDashboard 自己长期维护一套完整假的 ANCS Server。

## 当前建议

```text
PTDashboardANCSProvider
```

降级为：

```text
Experimental / Compatibility Layer
```

不要和 TIO Server 强耦合。

### 正式路径

```text
iOS System ANCS
        │
        ▼
XP400 Connectivity Box
```

CrazyDashboard 主要负责：

```text
请求通知权限
生成本地通知
业务通知
```

### Experimental Provider

只用于：

- 协议研究；
- 模拟；
- Unit Test；
- 非系统 ANCS 环境；

不要成为正常连接成功的必要条件。

---

# 20. 删除或隔离 stale ANCS helper

当前 `PTBluetoothManager` 仍然存在：

```swift
sendCustomAlertToDashboard(...)
```

但内部实际上只：

```text
build frame
```

并没有真正发送。

这属于典型 stale experimental API。

建议：

```text
DELETE
```

或者移动：

```text
Experimental/Legacy/
```

不要继续让业务代码误以为它是正式可用 API。

---

# 21. Advertisement 行为对齐

官方 Android APK 使用：

```text
PEUGEOT
```

作为 BLE local name。

CrazyDashboard 应把：

```text
local name
advertised service UUID
manufacturer data
```

统一放入：

```text
PTXP400AdvertisingProfile
```

例如：

```swift
struct PTXP400AdvertisingProfile {
    let localName: String
    let serviceUUIDs: [CBUUID]
    let manufacturerData: Data?
}
```

---

# 22. TIO Manufacturer Data

Telit Terminal I/O Profile 的官方实现支持在广播 manufacturer specific data 中携带：

```text
compatibility version
operation mode
connection requested
```

建议创建：

```text
PTTIOAdvertisementManufacturerData
```

但不要直接写死未知值。

策略：

```text
先抓官方 Android App advertisement
↓
确认实际字节
↓
再实现
```

当前阶段标记：

```text
P1 research
```

不要因为 Telit 文档存在就自动假设 Peugeot App 100% 使用相同 manufacturer payload。

---

# 23. BLE Fingerprint Scanner

必须单独做一个 Developer Tool：

```text
PTXP400BLEFingerprintScanner
```

使用：

```text
CBCentralManager
```

仅用于扫描。

记录：

```text
timestamp
name
identifier
RSSI
serviceUUIDs
manufacturerData
overflowServiceUUIDs
solicitedServiceUUIDs
txPower
connectable
raw advertisement dictionary
```

目标：

- 比较正常 XP400 周边 BLE；
- 将来观察 Dealer Update；
- 查找 Bootloader 广播；
- 查找 `BM+S_DFU`；
- 查找 Nordic Legacy DFU 1530；
- 查找 Secure DFU FE59；
- 查找未知 FACOMSA maintenance service。

这个 Scanner 必须与：

```text
PTXP400PeripheralServer
```

完全独立。

---

# 24. 官方 APK 中没有 Connectivity Box OTA

官方 APK 里虽然存在：

```text
ConnectivityBox
firmwareVersion
firmwareDate
hardwareId
```

但当前反编译没有发现：

```text
firmware URL
firmware binary
downloadFirmware
DFU
Bootloader
AT+DFUSTART
FE59
Nordic 1530
```

`UpgradeFragment` 更符合 Android App 自身跳转商店更新。

因此 CrazyDashboard **当前不要增加所谓“Peugeot Box OTA”正式模块**。

---

# 25. Firmware Research 模块必须独立

未来如果研究：

```text
Connectivity Box
FACOMSA Instrument
TEP2020
Bootloader
Firmware Resource
```

建议单独：

```text
Global/Research/
```

而不是：

```text
Global/BLE/
Global/OBD/
```

里面直接堆实验代码。

建议：

```text
Global/
└── Research/
    ├── XP400/
    │   ├── BLEFingerprint/
    │   ├── CANCorrelation/
    │   ├── TEP2020/
    │   ├── ECUIdentification/
    │   └── Firmware/
    │
    └── Shared/
        ├── Evidence/
        ├── Hex/
        └── Capture/
```

---

# 26. OBD 模块当前评价

当前 OBD 已经不只是标准 PID Reader。

现在包含：

```text
PTHiddenOBDConnector
PTCANRecorder
PTDashboardHacker
PTUDSDiagnosticService
PTXP400InstructionCatalog
PTXP400InstructionEvidenceStore
```

这套方向很有价值。

但最大的问题和 BLE 一样：

> **Transport、ELM327 State、Polling、Raw Command、Sniffer、UDS、Research 混在一起。**

---

# 27. `PTHiddenOBDConnector.swift` 必须拆

当前文件已经超过 2000 行。

建议：

```text
OBD/
├── Transport/
│   ├── PTOBDTransport.swift
│   ├── PTBLEOBDTransport.swift
│   └── PTWiFiOBDTransport.swift
│
├── ELM327/
│   ├── PTELM327Session.swift
│   ├── PTELM327CommandQueue.swift
│   ├── PTELM327Parser.swift
│   ├── PTELM327Capabilities.swift
│   └── PTELM327Monitor.swift
│
├── Telemetry/
│   ├── PTOBDPIDCatalog.swift
│   ├── PTOBDPollingEngine.swift
│   └── PTOBDTelemetryDecoder.swift
│
├── CAN/
│   ├── PTCANRecorder.swift
│   ├── PTCANFrameParser.swift
│   ├── PTCANCaptureStore.swift
│   ├── PTCANDiffEngine.swift
│   └── PTCANCorrelationEngine.swift
│
├── Diagnostics/
│   ├── PTUDSTransport.swift
│   ├── PTUDSReadService.swift
│   ├── PTOBDDiagnosticAddress.swift
│   └── PTOBDReadOnlyCatalog.swift
│
└── Research/
    ├── PTDashboardResearchService.swift
    ├── PTXP400InstructionCatalog.swift
    └── PTXP400InstructionEvidenceStore.swift
```

---

# 28. Transport Protocol

BLE ELM327 和 Wi-Fi ELM327 应统一：

```swift
protocol PTOBDTransport: AnyObject {
    var state: PTOBDTransportState { get }

    func connect() async throws
    func disconnect() async

    func write(_ command: String) async throws -> String
    func enterStreamingMode(...)
    func stopStreamingMode()
}
```

上层不要再：

```text
switch activeConnectionType
case bluetooth:
case wifi:
```

散落几十处。

---

# 29. ELM327 独立状态机

建议：

```swift
enum PTELM327State {
    case disconnected
    case transportConnected
    case resetting
    case configuring
    case ready
    case polling
    case monitoring
    case diagnosticExclusive
    case failed
}
```

这样：

```text
Polling
ATMA
UDS
Raw Command
```

之间就不会互相抢总线。

---

# 30. Diagnostic Bus Lease

这是 OBD 下一步最值得实现的基础设施。

创建：

```text
PTOBDBusLease
```

例如：

```swift
enum PTOBDBusLeaseKind {
    case telemetry
    case sniffer
    case diagnosticRead
    case developerWrite
}
```

获得：

```text
diagnosticRead
```

时自动：

```text
暂停 polling
flush command queue
保存当前 ELM configuration
执行 diagnostic
恢复 ELM configuration
恢复 polling
```

不要在每个方法内部手写：

```text
pause polling
sleep
send
resume
```

---

# 31. Raw Command Injection 必须收紧

当前代码存在：

```swift
injectRawHexCommand(...)
```

注释甚至明确提到：

```text
$22
$27
$2E
ATMA
```

虽然当前更危险的 Dashboard Write/Flash 入口已经默认 blocked，这是好的。

但是一个“任意原始命令” API 本身仍然可以绕过高层安全边界。

建议增加：

```text
PTOBDCommandClassifier
```

---

# 32. Command Risk Classification

例如：

```swift
enum PTOBDCommandRisk {
    case passive
    case readOnly
    case stateChanging
    case write
    case programming
    case unknown
}
```

分类：

```text
ATMA              passive
22 xxxx            readOnly
19 xx              readOnly
10 xx              stateChanging
27 xx              stateChanging/security
2E xxxx            write
31 xx              stateChanging
34 ...             programming
36 ...             programming
37 ...             programming
11 xx              reset
unknown            unknown
```

### 默认策略

Release：

```text
passive
readOnly
```

Developer：

```text
passive
readOnly
有限 stateChanging
```

Explicit Lab Build：

```text
write/programming
```

也不能自动执行，仍然要求 preflight。

---

# 33. `PTDashboardHacker` 建议重命名

从代码职责看，现在已经不是“hack helper”，而是一套：

```text
XP400 Diagnostic Research Service
```

建议：

```text
PTDashboardHacker
↓
PTXP400DashboardResearchService
```

原因：

- 文件职责更清楚；
- GitHub 对外更专业；
- 减少未来误调用；
- 有利于和 FACOMSA / Peugeot 技术人员交流；
- 明确这是 Research，不是正式车辆控制 API。

---

# 34. 当前写入路径保持关闭

当前：

```swift
writeDashboardConfig(...)
```

即使被调用，仍返回：

```text
false
```

并打印：

```text
配置写入仍未开放
```

这个设计暂时不要改。

在以下条件全部完成前：

```text
真实 ECU 地址
真实协议
真实 DID
真实 payload
真实 checksum
真实 session
真实 backup
已知恢复手段
bench ECU
```

不要开放车辆仪表写入。

---

# 35. UDS 模块保持 Read-Only First

当前 `PTUDSDiagnosticService` 并没有实现：

```text
RequestDownload
TransferData
SecurityAccess
```

这是合理的。

下一阶段优先继续完善：

```text
ReadDataByIdentifier
ReadDTCInformation
ECU Identification
Tester Present（仅在确认需要时）
```

而不是优先：

```text
0x27
0x2E
0x34
0x36
```

---

# 36. DID Fuzz 必须继续限制范围

当前项目已经有：

```text
maximumCount
duration
delay
developer authorization
```

这些保护应保留。

下一步增加：

```text
adaptive rate limit
negative response backoff
ECU sleep detection
bus error stop
battery voltage guard
capture correlation
```

---

# 37. CAN Recorder 当前基础很好

`PTCANRecorder` 当前已经具备：

- Schema Version；
- `PTCANFrame`；
- direction；
- timestamp；
- sequence；
- header；
- data；
- DLC；
- JSONL 实时持久化；
- crash recovery；
- JSON；
- CSV；
- dropped count；
- metadata；
- capture event。

因此：

> **不要重写 Recorder。**

下一步重点是分析层。

---

# 38. 新增 CAN Diff Engine

实现：

```text
PTCANDiffEngine
```

输入：

```text
Capture A
Capture B
```

输出：

```text
新增 CAN ID
消失 CAN ID
频率变化
Payload bit entropy
Byte position variation
周期变化
事件附近突变
```

例如：

```text
A = ignition only
B = CrazyDashboard advertising
C = BLE connected
D = authenticated
E = navigation
```

自动生成：

```text
A → B
B → C
C → D
D → E
```

Diff Report。

---

# 39. CAN Event Marker

虽然 Recorder 已经有 events，下一步 UI 应提供一键 marker：

```text
Ignition ON
Start BLE Advertising
BLE Connected
Authenticated
Open Dashboard Settings
Change Color
Start Navigation
Start TEP2020
Open Dashboard ECU
Read Identification
Enter Update Page
```

每个 marker 写入：

```text
monotonic timestamp
wall clock
event type
optional note
```

以后做 TEP2020 对比会非常有价值。

---

# 40. CAN Correlation Engine

新增：

```text
PTCANCorrelationEngine
```

目标：

给一个操作窗口：

```text
eventTime ± 2s
```

自动寻找：

```text
发生变化最大的 CAN IDs
```

排序：

```text
score =
frequency_delta
+ payload_delta
+ new_frame_score
+ temporal_proximity
```

这样定位 Connectivity Box / TFT 仪表 CAN ID 比肉眼翻日志效率高得多。

---

# 41. TEP2020 专用 Capture Template

新增预置模板：

```text
XP400_TEP_Idle
XP400_TEP_Connect
XP400_TEP_ECU_List
XP400_TEP_Dashboard_Identification
XP400_TEP_Connectivity_Identification
XP400_TEP_Dashboard_Update_Check
```

每个模板告诉用户：

```text
什么时候开始抓
什么时候打 marker
什么时候停止
```

---

# 42. Evidence Store 升级

当前 `PTXP400InstructionEvidenceStore` 已经是一个很好的方向。

建议每条 evidence 不只存：

```text
command
response
```

而是：

```swift
struct PTXP400ProtocolEvidence {
    let id: UUID

    let source: Source
    let transport: Transport
    let vehicleModel: String
    let vehicleYear: Int?
    let ecuAddress: PTOBDDiagnosticAddress?

    let request: String?
    let response: String?

    let captureID: UUID?
    let eventID: UUID?

    let firstSeenAt: Date
    let lastSeenAt: Date

    let repetitionCount: Int
    let confidence: Confidence
    let safetyClassification: SafetyClassification

    let notes: String?
}
```

---

# 43. Evidence Confidence

统一：

```swift
enum PTProtocolConfidence {
    case official
    case capturedRepeatable
    case capturedOnce
    case crossVehicle
    case inferred
    case speculative
}
```

例如：

```text
FEFB UUID
official

Credits 25/4
official + captured

XP400 Dashboard CAN ID
capturedRepeatable

某 DID = startup logo
speculative
```

这样未来不会把研究假设写成代码常量。

---

# 44. 官方 APK Evidence Snapshot

建议把当前 APK 分析结果固化到仓库：

```text
Docs/
└── ReverseEngineering/
    └── PeugeotAndroidApp/
        ├── README.md
        ├── BLE-TIO.md
        ├── Authentication.md
        ├── Navigation.md
        ├── TelemetryFrames.md
        ├── ANCS.md
        ├── ConnectivityBoxModel.md
        └── FirmwareFindings.md
```

尤其记录：

```text
APK version
SHA256
package
date analyzed
class names
UUIDs
constants
method evidence
```

避免以后换 APK 后忘记：

```text
哪个结论来自哪个版本
```

---

# 45. APK 与 CrazyDashboard 自动对照测试

创建：

```text
PTXP400ProtocolFixtureTests
```

Fixture 不需要保存整个 APK。

只保存已确认的合法 packet：

```text
auth key config
challenge
response
connection frame
data1
data2
data3
navigation
credits
```

测试：

```text
Android known frame
↓
Swift decoder
↓
expected model
```

---

# 46. Protocol Golden Tests

每一个 FrameBuilder 都应有 Golden Hex：

```swift
func test_navigation_frame_matches_official_fixture()
func test_key_id_matches_official_fixture()
func test_challenge_response_matches_fixture()
func test_credit_refill()
```

这样重构 Manager 时不会把协议改坏。

---

# 47. Fuzz Tests

重点：

```text
Inbound Reassembler
Telemetry Decoder
Credit Decoder
Auth Parser
ELM327 parser
CAN frame parser
UDS response parser
```

输入：

```text
empty
1 byte
random bytes
oversized
truncated
duplicated
concatenated
invalid hex
lowercase
spaces
CRLF variations
```

要求：

```text
不 crash
不越界
不死循环
不产生错误写指令
```

---

# 48. Swift 6 Concurrency

下一阶段所有新模块优先按 Swift 6 设计。

建议：

### BLE

由于 CoreBluetooth delegate 天然 callback-based：

```text
@MainActor
PTXP400PeripheralServer
```

或者使用一条明确 Serial Actor。

不要同时：

```text
Main Queue
DispatchQueue
Task
NSLock
```

混用来保护同一个 session state。

### Capture / File

像当前 `PTCANCaptureStore`：

```text
serial state queue
serial write queue
```

已经是明确边界。

如果未来迁 Actor：

```text
一次迁完整模块
```

不要半 Actor 半 lock。

---

# 49. Logger 统一

当前日志很多：

```text
PTOBDLogger.moto
PTOBDLogger.obd
PTNSLogConsole
```

建议建立：

```text
PTVehicleLogger
```

Category：

```text
ble.lifecycle
ble.tio
ble.auth
ble.navigation
ble.telemetry
ble.ancs

obd.transport
obd.elm327
obd.telemetry
obd.can
obd.uds

research.tep
research.firmware
```

支持：

```text
trace
debug
info
warning
error
```

---

# 50. Trace ID

每次连接：

```text
sessionID
```

每次 CAN Capture：

```text
captureID
```

每次 Diagnostic：

```text
operationID
```

日志统一打印：

```text
[BLE:xxxx]
[CAN:xxxx]
[UDS:xxxx]
```

后续跨 BLE + CAN 对时会非常方便。

---

# 51. UI 不直接依赖协议对象

目前 UI 层不应该直接操作：

```text
CBMutableCharacteristic
sendCredits
authState
raw DID
```

统一 ViewModel / Controller Interface：

```text
XP400ConnectionStatus
XP400TelemetrySnapshot
XP400NavigationStatus
XP400ResearchStatus
```

---

# 52. 正式功能与 Developer 功能分开

建议：

```text
CrazyDashboard
├── User
│   ├── Dashboard
│   ├── Navigation
│   ├── OBD
│   └── Settings
│
└── Developer
    ├── BLE Trace
    ├── BLE Scanner
    ├── CAN Recorder
    ├── CAN Diff
    ├── ECU Probe
    ├── Evidence
    └── Firmware Research
```

并使用：

```text
Build Configuration
Feature Flag
Developer Mode
```

隔离。

---

# 53. 不要把 Research API 暴露成普通 API

例如：

```swift
injectRawHexCommand
fuzzDashboardDIDs
performFullVehicleDeepDump
```

都不应该出现在：

```text
正常业务 autocomplete
```

建议放：

```text
Research
```

namespace / type 中。

---

# 54. Safety Gate

建议统一：

```text
PTVehicleOperationPolicy
```

输入：

```text
Build Mode
Connection State
Vehicle Stationary
Engine State
Battery Voltage
Known ECU
Protocol Evidence
User Developer Mode
```

输出：

```text
allowed / denied
blockers
```

目前不同模块已有部分 preflight，可以继续统一。

---

# 55. Release Build 原则

Release Build：

```text
禁止：
UDS arbitrary write
SecurityAccess automation
RequestDownload
TransferData
ECU Reset
unknown raw mutation commands
```

允许：

```text
Telemetry
Read-only DID
DTC read
CAN passive capture
BLE fingerprint
```

---

# 56. Firmware / Bootloader 研究路线

当前研究结论：

```text
Connectivity Box OTA
≠
官方手机 App OTA
```

而 FACOMSA TFT / Peugeot Dealer ECU Update 更值得研究。

建议未来只先实现：

```text
FirmwareMetadata
FirmwareContainerInspector
ResourceScanner
```

不要先实现：

```text
FirmwareFlasher
```

---

# 57. Firmware Container Inspector

未来拿到 firmware 文件后：

```text
Research/Firmware/
```

提供只读：

```text
file size
SHA256
entropy
magic detection
partition detection
compression detection
strings
resource signatures
```

扫描：

```text
ELF
uImage
FIT
SquashFS
CRAMFS
UBIFS
FAT
LZ4
LZMA
zlib
gzip
PNG
JPEG
BMP
RGB565 candidate
RLE candidate
font signatures
```

---

# 58. Graphics Resource Research

根据 FACOMSA 历史技术资料，启动 Logo 不一定是 PNG。

需要支持分析：

```text
RGB565
ARGB
RLE
OpenVG/vector-like resources
texture atlas
resource table
compressed image block
```

目标：

```text
Pulsion classic Lion
vs
XP400 shield Lion
```

做 binary/resource diff。

---

# 59. 当前不要做的事情

## 不要

### 1

直接给 XP400 Box 发送：

```text
AT+DFUSTART
```

因为目前还没有证明：

```text
XP400 物理模块 == 标准 BlueMod
```

### 2

直接实现 Nordic DFU 并刷真实 Box。

### 3

猜：

```text
F1A0 = startup logo
```

然后给真实 TFT 发 `2E`。

### 4

把 guessed CAN ID：

```text
7A0 / 7A8
```

当成正式常量。

### 5

在原车仪表上测试 Firmware Write。

---

# 60. 建议新增文件清单

## BLE

```text
PTXP400PeripheralServer.swift
PTXP400BLEState.swift
PTXP400BLESession.swift
PTXP400BLETimeoutController.swift

PTXP400TIOProfile.swift
PTXP400TIOCreditController.swift
PTXP400TIOSendQueue.swift

PTXP400Authenticator.swift
PTXP400AuthState.swift

PTXP400Frame.swift
PTXP400FrameBuilder.swift
PTXP400FrameParser.swift

PTXP400TelemetryDecoder.swift
PTXP400TelemetrySnapshot.swift

PTXP400NavigationScheduler.swift

PTXP400ANCSCoordinator.swift

PTXP400BLETraceRecorder.swift
PTXP400BLEFingerprintScanner.swift
```

## OBD

```text
PTOBDTransport.swift
PTBLEOBDTransport.swift
PTWiFiOBDTransport.swift

PTELM327Session.swift
PTELM327State.swift
PTELM327CommandQueue.swift
PTELM327Monitor.swift

PTOBDBusLease.swift
PTOBDCommandClassifier.swift
PTVehicleOperationPolicy.swift

PTCANFrameParser.swift
PTCANDiffEngine.swift
PTCANCorrelationEngine.swift

PTXP400DashboardResearchService.swift
```

---

# 61. 建议删除 / 降级 / 重命名

## 删除或 Legacy

```text
sendCustomAlertToDashboard()
```

如果没有正式使用路径。

## 重命名

```text
PTDashboardHacker
→
PTXP400DashboardResearchService
```

## 缩小

```text
PTBluetoothManager
→
Facade only
```

## 缩小

```text
PTHiddenOBDConnector
→
Transport facade / compatibility facade
```

---

# 62. 第一阶段实施顺序：P0

目标：

> **冻结当前已工作的行为。**

先做：

- [x] 为 Auth 建 Fixture
- [x] 为 TIO Credits 建 Fixture
- [x] 为 Navigation Frame 建 Fixture
- [x] 为 Data1/2/3 建 Fixture
- [x] 为 ABS 建 Fixture
- [x] 为 Reassembler 建 Unit Tests
- [ ] 记录一个当前可成功连接 XP400 的完整 BLE Trace
- [ ] 记录一份正常 CAN baseline

### 完成条件

重构后：

```text
同一 Fixture
同一输出
```

---

# 63. 第二阶段：P1 BLE Core Refactor

- [x] 新建 `PTXP400BLESession`
- [x] 新建 `PTXP400BLEState`
- [x] 新建 `PTXP400Authenticator`
- [x] 新建 `PTXP400TIOCreditController`
- [x] 新建 `PTXP400TIOSendQueue`
- [x] 新建 `PTXP400TelemetryDecoder`
- [x] 新建 `PTXP400NavigationScheduler`
- [x] 保留旧 Manager 为 Facade
- [x] 不改 public API

### 完成条件

`PTBluetoothManager.swift`：

```text
< 600 lines
```

理想：

```text
300~500 lines
```

---

# 64. 第三阶段：P2 BLE Reliability

- [x] Phase timeout（当前接入 central subscription；其余阶段等待稳定核心 Hook）
- [x] Session token
- [x] CoreBluetooth State Restoration（2026-09-11 已接入 restoration identifier / willRestoreState）
- [x] dynamic transport maximum（外围策略已完成；实际发送分片等待稳定核心 Hook）
- [x] send queue stall detector（纯检测器已完成；实际队列 Hook 等待稳定核心开放）
- [x] advertisement profile（FEFB Service UUID 边界已固化）
- [ ] official local name parity（等待 Android 或实车广播证据）
- [x] malformed write response（Credits 校验器已完成；实际 GATT Hook 等待稳定核心开放）
- [x] metrics
- [x] trace export

### 完成条件

以下场景不会卡死：

```text
Bluetooth off/on
App background/foreground
XP400 ignition off/on
subscribe 一半断线
Auth 半途断线
Credits 耗尽
updateValue backpressure
App 被系统回收
```

## P2 实施记录（2026-09-09）

本轮遵循“稳定核心不改”的边界，`PTBluetoothManager.swift`、
`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 均未修改。已完成的是可以在外围安全接入、不会复制第二套 BLE 传输层的可靠性能力：

> 历史说明：本段记录的是 2026-09-09 的冻结边界；`PTBluetoothManager.swift` 的恢复入口已在 2026-09-11 的 P1 续记中接入，硬件恢复验证仍未完成。

- [x] Session Token：为每次真实或 Mock 仪表连接尝试分配新的 UUID 和 generation，超时任务及延迟回调不会跨越连接代次。
- [x] Phase Timeout：继续使用现有集中式 watchdog，并为当前可观测的 central subscription 阶段接入 Token 校验、超时收口和广播停止。
- [x] Expected Reconnect：保留用户连接意图，支持蓝牙开关、点火恢复和稳定外设回调后的自动接受重连；用户主动断开、Mock 停止和超时会清除意图。
- [x] Background / Foreground Reconcile：应用回到前台时重新校正稳定外设生命周期；后台先完成已有车库快照 flush。
- [x] Late Callback Guard：忽略无连接意图的成功回调，以及用户主动断开或超时后的迟到断开回调。
- [x] Metrics：新增有界、隐私安全的 BLE 生命周期指标，不保存 VIN、坐标或原始 Payload。
- [x] Trace Export：支持导出可靠性 JSON；协议证据导出继续复用已有 `PTProtocolDiscoveryRecorder`，不重复保存原始抓包。
- [x] Dynamic Transport Policy：新增纯策略，按 `maximumUpdateValueLength` 与已确认的 20 字节协议上限选择安全分片长度。
- [x] Send Queue Stall Detector：新增纯状态检测器，可识别 `updateValue` 背压后持续无进度的队列阻塞。
- [x] Malformed Write Validator：复用现有 Credits 校验边界，统一识别缺失、长度错误、非法值和余额溢出。
- [x] Advertisement Profile：固化 FEFB Service UUID 匹配边界；在没有 Android 或实车证据前不猜测官方 Local Name。
- [x] Swift 6 Isolation：P2 纯值类型及其依赖的既有 P0 生命周期类型明确为 `nonisolated`，避免默认 actor 隔离警告升级。
- [x] Tests：增加 Session Token、传输上限、Credits、广播 Profile、队列停滞和有界指标导出测试；P2 测试已纳入工程测试 Target。

### 受稳定核心边界限制的延期项

以下内容已经准备了外围策略或记录入口，但不能在不修改冻结核心的情况下声称已经接入真实传输：

- [x] CoreBluetooth State Restoration：已在 2026-09-11 接入 restoration identifier、恢复服务校验和 `willRestoreState`；真实系统回收后的设备验证仍待执行。
- [ ] 实际动态分片：核心的 `CBPeripheral.maximumUpdateValueLength` 和固定发送分片位于私有实现中，本轮未复制或绕过发送队列。
- [ ] 实际发送队列停滞监控：核心的 queue、`isSending` 和 `sendCredits` 未暴露可靠性回调；当前只交付纯检测器。
- [ ] 实际 GATT malformed write 埋点：外围校验器已完成，但核心响应/写入路径仍未开放统一事件 Hook。
- [ ] Official Local Name parity：尚无可信 Android 广播或实车抓包证据，因此只提供可配置 Profile，不写入猜测名称。
- [ ] 完整阶段超时：当前只把 central subscription 接入稳定回调；认证、连接帧和发送队列阶段需核心提供明确阶段事件后再接入。
- [ ] App 被系统回收后的 CoreBluetooth 系统恢复：当前仅保留已有 App 级恢复入口，未冒充系统 State Restoration。
- [ ] 实车/XCTest 验证：本机当前 Scheme 没有可用的兼容模拟器目标，需在真实配对设备或兼容 CI 目的地完成。

### P2 验证结果

- `swiftc -parse`：P2 新文件、协调器和相关 P0 文件通过语法检查。
- `git diff --check`：通过。
- 冻结核心差异检查：三个冻结核心文件无差异。
- 无签名 iOS `build-for-testing`：通过，P2 源码与测试 Bundle 均被编译。
- XCTest 实际执行和 XP400 真车验证：本轮未执行，不能替代上述编译结论。

---

# 65. 第四阶段：P3 ANCS

- [x] 明确 system ANCS 正式路径
- [x] 自定义 provider 标 Experimental
- [ ] 清除 stale helper（位于冻结的 `PTBluetoothManager.swift`，保留待核心解冻后删除）
- [x] 测试 Call / SMS / App Notification（验证矩阵和真机操作指引已完成，真实设备测试待执行）
- [x] 测试 Action 支持边界（系统托管，不提供 App 动作桥接）
- [x] 权限失败不影响 TIO Connection
- [x] ANCS 失败不影响 Navigation

## P3 实施记录（2026-09-09）

本阶段将 iOS 系统通知和 App 自有 ANCS 风格 GATT 通道彻底分开。正常车辆连接、导航和系统通知不再依赖实验 Provider；`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 继续保持未修改。

### 已完成

- [x] 系统路径统一由 `PTXP400ANCSCoordinator.scheduleSystemNotification` 转发到已有 `PTNotificationCenter`，继续使用 `UNUserNotificationCenter` 权限、分类、去重和冷却规则。
- [x] 设置页只保留系统通知权限、本地 iPhone 测试和 XP400 真机验证指引；本地测试结果只表示 iOS 通知中心已接受，不宣称仪表已显示。
- [x] `PTDashboardANCSProvider` 明确标记为 Experimental，增加安装成功结果和可逆 `uninstall()`；卸载时移除实验服务并尽可能恢复稳定 `CBPeripheralManager` 委托。
- [x] 自有 Provider 测试入口移动到开发者工具，不再出现在普通通知设置流程中；发送结果明确区分 queued、waiting 和 unavailable。
- [x] 修复实验 Provider 单特征取消订阅时误清除另一特征状态的问题；只有两个 ANCS 特征都取消订阅后才清理整个会话。
- [x] 新增 `PTXP400ANCSNotificationSource` 和 `PTXP400ANCSVerificationCase`，固定覆盖电话、短信和第三方 App 通知三类真实来源。
- [x] 明确 Action 边界：电话/短信/第三方通知的操作由 iOS、配对关系和仪表固件系统托管，PTSpeed 不伪造动作回调或声称可以控制系统通知。
- [x] 新增 `PTXP400P3Tests`，覆盖三类通知验证矩阵、系统路径标识、Experimental 标识和 ANCS UUID 契约。
- [x] 新增停止实验 Provider 的开发者入口，便于实车验证完成后恢复稳定 BLE 委托。

### 可靠性与隔离边界

- 系统通知权限为 `denied`、`notDetermined` 或本地通知提交失败时，只返回 `PTNotificationDeliveryResult`，不会调用 BLE Provider，也不会改变 TIO 连接状态。
- 实验 Provider 的 GATT 注册失败、订阅缺失、队列满或卸载，只影响实验通道；正常导航仍通过既有导航发送链路运行。
- `PTDashboardANCSProvider` 复用现有外设管理器只是实验兼容路径，不等同于 iOS 向 App 暴露系统 ANCS 消费者 API。

### 保留延期

- [ ] `PTBluetoothManager.sendCustomAlertToDashboard(...)` 仍位于冻结核心中，当前没有业务调用且内部不执行真实发送；待核心允许修改时删除，避免与统一 Coordinator 形成第二入口。
- [ ] Call、SMS、第三方 App 通知及仪表动作仍需真实配对 XP400、锁屏/专注模式和不同通知设置下逐项验证；单元测试不替代实车结论。
- [ ] 系统 ANCS 是否显示某个具体第三方 App 的内容由 iOS、App 通知权限、Focus、锁屏预览和仪表固件决定，PTSpeed 不把本地测试结果升级为硬件兼容性结论。

### P3 验证结果

- `swiftc -parse`：Coordinator、Provider、设置页、开发者入口和 P3 测试通过。
- `Localizable.xcstrings`：JSON 解析通过。
- `git diff --check`：通过。
- 无签名 iOS `build-for-testing`：通过，P3 源码与测试 Bundle 均被编译。
- 构建仍出现既有第三方静态库对象文件警告，但没有 P3 编译错误。
- XCTest 实际执行、真实电话/短信/第三方通知和 XP400 真机验证：本轮未执行。

---

# 66. 第五阶段：P4 OBD Architecture

- [ ] `PTOBDTransport`
- [ ] BLE/Wi-Fi Transport
- [ ] `PTELM327Session`
- [ ] `PTOBDBusLease`
- [ ] Raw command classifier
- [ ] polling / monitor / diagnostics 排他
- [ ] 旧 API compatibility facade
- [ ] 移除大范围 `switch activeConnectionType`

---

# 67. 第六阶段：P5 Research Tooling

- [ ] BLE Fingerprint Scanner
- [ ] CAN Diff Engine
- [ ] CAN Correlation Engine
- [ ] Event Marker UI
- [ ] XP400 TEP2020 capture templates
- [ ] Evidence Browser
- [ ] Evidence confidence
- [ ] ECU Identification read-only probe

---

# 68. 第七阶段：P6 TEP2020 / FACOMSA Research

仅研究：

```text
ECU list
Dashboard identification
Connectivity Box identification
HW version
SW version
Boot version
Electronic reference
Update available metadata
```

目标首先是：

```text
知道它是谁
```

不是：

```text
立刻刷它
```

---

# 69. 第八阶段：P7 Firmware Resource Research

只有真正拿到：

```text
合法 firmware/package/dump
```

后开始：

- [ ] SHA256
- [ ] Container detection
- [ ] Partition scan
- [ ] Graphics scan
- [ ] Pulsion vs XP400 diff
- [ ] Lion resource identification
- [ ] checksum/signature analysis

### 此阶段仍然不包含

```text
真实车辆写入
```

---

# 70. 推荐 GitHub Issue / Milestone

## Milestone: XP400 BLE Core 2.0

Issues：

```text
#1 Split PTBluetoothManager
#2 Introduce BLE session state machine
#3 Add phase watchdogs
#4 Introduce TIO send queue
#5 Move Auth into dedicated module
#6 Move telemetry decoder
#7 CoreBluetooth state restoration
#8 ANCS separation
```

## Milestone: XP400 OBD Research 2.0

```text
#9 Introduce PTOBDTransport
#10 Introduce ELM327 session state
#11 Add bus lease
#12 Add command risk classifier
#13 CAN diff engine
#14 CAN event correlation
#15 Evidence confidence system
```

## Milestone: XP400 FACOMSA Research

```text
#16 TEP2020 capture workflow
#17 Dashboard ECU identification
#18 Connectivity Box ECU identification
#19 BLE DFU fingerprint scanner
#20 Firmware container inspector
```

---

# 71. 推荐优先级

| 优先级 | 项目 | 原因 |
|---|---|---|
| P0 | Protocol Fixtures | 防止重构破坏已工作的协议 |
| P0 | Manager 拆分 | 当前技术债最大 |
| P0 | BLE State Machine | 提升稳定性 |
| P0 | Timeout | 防死锁/假连接 |
| P1 | State Restoration | iOS BLE 可靠性 |
| P1 | OBD Bus Lease | 防止 polling/sniffer/diagnostic 冲突 |
| P1 | Command Classifier | 限制 raw injection |
| P1 | ANCS 解耦 | 避免干扰核心连接 |
| P2 | CAN Diff | 直接服务 TEP2020 研究 |
| P2 | BLE Fingerprint | 直接服务 Box/DFU 研究 |
| P2 | Evidence Upgrade | 防止猜测变成“事实” |
| P3 | Firmware Inspector | 拿到 firmware 后再做 |
| 暂缓 | ECU Write | 当前证据不够 |
| 暂缓 | DFU Flash | 当前硬件未确认 |

---

# 72. CrazyDashboard 目标架构

```text
┌─────────────────────────────────────────┐
│                 UI                      │
│ Dashboard / Navigation / OBD / DevTools │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│          Vehicle Application Layer      │
│                                         │
│ Telemetry Snapshot                      │
│ Navigation Coordinator                  │
│ Connection Status                       │
│ Research Status                         │
└──────────────┬───────────────┬──────────┘
               │               │
       ┌───────▼───────┐ ┌────▼─────────┐
       │ XP400 BLE     │ │ OBD / CAN    │
       │               │ │              │
       │ Peripheral    │ │ Transport    │
       │ TIO           │ │ ELM327       │
       │ Credits       │ │ Polling      │
       │ Auth          │ │ CAN Capture  │
       │ Frames        │ │ UDS Read     │
       └───────┬───────┘ └────┬─────────┘
               │               │
               └───────┬───────┘
                       │
            ┌──────────▼──────────┐
            │ Research / Evidence │
            │                     │
            │ BLE Fingerprint     │
            │ CAN Diff            │
            │ TEP2020             │
            │ ECU Identification  │
            │ Firmware Inspector  │
            └─────────────────────┘
```

---

# 73. 最终原则

以后 CrazyDashboard 增加任何 XP400 功能，都先问三个问题：

### 1. 这是哪个协议层？

```text
BLE
TIO
Peugeot/FACOMSA Application
CAN
UDS
Firmware
```

不要跨层直接互相调用。

### 2. 证据是什么？

```text
Official APK
Official Document
Repeatable Capture
Single Capture
Inference
Guess
```

代码必须能知道证据等级。

### 3. 这个操作会不会改变车辆状态？

```text
Passive
Read Only
State Changing
Write
Programming
```

不同风险等级必须走不同入口。

---

# 74. 我建议你实际执行的顺序

如果现在开始正式改：

```text
第一步
Protocol Fixture + Unit Tests

第二步
拆 PTBluetoothManager

第三步
BLE State Machine + Timeout

第四步
TIO SendQueue / Credits 独立

第五步
Telemetry Decoder / Navigation 独立

第六步
ANCS 解耦

第七步
拆 PTHiddenOBDConnector

第八步
Bus Lease + Command Classifier

第九步
CAN Diff / Correlation

第十步
TEP2020 read-only research
```

做到第十步之后，再决定是否进入：

```text
Firmware resource
Bootloader
Dashboard Logo
```

研究。

---

# 75. 最终阶段目标

完成本路线后，CrazyDashboard 应达到：

## 正式用户功能

```text
稳定 XP400 BLE reconnect
稳定 navigation
稳定 telemetry
稳定 ANCS
稳定 OBD telemetry
```

## 工程质量

```text
Manager 不再千行级
协议层可单测
BLE/OBD 彻底分层
Swift 6 concurrency 边界明确
无 stale session
无 queue deadlock
```

## 研究能力

```text
BLE passive fingerprint
CAN high quality capture
CAN diff
TEP correlation
read-only ECU identification
protocol evidence database
firmware static inspection
```

## 风险边界

```text
普通版本不执行未知写操作
Developer 功能有 policy gate
Firmware flashing 不与日常代码耦合
所有猜测都有 evidence level
```

---

# 76. 一句话总结

CrazyDashboard 下一阶段最重要的不是继续增加更多“能发什么指令”的函数，而是把现有已经成功逆向的 XP400 能力整理成：

```text
稳定的 BLE/TIO Core
+
可验证的 Peugeot/FACOMSA Protocol
+
解耦的 OBD/CAN Diagnostic Stack
+
Evidence-driven Research Tooling
```

这样以后无论 FACOMSA 回邮件、拿到 TEP2020 抓包、找到 `1140254700` 固件、还是发现新的 Connectivity Box firmware，都可以作为独立证据接进来，而不需要再次推翻整个 CrazyDashboard 架构。

---

# Appendix A - 当前关键文件评估

## `Global/BLE/PTBluetoothManager.swift`

状态：

```text
功能成熟
职责过多
必须拆分
```

保留其 Facade 身份。

---

## `PTXP400BLEInboundReassembler.swift`

状态：

```text
方向正确
保留
增加 fuzz/metrics
```

---

## `PTXP400BLEProtocolContract.swift`

状态：

```text
方向正确
继续成为协议常量唯一来源
```

---

## `PTDashboardANCSProvider.swift`

状态：

```text
保留为 Experimental
不要成为正式 TIO 连接依赖
```

---

## `PTCANRecorder.swift`

状态：

```text
基础较完善
不重写
增加分析层
```

---

## `PTHiddenOBDConnector.swift`

状态：

```text
功能很多
文件过大
Transport/ELM/Monitor/Raw Injection 职责混合
必须拆
```

---

## `PTDashboardHacker.swift`

状态：

```text
研究框架已形成
命名不再合适
建议改为 PTXP400DashboardResearchService
保持写入关闭
```

---

## `PTUDSDiagnosticService.swift`

状态：

```text
Read-first 路线正确
继续保持
不要急着加入 programming services
```

---

## `PTXP400InstructionEvidenceStore.swift`

状态：

```text
非常值得继续投入
加入 source/confidence/capture/event 关联
```

---

# Appendix B - 官方 APK 对齐重点

当前已经确认并应长期保留为兼容基线：

```text
TIO FEFB
4 TIO characteristics
20 byte compatible chunk
25 Credits
4 low threshold
Peugeot/FACOMSA authentication
Phone = Peripheral
Connectivity Box = Central
Navigation frame
Configuration frame
ANCS integration
```

当前 APK 没有证据支持：

```text
Phone-side Connectivity Box firmware flashing
Nordic DFU
BlueMod DFU command
firmware package download
```

因此这些不能进入正式模块。

---

# Appendix C - 研究 Backlog

后续资料到手后继续：

- [ ] FACOMSA 回复
- [ ] XP400 Connectivity Box 标签
- [ ] XP400 TFT 标签
- [ ] `1140254700` FACOMSA internal ref
- [ ] `1179305800` FACOMSA internal ref
- [ ] TEP2020 XP400 ECU list
- [ ] Dashboard Identification
- [ ] Connectivity Box Identification
- [ ] SW/HW/Boot Version
- [ ] Dealer update CAN capture
- [ ] BLE during dealer update
- [ ] Pulsion firmware/reference
- [ ] Metropolis firmware/reference
- [ ] XP400 firmware/reference
- [ ] Pulsion classic Lion resource
- [ ] XP400 shield Lion resource

---

> 建议：从 **P0 Protocol Fixture → P1 BLE Core Refactor** 开始，不要先写新的破解功能。

---

# P0 实施记录（2026-09-09）

本次按“先冻结行为、再进入拆分”的原则完成了 P0 中不需要改动稳定传输核心的部分：

- [x] Auth Fixture：覆盖 Key/Configuration 长度、两种 20 字节 Challenge、连接身份帧和确定性响应前缀。
- [x] TIO Credits Fixture：覆盖最大合法增量 `0x19`、会话上限和溢出边界入口。
- [x] Navigation Frame Fixture：覆盖导航包络、长度字段、大端距离和道路文本。
- [x] Data1/2/3 Fixture：覆盖三类已确认的 11 字节车辆数据帧。
- [x] ABS Fixture：覆盖 ABS 11 字节车辆数据帧。
- [x] Reassembler Unit Tests：覆盖合并写入、分片写入、严格长度、非法帧边界和认证阶段顺序。
- [x] BLE lifecycle compatibility projection：在 `PTVehicleConnectivityCoordinator` 中加入显式状态归约器，并保持旧连接状态和公开调用兼容。
- [x] Central-subscription watchdog：统一取消、超时失败和断开清理路径，保留原有 15 秒连接失败语义。
- [x] Passive BLE trace capture：连接开始阶段即建立结构化会话，并在既有会话上限内保存每一个解析后的 BLE 帧。
- [x] PTSpeed 无签名 Debug 构建：主 App、Widget 和 Watch 相关 target 已通过 `generic/platform=iOS` 构建。
- [x] P0 测试目标编译：`build-for-testing` 已通过，新增 Fixture 和回归测试已被测试 target 编译。
- [ ] 记录一个当前可成功连接 XP400 的完整 BLE Trace：需要使用真实配对的 XP400 实车完成一次连接并导出文件，代码已准备好自动采集。
- [ ] 记录一份正常 CAN baseline：需要使用真实 ELM327/车辆完成一次 `ATMA` 基线抓包，不能用模拟数据代替实车证据。

## P0 核心落地补强（2026-09-11）

本次根据“暂时解除 `PTBluetoothManager` 冻结”的授权，把稳定管理器接入 P0 证据边界；没有重写认证、Credits、分片队列、重组器或 Data1/2/3/ABS 解码：

- [x] `PTBluetoothServerManager` 上报真实 CoreBluetooth 事实事件：蓝牙可用性、服务配置、广播、Central 订阅、认证开始/成功和断开。
- [x] `PTVehicleConnectivityCoordinator` 消费上述事实事件，并继续作为唯一的 `PTXP400BLELifecycleMachine` 状态归约入口，避免在 BLE Manager 内复制第二套生命周期状态机。
- [x] GATT UUID、帧头/帧尾、已知帧 ID 和 20 字节 TIO 分片上限统一引用 `PTXP400BLEProtocolContract`，新增回归测试防止协议常量漂移。
- [x] 使用 `CrazyDashboard.xcworkspace` 完成无签名 Debug 主 App、Widget、Watch App 构建。
- [x] 使用同一工作区完成 P0 测试 bundle 的 `build-for-testing` 编译检查。

本次仍未把硬件证据标记为完成：

- [ ] 完整 XP400 BLE Trace：必须在真实配对仪表盘上完成一次从广播、订阅、四阶段认证到 Data1/2/3/ABS 回传的连接，并导出被动证据文件。
- [ ] 正常 CAN baseline：必须使用真实 ELM327 与车辆完成一次 `ATMA`，记录协议、过滤器、帧频率和结束恢复结果。

## P0 边界与延期项

`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 继续保持未修改。`PTBluetoothManager.swift` 本次只增加事实事件上报，并把既有 GATT/帧常量绑定到已测试协议契约；认证、Credits、分片、队列、重组器和解码逻辑仍保持原实现，也没有复制第二套传输实现。

完整的 `PTBluetoothManager` 文件搬迁（Facade、Session、Authenticator、Credits、SendQueue、Parser、NavigationScheduler）留到后续阶段，在完成真实 BLE Trace 对照和回归后再进行，避免在没有实车证据时改变核心行为。

> 状态更新（2026-09-11）：上述延期项已在 P1 续记中以行为等价方式完成；真实 BLE Trace 和实车回归仍保持未完成，不能替代为硬件验收。

本次新增的独立回归入口：

- `Global/BLE/PTXP400BLELifecycle.swift`
- `Global/BLE/PTXP400BLEPhaseWatchdog.swift`
- `PTSpeedTests/PTXP400BLEP0Fixtures.swift`
- `PTSpeedTests/PTXP400BLEP0Tests.swift`

工程级验证已完成，但当前命令使用的是通用 iOS 构建目的地，因此只证明源码和测试 bundle 可编译；尚未替代 XCTest 实际执行、真实 XP400 BLE 连接或实车 CAN 验收。

本机虽有 iOS 27 模拟器，但当前 `PTSpeed` Scheme 没有提供与该模拟器匹配的可运行目的地，实际 XCTest 因 destination 不匹配而未执行；这不影响 `build-for-testing` 的编译结论。

---

# P1 实施记录（2026-09-09）

本阶段按“先建立外围协调边界、绝不复制稳定核心协议逻辑”的原则完成了可安全落地的 P1 项目。以下状态以当前仓库代码和最新 `build-for-testing` 结果为准。

## 已完成

- [x] 新增 `PTOBDBusLease` actor：FIFO 排队、任务取消、等待超时、连接代次和失效令牌检查。
- [x] 新增 `PTOBDCompatibilityGateway`：在不触碰稳定 OBD transport 的前提下，为高级诊断和裸指令建立统一的应用侧协调入口。
- [x] `PTAdvancedOBDCoordinator` 接入共享租约：普通 DID 读取使用 `diagnosticRead`，开发者探测使用 `developerWrite`，并保持旧诊断 API 兼容。
- [x] 普通 UDS 读取增加已确认 DID 白名单；未确认 DID、内存读取和节点扫描必须经过开发者门禁。
- [x] 新增 `PTOBDCommandClassifier`：区分 passive、readOnly、stateChanging、write、programming 和 unknown；`04`、`08`、`10`、`11`、`27`、`31`、`3E` 等不再误当成普通读取。
- [x] 裸 OBD 指令增加空值、十六进制格式和最大长度检查；写入、刷写、未知指令默认拒绝，只有明确的开发者操作上下文可以继续。
- [x] `PTCANExperimentCoordinator` 接入 `sniffer` 租约；抓包准备、录制、停止、适配器恢复和轮询恢复保持在同一协调流程内。适配器清理先于轮询恢复，失败路径也会释放租约。
- [x] CAN 抓包的 `ATMA` 被限制在开发者抓包操作上下文；恢复指令使用独立的安全恢复上下文。
- [x] 断开 OBD、连接超时和连接状态变为非 connected 时使 OBD 租约代次失效，排队诊断不会跨连接继续执行。
- [x] 新增 `PTXP400ANCSCoordinator`：系统通知路径和实验兼容 Provider 分开；正常连接流程不会自动安装自有 ANCS Provider，设置页测试仍保持兼容。
- [x] 新增 `PTXP400P1Tests`：覆盖租约串行化、取消、超时、断开失效、风险分类和普通读取白名单。
- [x] P1 新文件已加入 `PTSpeed` 主 App 和 `PTSpeedTests` 测试 target；最新无签名 iOS `build-for-testing` 通过。

## 明确延期与边界

> 历史状态说明：以下延期项是 2026-09-09 冻结核心时的记录；2026-09-11 的当前完成状态以本文末尾的 P1 BLE Core Refactor 续记为准。

- [ ] CoreBluetooth State Restoration 尚未接入 `PTBluetoothManager.swift`。当前稳定核心没有 restoration identifier 和 `willRestoreState` 入口；在冻结核心不可修改的约束下，本阶段只能完成生命周期模型和 watchdog，不能宣称已经实现系统级进程恢复。
- [ ] `PTBluetoothManager` 按 Session、Authenticator、Credits、SendQueue、Parser、NavigationScheduler 拆分延期。该拆分必须先有真实 XP400 BLE Trace，并完成行为等价回归后再做。
- [ ] 尚不能宣称实现了物理层面的“全局 OBD 互斥”。稳定 OBD manager 内部的 polling、heartbeat、`fetchProprietaryData`、部分 raw API 和 `ATMA` 流式写入仍没有可传递租约令牌的核心接口；当前租约是应用侧兼容协调边界，不是对冻结 transport 的强制硬锁。
- [ ] 将所有历史的 `injectRawHexCommand`、heartbeat、DTC、Mode 8、proprietary data 和 sniffer 入口完全迁移到风险网关，延期到允许增加稳定核心 drain/ownership hook 后处理，避免复制第二套响应和轮询引擎。
- [ ] 官方 advertising manufacturer data 与 Android 行为对齐仍需 Android 抓包证据；当前不猜测字段、不写入生产逻辑。
- [ ] 真实 XP400、真实 ELM327 CAN baseline、ANCS 实车结果和 XCTest 实际执行仍待设备条件。当前机器的 iOS 27 模拟器与 `PTSpeed` scheme 不兼容，因此本轮只完成源码解析和测试 bundle 编译，没有把它们表述为运行时验收。

## 稳定核心保护（2026-09-09 历史记录）

以下内容记录的是 2026-09-09 当时仍处于冻结状态的边界；2026-09-11 用户明确解除 `PTBluetoothManager.swift` 冻结后，当前状态以本文末尾的 P1 续记为准。本阶段仍然没有修改两个稳定 OBD 核心文件：

- `Global/OBD/Function/PTHiddenOBDConnector.swift`
- `Global/OBD/Function/PTOBDCommand.swift`

它们继续作为 ELM327、分片、轮询和标准 PID 的稳定底层；当时的 P1 新增代码只通过既有公开能力和外围兼容门面接入。

## 本轮验证

- `xcrun swiftc -parse`：通过。
- `git diff --check`：通过。
- 冻结核心文件差异检查：通过，结果为空。
- 无签名 iOS `build-for-testing`：通过，主 App 和 `PTSpeedTests` 均编译了 P1 新文件。
- 实际 XCTest：未执行；当前 `PTSpeed` scheme 没有与本机 iOS 27 模拟器匹配的可运行目的地。
- 构建仍有既有 Xcode Beta、Pods 和第三方静态库警告；本阶段未将其误判为 P1 源码错误。

---

## P1 BLE Core Refactor 续（2026-09-11，解除 `PTBluetoothManager` 冻结）

本轮按用户明确授权，允许修改 `Global/BLE/PTBluetoothManager.swift`，但仍保持两个稳定 OBD 核心文件不变。重构采用行为等价的兼容门面：`PTBluetoothServerManager` 的单例、旧方法、代理协议和既有协议帧行为保持不变；新组件只承接状态、会话、认证适配、Credits 计数、发送队列、帧包络校验和导航节流职责，没有新增第二套 BLE 传输或认证算法。

### P1 已完成

- [x] `PTXP400BLESession`：为真实 Central 和 Mock 连接分配连接代次与 Token；断开后旧回调不能复用会话。
- [x] `PTXP400BLEState`：集中保存认证、订阅和 Credits 状态；会话重置统一清空，避免跨车或跨连接残留。
- [x] `PTXP400Authenticator`：仅适配现有 `PTScooterAuth`，认证算法和报文顺序继续以既有实现为唯一来源。
- [x] `PTXP400TIOCreditController`：复用已确认的 Credits 校验边界，限制余额范围，并接入入站消费、远端 Credits 接收和本地补充。
- [x] `PTXP400TIOSendQueue`：保留普通、导航两类任务顺序，并接入原有 `updateValue` 背压和回调路径。
- [x] `PTXP400TelemetryDecoder`：只负责 `[preamble, id, payload, terminator]` 包络验证和帧分类；Data1/2/3、CONTROL、ABS 的语义解码继续使用原有逻辑。
- [x] `PTXP400NavigationScheduler`：复用原有导航 Fingerprint、500ms 最小间隔和重复过滤规则，不改变导航帧编码。
- [x] 兼容门面：`PTBluetoothManager.swift` 只保留 `PTBluetoothServerManager` 状态和旧入口，实际职责拆到 `PTBluetoothServerManager+*.swift`；门面当前 217 行，满足 `<600` 行完成条件。
- [x] 工程引用：新增 BLE 模型与 Manager 扩展已加入 `PTSpeed` target，未加入 Widget、Watch 或 OBD target，避免无关模块引入 CoreBluetooth 传输代码。
- [x] public API 兼容：既有 `PTBluetoothServerManager.shared`、数据读取、代理回调、导航、配置、Mock 和开发者探针入口保留。

### P2 State Restoration 在本轮完成接入

- [x] `CBPeripheralManagerOptionRestoreIdentifierKey` 使用固定标识 `com.yd.PTSpeed.xp400.dashboard.peripheral`。
- [x] 实现 `peripheralManager(_:willRestoreState:)`，恢复 FEFB Service 及 TX/Credits 特征后才进入 ready。
- [x] 恢复路径只恢复 GATT 基础设施和用户曾明确开启的广播意图，不恢复认证、Credits、Central 身份、排队数据或导航 Pending 状态。
- [x] 恢复的 Service 缺少必要特征时保持未配置状态并记录可靠性事件，避免后续 IUO 特征访问导致崩溃。
- [x] 恢复后仍需重新走既有认证流程；系统没有恢复服务或蓝牙未开启时安全等待正常初始化。

### 当前仍未宣称完成的硬件验收

- [ ] 真实 XP400 上的系统进程回收/重启恢复。
- [ ] 真实 XP400 完整 BLE Trace 对照。
- [ ] 真实 ELM327 CAN baseline。
- [ ] 兼容设备上的 XCTest 实际执行。

### 本轮验证

- `ruby xcodeproj` 工程解析：通过。
- `xcrun swiftc -parse`：拆分后的 Manager、扩展和 P1 组件通过。
- `git diff --check`：通过。
- 无签名 iOS Debug 主 App 构建：通过；构建覆盖 PTSpeed、Widget、Watch App 及测试相关依赖。
- 实际 XCTest、真实 Apple 设备和 XP400 实车验证：本轮未执行，不能用源码构建结果替代。
- 冻结保护检查：`Global/OBD/Function/PTHiddenOBDConnector.swift` 与 `Global/OBD/Function/PTOBDCommand.swift` 无差异。
