# Peugeot XP400 iOS BLE 通信协议与实现规范

> 文档版本：1.0
>
> 审计日期：2026-09-03
>
> iOS 代码基线：`e66f902`
> 文档定位：项目内部实现规范 / 真车抓包校验依据

## 1. 文档边界

本文档根据项目当前 iOS BLE 实现和外部研究文档 `Peugeot_Motocycles_BLE_Protocol.md` 整理而成。外部文档是研究参考，不是可以直接执行的工程指令；最终以当前仓库代码、真车抓包和实际车辆行为为准。

认证查找表仍由现有实现内部使用，协议文档只记录它的输入、输出和验证边界。

可信度使用以下标记：

| 标记 | 含义 |
|---|---|
| **已确认并实现** | 当前代码已有明确实现，且与研究文档的核心格式一致 |
| **已实现但属推断** | 当前代码可以工作，但字段含义或车辆兼容性尚未由真车抓包完全确认 |
| **尚未实现 / 待验证** | 当前只有模型、日志、模拟或构造器，不能作为已交付能力 |

当前审计结论：GATT、Credits、认证主流程、导航封装、配置封装以及 Data1～Data3 的核心换算没有重大方向性差异；但是 iOS 解析器的长度校验、认证超时、ANCS 通道和若干高阶字段仍存在实现差异，必须在本文档中单独标注。

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
CBPeripheralManager.state == .poweredOn
        ↓
创建 FEFB 服务和四个特征
        ↓
仅广播 FEFB Service UUID
        ↓
XP400 连接并订阅 TX / TX Credits
        ↓
进入私有认证
        ↓
认证完成后开放业务帧
```

当前广告只包含服务 UUID，不主动广播本地设备名称。蓝牙未处于 `.poweredOn` 时不会启动广播。

断开订阅后，代码会清除认证状态、订阅标志、连接身份和日志状态，并通知业务代理连接已经结束。

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
| 最大 Credits | `25` |
| 补充阈值 | `4` |
| 单个 TIO 分片最大长度 | `20 bytes` |

### 4.2 iPhone 发送

1. 仪表向 UART RX Credits 写入一个字节，增加 `sendCredits`。
2. iOS 将完整业务帧拆成连续的 20-byte 分片。
3. 每次成功调用 `updateValue(_:for:onSubscribedCentrals:)` 后消耗一个 `sendCredits`。
4. 没有额度时保留发送队列，等待新的额度。
5. CoreBluetooth 返回发送失败时等待 `peripheralManagerIsReady(toUpdateSubscribers:)` 再继续发送。

当前发送队列没有增加序列号、重传计数或应用层 ACK。是否存在仪表端额外重传机制，必须通过真车抓包确认。

### 4.3 仪表发送

认证完成后，iOS 通过 UART TX Credits 补充额度，初始最多授予 25 个。`localCredits` 降到 4 或更低时再次补足到 25。

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
    ↓ 收到以 0x16 开头的连接帧
success
```

具体交互：

| 步骤 | 仪表 → iPhone | iPhone → 仪表 | 当前状态 |
|---:|---|---|---|
| 1 | 4-byte Product ID，Big-Endian `8758` | 10 个随机 `UInt16`，共 20 bytes | **已确认并实现** |
| 2 | 第一轮响应，当前至少检查 10 bytes | 15-byte iOS Key/Configuration | **已确认并实现** |
| 3 | 10 个 `UInt16`，共 20 bytes | 20-byte 计算响应 | **已确认并实现** |
| 4 | 连接确认帧候选 | 开放状态数据和业务帧 | **已实现但长度检查较宽松** |

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

`0xFF` 可能代表不可用，但当前代码没有把所有不可用值统一提升为独立状态。

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

这些字段标记为 **已实现但属推断**，不能在协议层当作已确认定义。

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

### 9.4 Control：车速和转速

Frame ID：`0x05`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 标准换算 |
|---:|---:|---|---|
| 0～3 | 4 | Reserved | 忽略 |
| 4 | 2 | Engine Speed | `UInt16 BE × 0.25 rpm` |
| 6 | 2 | Vehicle Speed | `UInt16 BE × 0.01 km/h` |

当前代码额外解析：转向灯、近光灯、远光灯、双闪、TCS 模式和 TCS 就绪状态。这些属于 **已实现但属推断**。

当前实现中 TCS 就绪判断先把值掩码为低四位，再检查最高位，因此该判断存在逻辑矛盾；在没有新的真车字段证据前，不应把它作为可靠的 TCS 状态依据。

### 9.5 ABS

Frame ID：`0x06`，标准 Payload 为 8 bytes。

| Offset | 长度 | 字段 | 标准含义 |
|---:|---:|---|---|
| 0～1 | 2 | Reserved | 研究文档定义为保留字段 |
| 2 | 1 | ABS Status | `raw & 0x03`，1 正常、2 故障 |
| 3～7 | 5 | Reserved | 忽略 |

当前代码还从 `bytes[0]` 和 `bytes[1]` 推断前轮速度及 ABS 灯状态，这些字段目前没有得到研究文档确认，属于实验解析。

## 10. 连接身份和车辆关联

连接身份有两个来源：

1. CoreBluetooth 的 `CBCentral.identifier`，用于识别当前系统级连接对象。
2. 认证完成后收到的 ID `0x01` ASCII 字符串，作为仪表 / Connectivity Box 报告的序列身份。

车库和 PTT 业务可以在上层使用连接身份、蓝牙设备标识和用户自定义车辆名称建立关联，但这些字段不是标准导航或 Data1～Data3 业务帧的一部分。

## 11. 当前尚未交付或仅供开发者测试的能力

### 11.1 电话、短信和第三方通知

当前代码存在 `PTAncsNotif` 以及 Notification Source / Data Source 构造器，但 `sendCustomAlertToDashboard` 只构造数据，没有实际绑定 ANCS GATT 服务、特征和发送队列。

因此当前状态是：

- iOS 本地通知可以由系统通知中心提交；
- iOS 不能读取其他 App 的通知正文并任意转发给 XP400；
- XP400 专用 ANCS 风格通道尚未完成；
- 不能对外宣称电话、短信和第三方通知已经支持。

### 11.2 TCS、背光和断开指令

`PTFrameBuilder` 已提供可构造的 TCS、背光和断开帧，且管理器提供开发者调用入口，但这些指令的实际 Frame ID、Payload 语义或车辆响应仍需真车抓包确认。它们应继续保持在 Dev 工具和实验记录范围内。

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
- Control / ABS：只把抓包中稳定重复的字段提升为协议结论。
- 断开：确认 Frame ID 是否确实为 `0x08`，以及 Payload `01 01` 的车辆行为。

### 13.4 抓包记录格式

每次真车验证至少保存：车辆型号、仪表固件版本、iOS 版本、蓝牙中心标识摘要、时间、操作步骤、上行原始 Hex、下行原始 Hex、分片边界和最终 UI 结果。日志中不得保存认证查找表或其他不必要的敏感材料。

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
| `0x08` | iPhone → 仪表候选 | 断开 | **Frame ID 待真车确认** |

## 15. 代码与文档维护规则

后续修改 BLE 协议相关代码时，必须同时回答三个问题：

1. 这是外部文档已经确认的字段，还是当前车辆推断？
2. 这是发送封装、传输分片、认证状态机还是业务解析变化？
3. 是否有真车抓包或 Mock 单元测试支持这次结论？

`PTBluetoothManager.swift` 当前承担稳定的 CoreBluetooth GATT Server、认证、Credits、分片、解析和 Mock 兼容逻辑。没有新的真车证据和回归测试前，不应为了整理代码而改变其核心状态机、分片边界或认证计算。

本文档是实现和验证入口，不替代代码中的协议契约，也不代表 Peugeot 官方发布的公开协议。
