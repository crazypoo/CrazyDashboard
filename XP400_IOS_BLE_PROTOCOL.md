# Peugeot XP400 iOS BLE 通信协议与实现规范

> 文档版本：1.5
>
> 审计日期：2026-09-04
>
> iOS 代码基线：`5c88228`
> 文档定位：项目内部实现规范 / 真车抓包校验依据
> 1.1 更新记录：补充 iOS 运行时边界、证据分层、导航实际链路和 BLE-OPT 优化清单；完成 BLE-OPT-001 上行分片重组实现与纯逻辑验证
> 1.2 更新记录：完成 BLE-OPT-005 服务生命周期编排；服务添加成功后才开始广播，支持重复启动、显式停止、蓝牙状态恢复及前后台幂等校正
> 1.3 更新记录：完成 BLE-OPT-002/003/004/006/007；补齐 Credits 与会话清理、严格认证帧校验、导航最新状态合并，以及 Data1～Data3/Control/ABS 的不可用值状态
> 1.4 更新记录：完成 BLE-OPT-008；Data2 和 ABS Mock 统一为 11-byte 车辆状态帧，并对已知入站帧补齐严格长度校验
> 1.5 更新记录：记录 PTSpeed-only 真车场景下真实来电和短信可通过系统 ANCS 显示；区分 iPhone 本地测试通知与仪表验证，保留第三方通知和跨条件矩阵待验证
> 1.6 更新记录：新增 `PTDashboardANCSProvider`，通过现有 `CBPeripheralManager` 提供 App 自有的 ANCS 风格测试通道；设置页增加固定英文直连测试入口。该通道不读取、不伪造系统电话或短信通知，真实 XP400 的服务接受、订阅和显示仍需真机验证

## 1. 文档边界

本文档根据项目当前 iOS BLE 实现整理而成。最终以当前仓库代码、真车抓包和实际车辆行为为准。

认证查找表仍由现有实现内部使用，协议文档只记录它的输入、输出和验证边界。

可信度使用以下标记：

| 标记 | 含义 |
|---|---|
| **已确认并实现** | 当前代码已有明确实现，且与研究文档的核心格式一致 |
| **已实现但属推断** | 当前代码可以工作，但字段含义或车辆兼容性尚未由真车抓包完全确认 |
| **尚未实现 / 待验证** | 当前只有模型、日志、模拟或构造器，不能作为已交付能力 |

“已确认并实现”只表示“研究文档与当前代码能够对上”，不表示已经通过真实 XP400 车辆验证。真车验证必须另外记录车辆型号、仪表固件、iOS 版本、原始 Hex 和 UI 结果。

本次审计继续沿用 1.1 版新增的四类审计维度：

| 维度 | 判断依据 | 当前文档规则 |
|---|---|---|
| iOS 实现 | `PTBluetoothServerManager`、`PTFrameBuilder` 和协议契约 | 说明当前代码实际做了什么 |
| 自动化测试 | `PTSpeedTests/PTCoreTests.swift` 中的 BLE 契约测试 | 说明可重复验证的纯数据行为 |
| 真车验证 | 抓包、仪表显示和多版本车辆记录 | 没有记录时保持“待验证” |

当前审计结论：GATT、Credits、认证主流程、导航封装、配置封装以及 Data1～Data3 的核心换算没有重大方向性差异；已补齐已知车辆状态帧的长度校验和严格 Mock 样本，并新增可失败即安全退出的 ANCS 风格测试通道。真车已确认系统通知链路在 PTSpeed 单独连接场景下可显示真实来电和短信；TCS、灯光、ABS 前轮速度、部分保留位和断开帧 ID 也已有真车抓包证据，协议字段与代码实现仍需分开记录。

### 1.1 审计来源和快照

| 来源 | 快照信息 | 用途 |
|---|---|---|
| 参考 APK | `Peugeot+Motocycles_2.1.37_APKPure.xapk`，versionCode `104` | 仅作为研究来源，不代表 iOS 包或 Peugeot 官方规范 |
| iOS 代码 | Git 提交 `5c88228` | 本文当前实现事实的基线 |
| BLE 核心快照 | `PTBluetoothManager.swift` SHA-256：`27bc0720e0ba9ed42c497b340fecff02dde2c6966d0aad38d7989887c763f448` | 记录包含 BLE-OPT-002/003/004/005/006/007/008 的当前工作树快照 |
| 协议契约快照 | `PTXP400BLEProtocolContract.swift` SHA-256：`69a7c77857c06eaa8c796dc495908b206afc4b3a2b2c79e8493f667a78aad9dd` | 固定 Credits 与认证纯数据校验器版本 |

如果任一代码快照发生变化，应重新核对本文档，而不是只修改版本号。

## 2. iOS 端系统角色

### 2.1 连接角色

XP400 的 Connectivity Box 是 BLE Central / GATT Client，iPhone 是 BLE Peripheral / GATT Server。

因此 iOS 端的实际职责是：

1. 使用 `CBPeripheralManager` 创建 TIO GATT 服务。
2. 广播 FEFB 服务 UUID，让仪表主动发现并连接手机。
3. 等待 XP400 订阅 UART TX 和 UART TX Credits。
4. 处理仪表写入的认证、Credits 和车辆状态数据。
5. 认证完成后发送导航、配置和开发者测试帧。

核心入口位于：

- `Global/BLE/PTBluetoothManager.swift`
- `PTBluetoothServerManager`
- `PTFrameBuilder`
- `PTScooterAuth`
- `Global/BLE/PTXP400BLEProtocolContract.swift`

### 2.2 iOS 生命周期

`PTBluetoothServerManager` 使用 `CBPeripheralManager(delegate:queue: nil)` 创建基站，因此当前 CoreBluetooth 回调和状态机操作默认运行在主队列。现有稳定实现没有把整个 BLE 状态机声明为独立 actor，也不能把它当作任意线程都可安全调用的对象。

启动流程：

```text
startBaseStationAndScan() 保留“请求广播”意图
        ↓
CBPeripheralManager.state == .poweredOn
        ↓
创建 FEFB 服务和四个特征（configuring）
        ↓
peripheralManager(_:didAdd:error:) 成功
        ↓
仅广播 FEFB Service UUID（advertising）
        ↓
XP400 连接并订阅 TX / TX Credits
        ↓
进入私有认证
        ↓
认证完成后开放业务帧
```

当前广告只包含服务 UUID，不主动广播本地设备名称。蓝牙未处于 `.poweredOn` 时不会启动广播；启动请求会保留，待蓝牙恢复后继续配置服务。

断开订阅后，代码会清除认证状态、订阅标志、连接身份、日志状态、发送队列、会话 Credits、发送阻塞状态、活跃通知和待发送导航，并通知业务代理连接已经结束。新 Central 到来时先执行同一套清理，再建立新会话。

`startBaseStationAndScan()` 的名称沿用了历史命名；当前实现只启动 iOS Peripheral 广播，不执行 BLE Central 扫描。服务生命周期单独记录为：`unavailable`（蓝牙不可用）、`idle`（未请求广播）、`configuring`（等待 `didAdd`）、`ready`（服务已添加但未广播）和 `advertising`（已请求/正在广播）。订阅和认证仍然是后续独立阶段，不能用 `advertising` 或 `blueConnected` 代替。

`startBaseStationAndScan()` 是幂等操作：广播已经存在、服务正在添加或服务已经就绪时不会重复添加服务。`stopAdvertising()` 只停止广播并保留已添加服务，不强制断开已经订阅的仪表；下一次启动会复用服务。CoreBluetooth 没有独立的“广播成功”代理回调，因此 `advertising` 以 `startAdvertising` 请求和 `isAdvertising` 状态观察共同判断。

状态转换规则：

| 触发 | 处理 | 结果 |
|---|---|---|
| `startBaseStationAndScan()` | 记录广播意图，按当前蓝牙状态继续 | `.configuring` / `.ready` / `.advertising`，不可用时 `.unavailable` |
| `didAdd service` 成功 | 仅在 FEFB 服务注册完成后启动广告 | `.ready` → `.advertising` |
| `didAdd service` 失败 | 记录错误，不启动广告 | 回到 `.idle` |
| 蓝牙关闭、未授权、重置或不支持 | 停止广告、废弃服务注册状态、清理会话认证 | `.unavailable`；保留启动意图 |
| 蓝牙重新 `.poweredOn` | 重新添加服务并在 `didAdd` 成功后广播 | `.configuring` → `.advertising` |
| App 回前台 | 调用幂等校正，补起被系统停止的广告 | 不重复添加服务或广播 |

## 2.3 iOS 后台与系统配置边界

当前 `PTSpeed/Info.plist` 声明了以下后台模式：

```text
bluetooth-peripheral
bluetooth-central
location
audio
```

这只能证明工程声明了相应后台能力，不代表 XP400 连接在进程被系统挂起、终止或重新启动后可以自动恢复。当前 `PTBluetoothServerManager` 仍没有实现 CoreBluetooth State Restoration 或 `willRestoreState`；但服务添加已经通过 `didAdd service` 串行化，前台恢复会通过生命周期校正重新检查服务和广播。

当前启动顺序是 `setupServices()` 调用 `peripheralManager.add(service)`，等待 `didAdd service` 成功后才调用 `startAdvertising(...)`；管理器提供幂等的 `stopAdvertising()` 生命周期入口。进入后台不主动停止已请求的广播，因为工程声明了 `bluetooth-peripheral`；回到前台会再次校正。进程被系统终止后的自动恢复仍不在本次范围内。

`PTVehicleConnectivityCoordinator` 另外有 15 秒的仪表连接 watchdog。它属于应用层连接尝试超时，不等同于研究文档中的 30 秒 GATT 超时或 6 秒 MTU 等待超时；watchdog 失败时仍应单独检查 Peripheral 广播、服务状态、发送队列和认证状态是否已经清理。

## 3. TIO GATT 服务

### 3.1 服务和特征

服务 UUID 和四个特征 UUID 与研究文档一致：

| 名称 | UUID | iOS 属性 | iOS 权限 | 数据方向（站在 iPhone Server 角度） | 状态 |
|---|---|---|---|---|---|
| TIO UART Service | `FEFB` | Primary | — | iPhone 与仪表的 UART 通道 | **已确认并实现** |
| UART RX | `00000001-0000-1000-8000-008025000000` | Write Without Response | Write Encryption Required | 仪表 → iPhone | **已确认并实现** |
| UART TX | `00000002-0000-1000-8000-008025000000` | Notify | Read Encryption Required | iPhone → 仪表 | **已确认并实现** |
| UART RX Credits | `00000003-0000-1000-8000-008025000000` | Write | Write Encryption Required | 仪表授予 iPhone 发送额度 | **已确认并实现** |
| UART TX Credits | `00000004-0000-1000-8000-008025000000` | Indicate | Read Encryption Required | iPhone 授予仪表发送额度 | **已确认并实现** |

项目使用 `notifyEncryptionRequired` 和 `indicateEncryptionRequired`，并要求相应的读写权限使用加密链路。研究文档中的 CCC Descriptor 由 CoreBluetooth 的 Notify / Indicate 订阅机制管理，业务代码不直接拼装 CCC Descriptor。

### 3.2 发送前置条件

在两个条件同时满足前，不允许进入正常业务数据阶段：

- XP400 已订阅 UART TX；
- XP400 已订阅 UART TX Credits。

两个特征都订阅后，iOS 将认证状态重置为 `waitKeyId`，等待仪表写入产品 Key ID。仅建立 GATT 连接，或者只订阅一个特征，都不能视为业务连接成功。

## 4. Credits 流控和分片

### 4.1 两个方向的额度

由于 iPhone 是 GATT Server，`RX` 和 `TX` 的命名容易与常规客户端视角相反：

| 变量 / 通道 | 含义 |
|---|---|
| `sendCredits` / UART RX Credits | 仪表写入额度，允许 iPhone 通过 UART TX 发送分片 |
| `localCredits` / UART TX Credits | iPhone 发给仪表的额度，允许仪表通过 UART RX 发送分片 |

当前实现的固定参数：

| 参数 | 值 |
|---|---:|
| 研究文档中的最小 ATT MTU | `23` |
| 最大 Credits | `25` |
| 补充阈值 | `4` |
| 单个 TIO 分片最大长度 | `20 bytes` |

当前 iOS 发送器没有根据协商结果动态调整分片长度，而是固定使用 20 bytes；最小 MTU `23` 是研究文档提供的传输假设，不是当前 iOS 代码主动协商或验证出来的结果。

### 4.2 iPhone 发送

1. 仪表向 UART RX Credits 写入一个字节，增加 `sendCredits`。
2. iOS 将完整业务帧拆成连续的 20-byte 分片。
3. 每次成功调用 `updateValue(_:for:onSubscribedCentrals:)` 后消耗一个 `sendCredits`。
4. 没有额度时保留发送队列，等待新的额度。
5. CoreBluetooth 返回发送失败时等待 `peripheralManagerIsReady(toUpdateSubscribers:)` 再继续发送。

当前发送队列没有增加序列号、重传计数或应用层 ACK。是否存在仪表端额外重传机制，必须通过真车抓包确认。

### 4.3 仪表发送

认证完成后，iOS 通过 UART TX Credits 补充额度，初始最多授予 25 个。`localCredits` 降到 4 或更低时再次补足到 25。

### 4.4 当前实现的传输边界

`UART_RX` 的写入现在先经过 `PTXP400BLEInboundReassembler`，再交给认证状态机或状态解析器。重组器按照当前认证阶段识别边界，不使用一个通用的 Header + Length 规则混淆不同报文：

- 首轮 Key/Configuration：固定 15 bytes，前 4 bytes 必须是大端 `00 00 22 36`；
- 首轮认证响应：固定 20 bytes；
- 第二轮随机挑战：固定 20 bytes；
- 认证完成帧：严格 15 bytes，格式为 `0x16 0x01 + 12-byte hexadecimal identity + 0x00`；
- 认证后的车辆状态：严格 11 bytes，Frame ID 为 `0x02`～`0x06`；认证后重复出现的连接/心跳帧仍按严格 15 bytes 兼容解析。

因此，拆分写入会先缓存到完整长度，合并写入会在一次回调中连续排空多个逻辑帧；带 `0x16` 边界的连接帧和状态帧遇到非法数据后会寻找下一个帧头重新同步。认证响应和随机挑战在协议上没有帧头、长度字段或结束符，重组器只能按 20-byte 边界处理，这是该协议本身的恢复上限，不能据此推断丢失字节后的真实边界。重复的前一认证阶段帧会在进入下一阶段前丢弃，避免误推进认证状态机。

已完成的传输边界优化：

- `UART_RX_CREDITS` 只接受一个 `1...25` 的字节；空数据、额外字节、零值和超大值会被拒绝，不再读取越界；
- `sendCredits` 以 25 为会话上限，累加可能溢出上限时拒绝，合法请求逐个返回 ATT 结果；
- 断开订阅、蓝牙不可用和新 Central 到来时清空 `sendQueue`、`sendCredits`、`localCredits`、`isSending`、活跃通知和认证临时状态；
- 导航队列项单独标记，只有被替换的导航分片会被清理，认证、配置和控制任务不受影响；
- 仍然没有应用层 ACK、序号、CRC 或自动重传，发送完成只代表 CoreBluetooth 接受了该分片。

## 5. 私有双向认证

### 5.1 认证状态机

当前 iOS 状态机为：

```text
waitKeyId
    ↓ 收到产品 ID 8758
waitAuthMsg
    ↓ 前 10 bytes 响应校验成功
waitRandomNums
    ↓ 收到 20-byte 第二轮挑战并完成计算
waitConnectionFrame
    ↓ 收到严格 15-byte 连接帧（0x16 0x01 + 12-byte hexadecimal identity + 0x00）
success
```

具体交互：

| 步骤 | 仪表 → iPhone | iPhone → 仪表 | 当前状态 |
|---:|---|---|---|
| 1 | 严格 15-byte 车辆 Key/Configuration；前 4 bytes 必须是 Big-Endian Product ID `8758`，剩余字段按不透明字节保留 | 10 个随机 `UInt16`，共 20 bytes | **已实现，首包剩余字段不解释** |
| 2 | 严格 20-byte 第一轮响应；认证算法仍只比较协议确认的前 10 bytes | 15-byte iOS Key/Configuration | **已实现，包络严格** |
| 3 | 严格 20-byte、10 个 `UInt16` 的第二轮挑战；不会接受额外字节 | 20-byte 计算响应 | **已确认并实现** |
| 4 | 严格 15-byte Connection Frame：`0x16 0x01 + 12-byte hexadecimal identity + 0x00` | 开放状态数据和业务帧 | **已实现，长度、帧头、结束符和身份字符严格校验** |

认证成功后，代码设置 `authenticated = true`、保存车辆连接标志、授予仪表 Credits，并把第一包连接数据继续交给状态解析器。

### 5.2 Key ID 和身份数据

双方使用的产品标识是：

```text
0x00002236
```

在线上以四字节 Big-Endian 表示：

```text
00 00 22 36
```

当前 iOS 回复的 15-byte 数据结构为：

| 偏移 | 长度 | 当前内容 |
|---:|---:|---|
| 0 | 4 | 产品 ID `8758`，Big-Endian |
| 4 | 3 | 当前代码写入 `[2, 0, 8]` |
| 7 | 3 | 当前代码写入 `[1, 4, 25]` |
| 10 | 1 | 分隔字节 `1` |
| 11 | 4 | iOS 系统版本号分量，不足四段补 `0` |

代码中的旧注释与实际 `[2, 0, 8]` 内容不完全一致，本文档以实际写入字节为准。

### 5.3 查表响应

认证使用现有 `PTScooterAuth` 查表算法：

```text
for i = 0...4:
    left  = table[random[i]     & 0x07FF]
    right = table[random[i + 5] & 0x07FF]
    result = (left + right) & 0xFFFF
```

五个结果按 Big-Endian 写出 10 bytes，再追加 10 bytes 随机填充，形成 20-byte 响应。当前验证逻辑只比较仪表响应的前 10 bytes，并未把后 10 bytes 作为认证条件。

认证查找表属于实现内部数据，不在本文件复制，也不应在日志中打印。

### 5.4 与研究文档的差异

研究文档提到的 GATT 连接 30 秒和 MTU 等待 6 秒超时，在当前 iOS `PTBluetoothServerManager` 中没有对应的认证阶段定时器。当前文档不能把这两个时间写成 iOS 已实现行为。

## 6. 帧封装规则

### 6.1 iPhone → 仪表：可变长度业务帧

导航、配置和开发者发送帧使用：

```text
16 | Frame ID | Payload Length (2 bytes, BE) | Payload | 00
```

总长度必须满足：

```text
frame.count == payload.count + 5
```

当前 `PTXP400BLEProtocol.isValidOutboundFrame(_:)` 对包头、包尾、Big-Endian 长度和总长度进行校验。

### 6.2 仪表 → iPhone：固定状态帧

研究文档定义 Data1～ABS 状态帧为：

```text
16 | Frame ID | 固定 8-byte Payload | 00
```

总长度为 11 bytes，且没有两字节 Payload Length。连接身份帧单独使用：

```text
16 | 01 | 12-byte ASCII identity | 00
```

总长度为 15 bytes。

当前代码的 `parseDashboardFrame(_:)` 为兼容 Mock 和抓包数据，只检查最小长度、`0x16` 包头和 `0x00` 包尾，再按 Frame ID 检查各自的最小 Payload 长度。因此：

- 协议规范仍按严格 11-byte / 15-byte 结构记录；
- 当前运行时解析不能等同于严格长度验证；
- 真车数据校验或后续收紧解析器前，必须先覆盖现有 Mock 和历史抓包。

### 6.3 字节序、编码和校验速查

| 数据 | 当前 iOS 编码 | 备注 |
|---|---|---|
| 普通帧 Payload Length | Big-Endian | 仅存在于 iPhone → 仪表的业务帧 |
| 导航距离、车速、转速、里程 | Big-Endian | `UInt16`、`UInt24` 和 `UInt32` 按字段定义读取 |
| 认证 Challenge / Response | Big-Endian | 每个 `UInt16` 按两字节处理 |
| 连接身份 | ASCII | 研究格式为 12 个十六进制字符 |
| 道路名称 | ISO-8859-1 | 上层会先将中文路名转换为兼容拼音 |
| ANCS UID 和长度 | Little-Endian | 适用于 App 自有 ANCS 风格测试通道；不代表可注入系统通知 |
| 应用层 CRC / Checksum | 无 | 当前代码和研究文档都没有发现 |

这套协议存在方向不对称性：不能把固定 11-byte 车辆状态帧交给 iPhone → 仪表的长度帧解析器，也不能把带 Payload Length 的发送帧直接当成认证或车辆状态帧。

已存在的纯数据验证向量：

```text
配置（Blue / Metric / English）:
16 07 00 06 01 02 01 01 01 01 00

41-byte TIO 数据分片长度:
20, 20, 1

连接身份:
16 01 41 31 42 32 43 33 44 34 45 35 46 36 00
```

## 7. iPhone 发送导航帧

### 7.1 Payload 布局

Frame ID 为 `0x01`。当前 `PTFrameBuilder.buildNavigationFrame(info:)` 依次写入：

| 顺序 | 字段 | 编码 |
|---:|---|---|
| 1 | Maneuver | `[01, maneuver]` |
| 2 | 距下一动作距离 | `[04, UInt32 BE]` |
| 3 | 下一道路名 | `[长度, ISO-8859-1 bytes]` |
| 4 | 当前道路名 | `[长度, ISO-8859-1 bytes]` |
| 5 | 当前限速 | `[01, speed]` |
| 6 | 到目的地距离 | `[04, UInt32 BE]` |
| 7 | ETA | `[07, 年2 bytes BE, 月, 日, 时, 分, 秒]` |

道路名称先进行去重音处理，再使用 ISO-8859-1 编码；每个道路名称最多 50 bytes，无法编码时使用空数据。

### 7.2 距离和 ETA

- 距离下一动作的数值当前按 5 米向下取整。
- 到目的地距离当前直接使用传入的原值，没有同步按 5 米取整。
- ETA 使用当前设备的 `Calendar`，以当前时间加上剩余秒数计算本地日期时间。
- 这与研究文档中“两个距离都按 5 米处理”的描述存在一个实现差异，后续真车兼容调整前必须保留该记录。

### 7.3 动作码边界

当前协议契约允许的主要动作包括：

| 范围 / 值 | 含义 | 状态 |
|---|---|---|
| `0x01` | 直行 / 默认 | **已确认并实现** |
| `0x02`、`0x03` | 右 U 型、左 U 型 | **已确认并实现** |
| `0x05`～`0x0C` | 普通左右转、保持方向 | **已确认并实现** |
| `0x13`～`0x2A` | 环岛出口动作 | **已确认并实现** |
| `0x2B`、`0x2C` | 出发、到达 | **已确认并实现** |
| `0x2E`、`0x2F` | 回到路线、无有效动作 | **已确认并实现** |
| `0x04`、`0x09` | Keep Right / Keep Left | 枚举存在，但当前契约未纳入确认集合 |
| `0x2D`、`0x30`、`0x31` | 轮渡、重新算路、无 GPS | **已实现但属推断** |

未知动作码会由协议契约安全回退到 `0x01`，避免把未确认的值发送到真实仪表。

### 7.4 iOS 导航数据来源和动作映射

研究文档描述的是 HERE SDK 数据源；当前项目实际使用 `AMapNaviKit`。`PTMotoDashBoardNavFunction` 负责把 AMap 回调转换成 `PTNavigationInfo`，再交给稳定的 BLE 发送层。

当前主要映射如下：

| AMap 动作 | 当前 XP400 码 |
|---|---:|
| `none`、`default`、`straight`、到达途经点 | `0x01` |
| `left` | `0x0B` |
| `right` | `0x06` |
| `leftFront` | `0x0A` |
| `rightFront` | `0x05` |
| `leftBack` | `0x0C` |
| `rightBack` | `0x07` |
| 左掉头 / 右掉头 | `0x03` / `0x02` |
| 到达目的地 | `0x2C` |
| 进入环岛 | `0x13` |

道路文本实际经过两层处理：

```text
AMap 中文/带重音文本
        ↓
toMotorcycleCompatiblePinyin()
        ↓
PTFrameBuilder 去重音 + ISO-8859-1 + 50-byte 截断
        ↓
导航 Payload
```

当前 AMap 适配器没有根据环岛出口数生成 `0x13`～`0x2A` 的完整出口编码，进入环岛会使用 `0x13` 作为安全回退。自定义 Roadbook 可以直接提供已归一化的协议动作码。

### 7.5 导航发送时机的实际差异

研究文档建议在动作、距离、ETA 或路线状态明显变化时发送；当前标准导航界面仍会在每次 AMap `update naviInfo` 回调中调用 `sendNavDataToDashboard`，但 BLE 适配层现在统一按动作、道路、限速、10 米转向距离桶、50 米目的地距离桶和 30 秒 ETA 桶去重，并限制最短发送间隔为 0.5 秒。

自定义 Roadbook 则在位置和目标点状态变化时发送。标准导航结束路径目前使用默认 `sendWelcomeMessage` 动作 `DEPART` 显示结束文字，而自定义 Roadbook 的强制到达路径使用 `ARRIVE`；这两个行为需要在真车上确认并统一。

当 Credits 不足或 CoreBluetooth 暂时不可写时，适配层只保留最新待发送导航；新的导航只删除旧导航分片，不会删除配置、认证或控制任务。欢迎文字使用兼容路径发送，不被普通导航节流误吞。

## 8. 仪表配置帧

### 8.1 配置格式

Frame ID 为 `0x07`，Payload 为三个带长度字段的参数：

```text
01 | color | 01 | unit | 01 | language
```

当前发送枚举：

| 参数 | 值 |
|---|---|
| Color | Red `1`、Blue `2`、Gold `3` |
| Unit | Metric `1`、Imperial `2` |
| Language | English `1`、French `2`、German `3`、Spanish `4`、Italian `5` |

配置发送完成只能说明分片已交给 CoreBluetooth 发送队列。设置界面会继续等待 Data3 回传，并同时匹配颜色、单位和语言；三项全部一致才显示“设置成功”，5 秒内没有回传则显示“未收到仪表确认”。这是应用层回读确认，不是协议定义的 BLE ACK。

注意：发送配置时的颜色值与 Data3 回传的颜色 bitfield 不同，不能直接复用。

当前单元测试锁定的配置向量为：

```text
PTFrameBuilder.buildConfigurationFrame(color: 2, unit: 1, language: 1)
→ 16 07 00 06 01 02 01 01 01 01 00
```

这个向量只验证 iOS 封包和长度字段，不能证明真实仪表已经接受配置。真实成功必须以 Data3 回传的颜色、单位和语言全部匹配为准。

## 9. 仪表回传状态帧

### 9.1 Data1：油量和里程

Frame ID：`0x02`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 当前换算 |
|---:|---:|---|---|
| 0 | 1 | Fuel Level | `round(raw × 0.3937)`，并限制在 0～100 |
| 1 | 1 | Reserved / 隐藏位 | 当前只记录调试信息 |
| 2 | 1 | Average Consumption | `raw × 0.1 L/100km` |
| 3 | 2 | Trip | `UInt16 BE × 0.1 km` |
| 5 | 3 | Odometer | `UInt24 BE × 0.1 km` |

`0xFF` 代表字段不可用时，代码保留完整 `rawPayload`，并通过 `fuelLevelAvailability`、`averageConsumptionAvailability`、`tripAvailability` 和 `odometerAvailability` 标记各字段状态；不可用字段的解码数值仅作为兼容占位，业务和 UI 必须检查状态后再使用。

### 9.2 Data2：发动机、保养、温度和电压

Frame ID：`0x03`，研究文档定义 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 当前换算 / 状态 |
|---:|---:|---|---|
| 0 | 1 | Reserved | 当前记录部分隐藏位 |
| 1 | 1 | Engine Status | 使用 `raw & 0x03`，0 未转动、1 启动中、2 运转中、3 熄火阶段 |
| 2 | 1 | Reserved | 当前记录隐藏位 |
| 3 | 1 | Maintenance | 使用 `raw & 0xE0` 判断是否需要保养 |
| 4 | 1 | Outside Temperature | `raw - 50 °C` |
| 5 | 1 | Battery Voltage | `raw × 0.1 V` |
| 6～7 | 2 | Reserved | 当前仅按原始数据保留 |

当前 iOS 代码还推断了：

- `bytes[1]` 的高两位作为背光模式；
- `bytes[1]` 的 bits 3:2 作为电池显示状态；
- `bytes[1]` 的 bits 5:4 作为支架状态；
- 发动机温度暂时固定为 `0`。

根据 `BLE-OPT-009` 的真车抓包结果，背光、电池显示、支架相关位的现场数据已经得到验证；当前代码仍以推断字段模型承载它们，后续应把抓包证据绑定到具体字段，并确认不同车型和仪表固件是否保持一致。发动机温度目前仍固定为 `0`，不属于本次已验证结论。

### 9.3 Data3：续航、配置和保养距离

Frame ID：`0x04`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 当前换算 |
|---:|---:|---|---|
| 0 | 2 | Autonomy | `UInt16 BE × 0.1 km` |
| 2 | 1 | Color / Unit | 颜色使用 bits 7:6，单位使用 bit 3 |
| 3 | 2 | Distance to Maintenance | `UInt16 BE × 1 km` |
| 5 | 1 | Language | `(raw >> 1) & 0x0F` |
| 6～7 | 2 | Reserved | 当前记录未知位 |

Data3 解码规则：

| 原始值 | 含义 |
|---|---|
| `color & 0xC0 == 0x00` | Blue |
| `color & 0xC0 == 0x40` | Gold |
| `color & 0xC0 == 0x80` | Red |
| `color & 0xC0 == 0xC0` | 未定义，当前回退 Blue |
| `color & 0x08 == 0` | Metric / Km |
| `color & 0x08 != 0` | Imperial / Mil |

语言解码值 1～5 分别对应 English、French、German、Spanish、Italian，未知值回退 English。

当续航或保养距离为 `0xFFFF`、颜色/单位或语言为 `0xFF` 时，代码仍保留原始 Payload，并分别输出 `autonomyAvailability`、`maintenanceDistanceAvailability`、`configurationAvailability` 和 `languageAvailability`；设置回读确认会拒绝不可用的 Data3。

### 9.4 Control：车速和转速

Frame ID：`0x05`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 标准换算 |
|---:|---:|---|---|
| 0～3 | 4 | Reserved | 忽略 |
| 4 | 2 | Engine Speed | `UInt16 BE × 0.25 rpm` |
| 6 | 2 | Vehicle Speed | `UInt16 BE × 0.01 km/h` |

当前代码额外解析：转向灯、近光灯、远光灯、双闪、TCS 模式和 TCS 就绪状态。上述 TCS 和灯光字段已经通过 `BLE-OPT-009` 真车抓包验证；但当前代码的字段映射仍需要单独回归。

当前实现中 TCS 就绪判断先把值掩码为低四位，再检查最高位，因此该判断存在实现逻辑矛盾。真车抓包已经证明相关原始位有验证价值，但在代码修正并回归前，不应把当前 `isTcsSystemReady` 输出直接视为可靠的 UI 状态。

### 9.5 ABS

Frame ID：`0x06`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 标准含义 |
|---:|---:|---|---|
| 0～1 | 2 | Reserved | 研究文档定义为保留字段 |
| 2 | 1 | ABS Status | `raw & 0x03`，1 正常、2 故障 |
| 3～7 | 5 | Reserved | 忽略 |

当前代码从 `bytes[0]` 和 `bytes[1]` 解析前轮速度及 ABS 灯状态；这些扩展字段已经通过 `BLE-OPT-009` 的真车抓包验证，但它们仍属于超出研究文档标准字段表的 iOS 扩展解析，应继续保留原始字节和车型/固件证据。

### 9.6 不可用值和保留位

研究文档约定了部分不可用值，例如 Data1 的 `0xFF`、Control 的 `0xFFFF`。当前 iOS 解析器已统一保留原始 Payload，并在解码模型中输出 `PTDashboardValueAvailability.available / unavailable`。Data2 的单字节字段、Data3 的 `0xFFFF`/`0xFF`、Control 的 `0xFFFF` 以及 ABS 的轮速/状态哨兵均按同一原则处理。

在协议文档和 UI 之间使用数据时，应区分：

- **原始值**：必须保留，便于抓包复核；
- **解码值**：只有在对应有效性为 `available` 时才用于仪表盘显示；
- **有效性**：通过 `PTDashboardValueAvailability` 说明该解码值是否来自可用原始值；
- **推断字段**：不能因为有数值就显示为确定的车辆状态。

未被 `BLE-OPT-009` 真车证据覆盖的保留字节当前只记录或忽略，不应在没有对应证据时重新解释为控制指令。

## 10. 连接身份和车辆关联

连接身份有两个来源：

1. CoreBluetooth 的 `CBCentral.identifier`，用于识别当前系统级连接对象。
2. 认证完成后收到的 ID `0x01` ASCII 字符串，作为仪表 / Connectivity Box 报告的序列身份。

车库和 PTT 业务可以在上层使用连接身份、蓝牙设备标识和用户自定义车辆名称建立关联，但这些字段不是标准导航或 Data1～Data3 业务帧的一部分。

### 10.1 iOS 代码入口映射

| 协议职责 | 当前代码入口 | 说明 |
|---|---|---|
| GATT Server、订阅、写入回调 | `PTBluetoothServerManager` | 维护 CoreBluetooth Peripheral 状态和连接身份 |
| 发送帧、配置帧、导航帧 | `PTFrameBuilder` | 只负责构造数据，不负责车辆确认 |
| 认证状态机 | `PTScooterAuth` + `PTAuthState` | 负责查表计算和四阶段握手 |
| 长度、上行重组、连接帧校验 | `PTXP400BLEProtocol` + `PTXP400BLEInboundReassembler` | 纯数据契约、阶段化重组和单元测试入口 |
| AMap 导航适配 | `PTMotoDashBoardNavFunction` | 将 AMap 动作和道路信息转成 XP400 Payload |
| 连接 watchdog、车库同步 | `PTVehicleConnectivityCoordinator` | 应用层状态协调，不等于 BLE 协议状态 |

后续排查问题时，日志应同时注明“GATT 状态、订阅状态、认证状态、Credits 状态、应用层发送状态”中的具体阶段，不能只使用一个 `isConnected` 布尔值判断整条链路。

### 10.2 现有自动化测试证据

当前仓库中已经存在以下纯数据契约测试：

| 测试 | 已覆盖内容 | 尚未证明的内容 |
|---|---|---|
| `testXP400BLEContractMatchesDocumentedConfigurationFrame` | 配置帧 Big-Endian 长度、完整 Hex 向量、20-byte 分片边界 | CoreBluetooth 真机发送、仪表接受配置 |
| `testXP400BLEContractSeparatesStatusAndAuthenticationFrames` | 11-byte 状态帧、15-byte 连接身份帧、非法身份字符 | 真实认证时序和车辆重组 |
| `testXP400BLEContractRejectsUndocumentedManeuverCodes` | 未确认动作码安全回退到 `0x01` | AMap 每一种动作在不同固件上的实际图标 |
| `testXP400BLEInboundReassemblerReassemblesSplitAndMergedHandshakeFrames` | 拆分 Key、合并认证写入和阶段切换 | 真车实际回调的分片边界 |
| `testXP400BLEInboundReassemblerHandlesSplitAndMergedStatusFrames` | 拆分状态帧、合并状态帧和连续排空 | 真车连续状态流量下的长期稳定性 |
| `testXP400BLEInboundReassemblerRecoversAfterInvalidKey` | 非法 Key 丢弃和合法 Key 恢复 | 车辆固件异常噪声的真实分布 |
| `testXP400BLEInboundReassemblerValidatesConnectionFrameAndResynchronizes` | 15-byte 连接帧严格校验和帧头重同步 | 真车非法连接帧后的恢复行为 |
| `testXP400BLEInboundReassemblerHandlesRawChallengeBoundaryAndDuplicate` | 20-byte 挑战边界和前阶段重复帧拦截 | 丢字节后的协议级恢复能力 |
| `testXP400BLEStrictCreditsAndAuthenticationBoundaries` | Credits 载荷/累计上限、15-byte Key 和 20-byte Challenge 严格边界 | CoreBluetooth ATT 回调和真实认证时序 |
| `testXP400DashboardUnavailableValueContract` | 原始 Payload 保留、Data1/Data3 不可用状态和配置单位占位 | 每种车辆固件哨兵值的现场确认 |

BLE-OPT-001、BLE-OPT-002、BLE-OPT-004 和 BLE-OPT-007 已有纯逻辑测试；BLE-OPT-003 和 BLE-OPT-006 的状态清理/队列行为已接入核心实现，但当前没有在 XCTest 中驱动真实 `CBPeripheralManager` 回调时序。BLE-OPT-005 的服务生命周期和前后台校正、Credits ATT 响应、断连清理、导航节流和完整认证握手仍需真车回归。

## 11. 当前尚未交付或仅供开发者测试的能力

### 11.1 电话、短信和第三方通知

当前代码新增 `PTDashboardANCSProvider`，复用现有 `CBPeripheralManager` 注册标准 ANCS UUID 的 Notification Source、Control Point 和 Data Source 特征，并维护订阅会话、UID、Control Point 属性读取和受 MTU 限制的分片队列。设置页的“发送直接 ANCS 测试”会发送固定英文的 App 自有消息；原有稳定 BLE 管理器和 TIO 传输逻辑未被重写。

真实设备验证已经确认：在 XP400 已启用 `Share System Notifications`、只保持 PTSpeed 与 XP400 连接并退出 Peugeot 官方 App 的条件下，真实来电和短信可以显示在仪表上。这说明当前 PTSpeed 使用 iOS 系统通知/ANCS 链路的路径是可工作的。

因此当前状态是：

- PTSpeed 的本地测试通知可以由系统通知中心提交，但只能验证 iPhone 本地通知投递；它不证明 XP400 已收到 ANCS 通知；
- 真实来电和短信在“仅 PTSpeed 连接、官方 App 已退出”的真机条件下已经可以显示在 XP400 仪表；
- iOS 不能读取其他 App 的通知正文并任意转发给 XP400；
- App 自有 ANCS 风格通道只发送 PTSpeed 主动生成的测试消息，不替代系统电话、短信或第三方通知链路；系统通知仍由 iOS 的 ANCS 条件决定；
- 该通道在服务注册失败、仪表未订阅或队列满时返回明确状态，不改变 TIO 连接；标准 ANCS 服务在 iOS 外设端的注册和 XP400 固件兼容性仍需真机验证；
- 第三方 App 通知、锁屏/专注模式、断连重连和不同仪表固件的兼容性仍待矩阵验证，当前不能对外宣称全部电话、短信和第三方通知场景均已支持。

### 11.2 TCS、背光和断开指令

TCS、灯光和 ABS 状态字段，以及断开帧的 Frame ID，已经有 `BLE-OPT-009` 真车抓包证据。`PTFrameBuilder` 仍提供可构造的 TCS、背光和断开帧，但写入指令的完整 Payload 语义、车辆响应和可逆性仍需按指令逐项验证；在此之前，TCS 和背光写入继续保持在 Dev 工具和实验记录范围内。

### 11.3 主动诊断和 Fuzz

主动诊断、配置通道探测、任意 ID 发送和 Mock 数据泵属于开发者能力，不是已确认的 XP400 BLE 应用协议。真实车辆测试必须具备明确的目标 ID、Payload、停止条件和日志留存策略。

## 12. Mock 与真实帧的边界

当前 Mock 数据用于驱动界面和业务联调：

- Data1 使用 8-byte Payload；
- Data2 当前使用 9-byte Payload，以配合现有宽松解析；
- Data3 当前使用 8-byte Payload，包含模拟颜色、单位、语言和 1100 km 保养距离；
- Control 使用 8-byte Payload；
- ABS 当前只有 3-byte Payload。

因此 Mock 不能用于证明真实仪表严格遵循 11-byte 状态帧。后续如果收紧解析器，必须先为 Mock 增加严格协议封装，避免界面回归测试被误伤。

## 13. 真车抓包验收清单

### 13.1 建立连接

- 确认 iPhone 广播 FEFB，且仪表可以发现并连接。
- 确认 TX 和 TX Credits 都完成订阅后才开始认证。
- 记录加密权限触发时机和系统配对行为。

### 13.2 双向认证

- 记录 Product ID 是否为 `00 00 22 36`。
- 记录两轮 20-byte Challenge 的分片顺序。
- 核对认证响应前 10 bytes，确认后 10 bytes 是否真的被车辆忽略。
- 确认 15-byte iOS Key/Configuration 的版本字段被车辆接受。
- 确认最后一帧是否严格为 15-byte `0x16 0x01 + 12-byte identity + 0x00`。
- 记录每个认证阶段的实际耗时，补足当前 iOS 未实现的超时证据。

### 13.3 业务帧

- 导航：确认完整帧分片、道路名称编码、两种距离的取整行为和 ETA 时区。
- 配置：分别验证颜色、单位和五种语言，并记录 Data3 回读。
- Data1～Data3：记录完整长度、保留字节和不可用值。
- Control / ABS：`BLE-OPT-009` 已完成 TCS、灯光、ABS 前轮速度和相关保留位的真车抓包验证；后续仍需把证据绑定到具体车型和固件。
- 断开：`BLE-OPT-009` 已确认 Frame ID 为 `0x08`；Payload `01 01` 的车辆行为仍按独立指令验证记录。

### 13.4 抓包记录格式

每次真车验证至少保存：车辆型号、仪表固件版本、iOS 版本、蓝牙中心标识摘要、时间、操作步骤、上行原始 Hex、下行原始 Hex、分片边界和最终 UI 结果。日志中不得保存认证查找表或其他不必要的敏感材料。

### 13.5 已完成的真车验证

`BLE-OPT-009` 已由真车抓包完成验证，当前可以把以下内容从“仅代码推断”提升为“已有真车字段证据”：

- TCS 状态相关位；
- 转向灯、近光灯、远光灯和双闪相关位；
- ABS 前轮速度和 ABS 灯相关位；
- 本次抓包覆盖到的保留位；
- Disconnect Frame ID `0x08`。

另外，系统通知链路已完成一项行为验证：

- 在 XP400 开启 `Share System Notifications`、退出 Peugeot 官方 App、仅连接 PTSpeed 的条件下，真实来电和短信可以显示在仪表；
- PTSpeed 发出的普通本地测试通知可以在 iPhone 上出现，但不能作为仪表 ANCS 已收到的证据；第三方通知、锁屏/专注模式和断连重连仍需单独记录。

本节只记录验证结论，不虚构未提供的车型、固件或抓包文件路径。若同一字段在其他车型或仪表固件上出现差异，应在这里追加兼容性记录，而不是覆盖原结论。

## 14. 协议 ID 汇总

| Frame ID | 方向 | 当前用途 | 状态 |
|---:|---|---|---|
| `0x01` | iPhone → 仪表 | 导航 | **已确认并实现** |
| `0x01` | 仪表 → iPhone | 连接身份 / 心跳候选 | **已确认格式，解析较宽松** |
| `0x02` | 仪表 → iPhone | Data1：油量、Trip、ODO | **已确认并实现** |
| `0x03` | 仪表 → iPhone | Data2：发动机、保养、温度、电压 | **核心字段已确认** |
| `0x04` | 仪表 → iPhone | Data3：续航、配置、保养距离 | **核心字段已确认** |
| `0x05` | 仪表 → iPhone | Control：转速、车速 | **核心字段已确认** |
| `0x06` | 仪表 → iPhone | ABS | **核心字段已确认** |
| `0x07` | iPhone → 仪表 | 颜色、单位、语言配置 | **已确认并实现** |
| `0x08` | iPhone → 仪表 | 断开 | **Frame ID 已由真车抓包确认，Payload 行为待单独记录** |

## 15. 代码与文档维护规则

后续修改 BLE 协议相关代码时，必须同时回答三个问题：

1. 这是外部文档已经确认的字段，还是当前车辆推断？
2. 这是发送封装、传输分片、认证状态机还是业务解析变化？
3. 是否有真车抓包或 Mock 单元测试支持这次结论？

`PTBluetoothManager.swift` 当前承担稳定的 CoreBluetooth GATT Server、认证、Credits、分片、解析和 Mock 兼容逻辑。没有新的真车证据和回归测试前，不应为了整理代码而改变其核心状态机、分片边界或认证计算。

本文档是实现和验证入口，不替代代码中的协议契约，也不代表 Peugeot 官方发布的公开协议。

## 16. iOS 实现优化与验证清单

以下项目不是当前协议事实，而是根据外部文档与现有 iOS 实现对比后整理出的后续工作包。完成代码或真车验证后，再更新对应状态和证据链接。

### P0：连接安全和会话边界

- [x] **BLE-OPT-001 上行分片重组**：分别处理认证数据、固定状态帧和可能被拆分/合并的 UART 写入；验收标准是分片、合并、重复和非法包不会误推进认证状态机。已加入阶段化重组器、严格认证长度、连接帧/状态帧校验、非法帧重同步和纯数据测试；真车实际分片边界仍需现场验收。
- [x] **BLE-OPT-002 Credits 输入保护**：`UART_RX_CREDITS` 只接受单字节合法额度并限制会话累计上限；非法输入返回 ATT 错误并留下脱敏日志。纯逻辑边界已测试，真实中心端写入仍需现场验收。
- [x] **BLE-OPT-003 连接会话清理**：断连、蓝牙不可用或新 Central 到来时清空发送队列、发送额度、本地额度、发送阻塞状态、活跃通知、待发送导航和认证临时数据；真实多 Central 时序仍需现场验收。

### P1：协议一致性和运行稳定性

- [x] **BLE-OPT-004 严格认证帧校验**：15-byte Key/Configuration、20-byte Challenge/Response 和 15-byte Connection Frame 已统一使用纯协议校验；认证查表和前 10-byte 兼容算法未改变。真实车辆兼容性仍需现场验收。
- [x] **BLE-OPT-005 服务生命周期**：已明确 `didUpdateState`、`didAdd service`、开始广播、停止广播和重复启动的状态；蓝牙不可用时停止广播并保留启动意图，恢复后重新注册服务；前后台切换采用幂等校正且后台不主动中断已请求的 Peripheral 会话。真实设备的蓝牙开关、系统后台挂起和进程终止结果仍需现场验收。
- [x] **BLE-OPT-006 导航状态合并**：已增加动作/道路/距离/ETA 去重、0.5 秒最低发送间隔，以及 Credits 不足时的最新导航保留；其他协议任务不会被导航合并删除。真实仪表显示频率仍需现场验收。
- [x] **BLE-OPT-007 不可用值统一**：Data1～Data3、Control 和 ABS 已保留原始 Payload 并输出字段级有效性；车库、保养、续航、仪表和骑行统计在使用前检查状态。不同固件的哨兵语义仍需现场验收。
- [x] **BLE-OPT-008 严格 Mock 样本**：Data2 和 ABS Mock 均使用 8-byte Payload，在线路上组成标准 11-byte 状态帧；`parseDashboardFrame(_:)` 对 Connection Frame 和 `0x02–0x06` 已知状态帧执行严格长度检查。纯数据回归覆盖标准帧、Data2 超长帧和 ABS 短帧；真实车辆仍需现场确认是否始终遵循该长度。

### P2：高阶字段和扩展能力

- [x] **BLE-OPT-009 真车字段矩阵**：已完成真车抓包验证，覆盖 TCS、灯光、ABS 前轮速度、相关保留位和断开帧 ID。原始抓包未内嵌到本文，具体车型、仪表固件、iOS 版本和文件归档位置以现场验证记录为准；写入指令仍需单独验收。
- [ ] **BLE-OPT-010 ANCS 完整链路**：真实设备已确认系统 ANCS 路径在“仅 PTSpeed 连接、官方 App 已退出”条件下可显示真实来电和短信；仍需第三方通知、锁屏/专注模式、重连和多固件矩阵，以及必要的抓包证据。当前 `PTAncsNotif` 原型不升级、不自建第二套 ANCS GATT，除非后续证据证明系统路径无法覆盖目标场景。

### 16.1 完成定义

每个工作包至少要留下以下证据：

1. 变更前后的协议行为说明；
2. 对应的纯数据测试或真车抓包；
3. 失败、取消、断连和重复连接场景结果；
4. 对旧 Mock、导航和配置 UI 的回归结论。

未完成工作包不得把本文件中的“已确认并实现”状态升级为“真车已验证”。

## 17. 1.3 版审计结论

与外部研究文档相比，当前 iOS 代码已经覆盖 XP400 的主要 TIO UART 业务路径，但仍有以下细节不应被忽略：

- 认证关键固定长度、Key 前缀、Connection identity 和 Credits 输入已在纯协议层严格校验；
- 认证和连接超时在 iOS 核心中尚未完整实现；
- 当前导航来源是 AMap，BLE 边界已统一做状态合并、最新值保留和最低发送间隔；
- 后台模式已声明；服务添加和前后台广播校正已实现，但 CoreBluetooth State Restoration 仍未实现；
- 断连清理、Credits 健壮性、上行重组和不可用值状态已经接入；CoreBluetooth 回调时序仍需现场回归；
- 系统 ANCS 路径已在 PTSpeed 单独连接的真车场景验证真实来电和短信；代码中的 `PTAncsNotif` 自建通道仍未实现，第三方通知和跨条件兼容性不应宣称为正式支持；TCS、灯光、ABS 前轮速度和部分保留位已经具备真车字段证据，但 TCS/背光写入指令和跨车型兼容性仍不能直接当作正式支持能力。

因此，当前文档可以作为 iOS BLE 实现和真车验证基线，但不能替代车辆固件协议确认；本次实现没有改写认证查表、TIO 分片算法或已稳定的核心传输边界。
