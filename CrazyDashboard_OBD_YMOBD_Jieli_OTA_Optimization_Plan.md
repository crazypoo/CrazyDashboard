# CrazyDashboard OBD / YMOBD / Jieli OTA 优化与实现计划

> 用途：作为下一次继续改造 `CrazyDashboard` 的长期参考文档。  
> 目标仓库：`https://github.com/crazypoo/CrazyDashboard`  
> 重点模块：`Global/OBD`，尤其 `Function/PTHiddenOBDConnector.swift`  
> 当前依据：
> - CrazyDashboard 当前公开代码的既有分析
> - `YMOBD-BLE-OBD-Initialization-Reproduction.md`
> - `app-service.js`
> - `YMOBD-Android.zip` 中的 DEX / SO 逆向结果
>
> 本文把信息分为：
> - **已确认**：当前文档、JS、DEX、SO 或 CrazyDashboard 代码中已有直接证据
> - **高置信推断**：多条证据一致，但仍建议真机抓包验证
> - **待验证**：实现前还应从真实硬件或更深层字节码确认

---

# 1. 总结

CrazyDashboard 当前 OBD 模块已经能够完成 BLE OBD 连接、ELM/YMOBD 初始化、PID 读取和部分 UDS/CAN 能力，但与 YMOBD 官方 App 的真实连接状态机相比，仍缺少一批重要兼容逻辑。

最优先的不是 OTA，而是先把普通 YMOBD 连接链路修到“官方兼容级”：

1. 修复 `<AUTH>` 替换 `ATRV` 的 P0 Bug
2. 修复 `AT+VERSION` 字段解析
3. 正确保存并验证 `AT+CRYPT` challenge
4. 补齐 `0100 -> AT+DEBUG_FLG -> 0100` 重试
5. 补齐初始化阶段每条命令 20 秒超时
6. 只有 `0100` 支持位非全 0 才允许进入 connected / unlocked
7. 补齐 BLE FFF0 优先校验、通用 ELM327 扫描、30 秒扫描截止、服务发现超时和自动重连
8. 扩展 YMOBD 官方设备名支持

OTA 方面，现在已经确认 YMOBD 使用：

- Jieli / 杰理 `jl_bt_ota`
- RCSP OTA
- YMOBD 自己的 `utsJieliOta`
- `OTAModule`
- `BleManager`
- `OTASecret`
- `libjl_ota_auth.so`

因此 OTA 不应该自己从零实现 RCSP 分包协议，而应该优先接入杰理官方 iOS OTA SDK，并在 CrazyDashboard 外层复刻 YMOBD 的：

- 固件检查
- 临时密钥生成
- 固件下载
- 固件 AES 解密
- OTA 生命周期
- 断线回连
- OTA 后版本回读

---

# 2.0 本次实施边界修订：PTHiddenOBDConnector 的 ELM327 基线

`PTHiddenOBDConnector.swift` 是项目的通用 ELM327 OBD 连接与传输实现，YMOBD 只是其中的可选扩展能力。因此，本计划中所有 YMOBD 规则都必须在能力探测成功后启用，不能把普通 ELM327 强制当作 YMOBD 设备处理。

本次 P0 实施采用以下兼容策略：

- `AT+VERSION` 只要没有 `devicename`、`devicetype`、`devicemac`、`custid`、`crypt` 等 YMOBD 专属字段，就跳过认证槽位，继续原有 ELM327 标准初始化。
- 扫描不设置全局 FFF0 硬过滤，以保留既有通用 ELM327 设备发现能力；已知 YMOBD 的 FFF0 服务仍然优先，连接后再按 FFF0 或通用 ELM327 服务完成特征发现。
- `AT+DEBUG_FLG` 只对已探测到 YMOBD 字段的设备启用；普通 ELM327 遇到 `0100` 失败时只执行有上限的 `0100` 重试。
- 认证失败但收到了正常 prompt 时不阻断普通只读初始化；没有 prompt 仍由初始化超时和物理重连策略处理。

这样可以同时满足 YMOBD 官方链路兼容性和通用 ELM327 的既有可用性，不复制第二套传输层，也不改变 `PTOBDCommand.swift` 或 BLE 核心。

---

# 2. CrazyDashboard 当前 OBD 模块已发现的问题

## 2.1 P0：`<AUTH>` 替换逻辑存在实际 Bug

当前 `PTHiddenOBDConnector` 初始化队列中本来包含：

```text
ATZ
ATE0
ATL0
ATH1
ATSP0
AT+VERSION
ATI
ATRV
<AUTH>
0100
020000
0600
0900
ATDP
0120
0140
0902
0904
0906
```

但当前 reset 逻辑大意为：

```swift
if let authIndex = initQueue.firstIndex(where: {
    $0.hasPrefix("AT+CRYPT") ||
    $0.hasPrefix("AT+SETCRYPT") ||
    $0 == "ATRV"
}) {
    initQueue[authIndex] = "<AUTH>"
}
```

这里第一个命中项是 `ATRV`。

结果：

```text
ATI
<AUTH>
<AUTH>
0100
...
```

这会造成：

- 原始 `ATRV` 被错误覆盖
- 队列出现两个 `<AUTH>`
- 后续只替换一个 placeholder 时，可能真的发送字面量 `<AUTH>`

### 必须修改

只允许替换原始 `<AUTH>`、`AT+CRYPT...`、`AT+SETCRYPT...`，不能把 `ATRV` 当成认证槽位。

建议：

```swift
private func resetAuthSlot() {
    if let index = initQueue.firstIndex(where: {
        $0 == "<AUTH>" ||
        $0.hasPrefix("AT+CRYPT") ||
        $0.hasPrefix("AT+SETCRYPT")
    }) {
        initQueue[index] = "<AUTH>"
    }
}
```

---

# 3. YMOBD 官方初始化流程

## 3.1 已确认的 19 步初始化队列

官方初始化顺序：

```text
1  ATZ
2  ATE0
3  ATL0
4  ATH1
5  ATSP0
6  AT+VERSION
7  ATI
8  ATRV
9  AUTH
10 0100
11 020000
12 0600
13 0900
14 ATDP
15 0120
16 0140
17 0902
18 0904
19 0906
```

认证步骤是条件分支：

```text
有 crypt:
    AT+SETCRYPT<crypt32(crypt, 0x263D9A7E)>

无 crypt:
    challenge = random(0x12345678 ... 0x7FFFFFFE)
    AT+CRYPT<challenge>
```

---

# 4. `AT+VERSION` 解析需要修正

官方实际字段是：

```text
devicename:
devicetype:
version:
devicemac:
custid:
crypt:
```

当前 CrazyDashboard 已知解析 key 包含：

```text
device name
device type
device mac
cust id
```

这与官方无空格字段不一致。

### 建议兼容两套 key

```swift
switch key.lowercased() {
case "devicename", "device name":
    ...
case "devicetype", "device type":
    ...
case "version":
    ...
case "devicemac", "device mac":
    ...
case "custid", "cust id":
    ...
case "crypt":
    ...
default:
    break
}
```

优先按官方无空格格式解析。

---

# 5. `AT+CRYPT` challenge 必须保存和验证

当前 CrazyDashboard 会生成 challenge，但没有完整保存 challenge 并校验返回结果。

官方逻辑：

```text
challenge = random(...)
send AT+CRYPT<challenge>

expected = hex8(
    crypt32(challenge, 0x263D9A7E)
)

response 前 8 位 == expected
    -> isOfficial = true

不匹配但有 prompt
    -> isOfficial = false
    -> 初始化继续

没有 prompt
    -> 超时 / 断开
```

固定测试向量：

```text
challenge: 12345678
expected : DEFEFEAD
```

### CrazyDashboard 应新增状态

```swift
private var currentAuthChallenge: UInt32?
private(set) var isOfficialYMOBD: Bool = false
```

并在发送 `AT+CRYPT` 时：

```swift
currentAuthChallenge = challenge
```

收到回复时再比对。

---

# 6. 初始化重试状态机需要补齐

官方关键规则：

## 6.1 ATZ

```text
ATZ
↓
STOPPED
↓
重试 ATZ
```

## 6.2 基础 AT 命令

以下命令如果没有 `OK`：

```text
ATE0
ATL0
ATH1
ATS0
```

官方会重试。

CrazyDashboard 已实现其中一部分，可保留。

## 6.3 `0100 + UNABLE TO CONNECT`

首次出现：

```text
0100
↓
UNABLE TO CONNECT
↓
AT+DEBUG_FLG
↓
0100
```

如果再次出现：

```text
0100
↓
UNABLE TO CONNECT
↓
0100
```

当前 CrazyDashboard 没有完整实现。

建议增加：

```swift
private var hasTriggeredDebugFlagFor0100 = false
```

逻辑：

```swift
if activeCommand == "0100",
   response.contains("UNABLE TO CONNECT") {

    if !hasTriggeredDebugFlagFor0100 {
        hasTriggeredDebugFlagFor0100 = true
        send("AT+DEBUG_FLG")
    } else {
        retry("0100")
    }
}
```

`AT+DEBUG_FLG` 返回后直接回：

```text
0100
```

## 6.4 `0100 + NO DATA`

官方：

```text
0100
↓
NO DATA
↓
0100
```

只要 BLE prompt 仍正常返回，官方会持续尝试。

建议 CrazyDashboard 增加合理上限，避免死循环，例如：

```swift
max0100RetryCount = 20
```

调试模式可放宽。

---

# 7. 初始化阶段缺少每命令 20 秒超时

CrazyDashboard 的普通 async command 已存在约 20 秒 timeout，但初始化使用的是另一条 `sendNextCommand()` 流程。

目前初始化命令发送后如果一直收不到：

```text
>
```

可能永远卡住。

### 建议

每发送一个 init command：

```swift
startInitCommandTimeout(command: activeCommand)
```

20 秒内没有 prompt：

```text
cancel timeout
↓
disconnect
↓
进入 reconnect 策略
```

收到：

```text
>
```

立即取消 timeout。

---

# 8. 初始化成功判定必须后移

官方不是：

```text
19 条命令全部跑完
=
成功
```

官方真正成功条件是：

```text
0100 解析出的 32-bit supported PID mask
!=
00000000000000000000000000000000
```

然后才：

```text
connectedECU = true
```

当前 CrazyDashboard 在 initQueue 结束后过早：

```swift
isUnlocked = true
onIceBroken?()
```

这是协议语义错误。

### 正确做法

保存：

```swift
private var pid0100Mask: String?
```

最终：

```swift
guard let mask = pid0100Mask,
      mask != "00000000000000000000000000000000"
else {
    disconnect(reason: .ecuUnsupportedOrUnavailable)
    return
}

isUnlocked = true
onIceBroken?()
```

---

# 9. BLE 扫描流程需要向官方靠齐

## 9.1 官方扫描 Service

```text
0000FFF0-0000-1000-8000-00805F9B34FB
```

当前 CrazyDashboard：

```swift
scanForPeripherals(withServices: nil, ...)
```

建议：

```swift
scanForPeripherals(
    withServices: [CBUUID(string: "FFF0")],
    options: [
        CBCentralManagerScanOptionAllowDuplicatesKey: false
    ]
)
```

> 兼容性修订：上面的 FFF0 过滤是“官方 YMOBD 专用实现”的参考，不适合作为本仓库通用入口的硬过滤。`PTHiddenOBDConnector` 必须继续使用无服务过滤扫描来发现通用 ELM327；连接后优先选择实际存在的 FFF0，再回退到设备提供的通用服务。

## 9.2 扫描截止时间

官方：

```text
30 秒
```

CrazyDashboard 当前 UI 连接超时约 10 秒，但底层 scan 可能继续。

需要把：

```text
UI connection timeout
```

和：

```text
BLE scan timeout
```

拆开。

建议：

```swift
private let scanTimeout: TimeInterval = 30
```

扫描截止：

```swift
central.stopScan()
```

---

# 10. 官方设备名白名单

已确认官方列表：

```text
OBDII
MS310
B25
V500
YM529
YM329
YM129
YM819
BT529
P300
BT15
BT17
OBD114
OBD147
BROM S10
BROM S15
BROM S20
BT319
BT369
TPMS
C15
C35
```

官方是：

```text
case-sensitive exact match
```

CrazyDashboard 当前正常 OBD whitelist 已知只有：

```text
OBDII
MS310
B25
V500
YM529
YM329
YM129
YM819
BT529
```

至少应补：

```text
OBD114
OBD147
BROM S10
BROM S15
BROM S20
```

但不要把所有 OTA / TPMS / Battery 设备直接当普通 OBD。

---

# 11. 官方设备类型分类

已确认：

```text
OTAList:
P300
BT369
C15
C35

BatteryTester:
BT_00
BT15
BT17
BT319

TPMS:
TPMS
```

分类：

```text
projectType = 999 -> OTA
projectType = 3   -> TPMS
projectType = 2   -> Battery Tester
projectType = 1   -> Normal OBD
```

CrazyDashboard 如果未来同时支持这些设备，应明确抽象：

```swift
enum PTYMOBDDeviceCategory {
    case obd
    case batteryTester
    case tpms
    case otaCapable
    case unknown
}
```

不要通过字符串散落在 connector 内判断。

---

# 12. GATT 行为

普通 YMOBD OBD：

```text
Service:
FFF0
```

官方会：

- 找最后一个 write characteristic
- 找最后一个 notify / indicate characteristic
- 保持 characteristic 自身默认 write type
- 开启 notify / indicate
- 等约 1 秒后进入初始化

CrazyDashboard 当前这一部分整体较接近官方。

## iOS 注意

不要手动写 CCCD：

```text
0x2902
```

CoreBluetooth 应使用：

```swift
peripheral.setNotifyValue(true, for: characteristic)
```

这是正确 iOS 层抽象。

---

# 13. 服务发现超时

官方大约：

```text
10 秒
```

如果 FFF0 service / characteristic discovery 没完成：

```text
close
↓
reconnect
```

CrazyDashboard 当前缺少明确的 service discovery watchdog。

建议：

```swift
private var serviceDiscoveryTimeoutTask: Task<Void, Never>?
```

或基于现有 PTGCDManager。

---

# 14. 自动重连状态机

官方：

```text
主动用户断开
status = 10009
↓
不自动重连
```

普通异常断线：

```text
status = 10006
↓
startConnecting()
```

OTA 中：

```text
交给 OTA Manager
```

CrazyDashboard 目前 `didDisconnectPeripheral` 基本只回调断开。

建议新增：

```swift
enum PTBLEDisconnectReason {
    case userInitiated
    case transportError
    case serviceDiscoveryTimeout
    case commandTimeout
    case otaTransition
}
```

然后：

```swift
switch reason {
case .userInitiated:
    break

case .otaTransition:
    otaManager.handleDisconnect(...)

default:
    scheduleReconnect()
}
```

---

# 15. 首页官方 24 命令轮询

官方首页不是动态 PID queue，而是固定：

```text
010C
010D
010C
0105
010C
ATRV

010C
010D
010C
0105
010C
ATRV

010C
010D
010C
0105
010C
ATRV

010C
010D
010C
0105
010C
ATRV
```

共：

```text
24 条
```

意义：

```text
RPM 010C 采样频率最高
Speed 010D
Coolant 0105
Voltage ATRV
```

CrazyDashboard 当前动态 weighted polling 功能更灵活，不一定要删除。

建议增加：

```swift
enum PTOBDPollingProfile {
    case officialYMOBD
    case adaptive
}
```

这样：

```text
officialYMOBD
```

用于协议复刻/兼容测试，

```text
adaptive
```

用于 CrazyDashboard 实际产品体验。

---

# 16. OTA：已经确认的整体架构

现在已经直接确认：

```text
YMOBD App
    ↓
utsJieliOta
    ↓
OTAModule
    ↓
BleManager
    ↓
com.jieli.jl_bt_ota
    ↓
RCSP
    ↓
Jieli 芯片
```

APK 内找到：

```text
classes2.dex
classes4.dex
```

以及：

```text
lib/arm64-v8a/libjl_ota_auth.so
lib/armeabi-v7a/libjl_ota_auth.so
```

---

# 17. classes2.dex：Jieli OTA SDK

已确认存在：

```text
com.jieli.jl_bt_ota
```

核心类：

```text
BluetoothOTAManager
RcspAuth
RcspOpImpl

IUpgradeCallback
IUpgradeManager

IRcspOTA
IRcspOp
```

OTA command 类包括：

```text
EnterUpdateModeCmd
ExitUpdateModeCmd

FirmwareUpdateBlockCmd
FirmwareUpdateStatusCmd

GetUpdateFileOffsetCmd

InquireUpdateCmd

NotifyUpdateContentSizeCmd

RebootDeviceCmd

SettingsMtuCmd
```

这说明：

- OTA 使用 RCSP
- 有 OTA mode
- 有 firmware block
- 有 firmware status
- 有 offset
- 支持升级断点 / 重连续传
- 有 MTU 设置
- 有 reboot

因此 CrazyDashboard 不应手写这套 RCSP packet。

---

# 18. classes4.dex：YMOBD 自己的 OTA 封装

已确认类：

```text
uts/sdk/modules/utsJieliOta/BleManager
uts/sdk/modules/utsJieliOta/BluetoothCompat

uts/sdk/modules/utsJieliOta/OTAModule

uts/sdk/modules/utsJieliOta/OTASecret

uts/sdk/modules/utsJieliOta/ReConnectHelper

uts/sdk/modules/utsJieliOta/IndexKt
```

JS 暴露：

```text
createEncryptKeyByJs

initOTAByJs

startOTAByJs

queryMandatoryUpdateByJs

reconnectOTAByJs

cancelOTAByJs

deInitByJs
```

---

# 19. OTA BLE UUID 线索

Jieli SDK 中已经发现：

```text
0000AE00-0000-1000-8000-00805F9B34FB
0000AE01-0000-1000-8000-00805F9B34FB
0000AE02-0000-1000-8000-00805F9B34FB
```

高置信关系：

```text
AE00 -> OTA / RCSP Service
AE01 / AE02 -> Write / Notify
```

但：

> AE01 和 AE02 的具体 write / notify 映射建议在 iOS 接入前再从 `BleManager` 字段赋值或真机 characteristic properties 确认，不要只靠命名推断。

---

# 20. `OTASecret` 已还原

## 20.1 核心不是固定密码

每次 OTA：

```text
UUID.randomUUID()
```

例如：

```text
550e8400-e29b-41d4-a716-446655440000
```

返回给 JS 的：

```text
key
```

是带 `-` UUID：

```text
550e8400-e29b-41d4-a716-446655440000
```

然后：

```text
remove("-")
```

变成：

```text
550e8400e29b41d4a716446655440000
```

这是：

```text
32 ASCII bytes
=
256 bit
```

作为 AES key。

---

# 21. `createEncryptKey()` 算法

逻辑：

```text
UUID.randomUUID()
        ↓
keyStr = 带 "-"
        ↓
remove("-")
        ↓
UTF-8
        ↓
32-byte AES key
        ↓
RSA/ECB/PKCS1Padding
        ↓
uppercase HEX
        ↓
encryptKey
```

返回结构：

```json
{
  "code": "1",
  "msg": "createEncryptKey ok",
  "encryptKey": "...",
  "key": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "pubKeyVer": 3
}
```

---

# 22. OTA RSA 公钥

已确认：

```text
RSA
2048 bit
Exponent = 65537
pubKeyVer = 3
```

公钥：

```pem
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtYT8O4diulE8FDFC89Dq
bevMrppsCm8JT5KHMkYNqmEnoajch9NjUAEXFG6nEOKG4jngQ6oMuPNLiJEEKI5m
tzUMImpAP/g0sCBUDnrB7r8CovULM9KY7KG2J4vgopX2EbKOfhLeUcDA/hD0+iPN
IyaYMmBdnYsrpXQ5NZHR0dVpDquwnRVrZGr6XIxheoWWC1hfA4/0pAiZpWdqQljC
mDolX6clSXW2RKZyEu7jZ24xY53ntxPP0S9TDivvxNJ5GYvGLqUm/j3Tejz0I9qg
lCQrx47U6nwhRcD86gW6PZU57x08w5yH+s1cCIIO9yKIB86Hu7UoW69zbtJTQANW
2QIDAQAB
-----END PUBLIC KEY-----
```

SHA-256 fingerprint：

```text
aba7ea13c8829866703aa87f63b29649eb28c0d4be348383cb458e883598fae1
```

---

# 23. 固件 AES 解密方式

已确认：

```text
AES-256
OFB
NoPadding
```

key：

```text
UTF8(UUID.remove("-"))
```

IV：

```text
16 bytes 全 0
```

即：

```text
00000000000000000000000000000000
```

所以：

```text
AES/OFB/NoPadding
```

---

# 24. `restoreKey()`

断线恢复时：

```text
restoreKey(uuidStr)
```

实际：

```text
keyStr = uuidStr
key = UTF8(uuidStr.remove("-"))
```

因此：

> OTA session 必须保存原始 `keyStr`。

不能在设备重连后重新调用：

```text
createEncryptKey()
```

否则新 key 无法解密之前已经下载的 firmware。

---

# 25. YMOBD 固件检查 API

请求参数：

```text
deviceType
protocolType
obdFirmwareVersion
```

其中：

```text
deviceType = obdModel
```

```text
protocolType = 9
```

特殊情况：

```text
ATI 包含 "v2.1"
↓
protocolType = 7
```

当前版本：

```text
obdFirmwareVersion
```

来自 `AT+VERSION` 的 version。

API：

```text
getFirmwareLastVersionInfo
```

返回中重要字段：

```text
firmwareVersion
firmwareDesc
firmwareFileUUID
```

如果：

```text
server firmwareVersion > current version
```

显示新固件。

---

# 26. 固件下载 API

流程：

```text
createEncryptKey
↓
encryptKey
↓
getFirmwareFile
```

URL：

```text
/ymobd/client/getFirmwareFile
?firmwareFileUUID=<UUID>
&encryptKey=<encryptKey>
```

下载得到的 `.bin`：

```text
仍然是 AES 加密状态
```

不能直接给 Jieli OTA SDK。

必须：

```text
OTASecret.decryptFirmwareFile
↓
AES-256/OFB/NoPadding
↓
plain Jieli firmware bytes
```

再：

```text
BluetoothOTAConfigure.setFirmwareFileData(...)
```

---

# 27. OTA 生命周期

JS / Kotlin 已确认事件：

```text
onInitCompleted
onOtaReady
onStartOTA
onProgress
onMandatoryUpgrade
onNeedReconnect
onStopOTA
onError
```

推荐 CrazyDashboard 对应：

```swift
enum PTOTAState {
    case idle
    case checking
    case downloading
    case decrypting
    case preparing
    case ready
    case verifying
    case upgrading
    case reconnecting
    case verifyingVersion
    case completed
    case failed(Error)
}
```

---

# 28. OTA 正确调用顺序

```text
普通 YMOBD FFF0 BLE
        ↓
AT+VERSION
        ↓
deviceType / version / mac / crypt
        ↓
普通 YMOBD AUTH
        ↓
checkFirmware
        ↓
createEncryptKey
        ↓
encryptKey + keyStr
        ↓
download encrypted firmware
        ↓
AES/OFB decrypt
        ↓
停止普通 OBD session
        ↓
Jieli RCSP OTA
        ↓
onOtaReady
        ↓
startOTA
        ↓
verification
        ↓
firmware transfer
        ↓
onNeedReconnect
        ↓
RCSP OTA reconnect
        ↓
continue
        ↓
onStopOTA
        ↓
设备 reboot
        ↓
重新扫描普通 FFF0 OBD
        ↓
AT+VERSION
        ↓
确认版本真的升级
```

---

# 29. 不要混淆两套认证

## 普通 YMOBD OBD AUTH

```text
AT+CRYPT
AT+SETCRYPT
crypt32
0x263D9A7E
```

用途：

```text
判断普通 YMOBD adapter 身份
```

## Jieli RCSP OTA AUTH

位于：

```text
RcspAuth
libjl_ota_auth.so
```

相关 Native：

```text
getRandomAuthData
getEncryptedAuthData
setLinkKey
```

用途：

```text
Jieli OTA / RCSP transport authentication
```

这两层完全不同。

---

# 30. `libjl_ota_auth.so`

已确认：

```text
libjl_ota_auth.so
```

包含：

```text
cd03_crc_encode
CRC16
JNI_OnLoad

nativeFilterFile

RcspAuth
setLinkKey
getRandomAuthData
getEncryptedAuthData
```

这说明 Jieli SDK 内部还包含：

- firmware filter
- CRC
- RCSP auth
- native OTA data handling

因此不要自行实现：

```text
FirmwareUpdateBlockCmd
```

除非未来有非常明确的研究需要。

---

# 31. CrazyDashboard 推荐新目录结构

建议：

```text
Global/
└── OBD/
    ├── Connector/
    │   └── PTHiddenOBDConnector.swift
    │
    ├── YMOBD/
    │   ├── PTYMOBDDevice.swift
    │   ├── PTYMOBDDeviceClassifier.swift
    │   ├── PTYMOBDAuthenticator.swift
    │   ├── PTYMOBDVersionParser.swift
    │   ├── PTYMOBDInitializer.swift
    │   ├── PTYMOBDFirmwareInfo.swift
    │   ├── PTYMOBDFirmwareAPI.swift
    │   ├── PTYMOBDFirmwareDownloader.swift
    │   └── PTYMOBDFirmwareCrypto.swift
    │
    ├── OTA/
    │   ├── PTJieliOTAManager.swift
    │   ├── PTJieliBLETransport.swift
    │   ├── PTJieliOTAReconnectManager.swift
    │   ├── PTOTAState.swift
    │   ├── PTOTAProgress.swift
    │   └── PTOTASession.swift
    │
    ├── Command/
    │   ├── PTOBDCommand.swift
    │   └── ...
    │
    ├── UDS/
    │   └── ...
    │
    └── CAN/
        └── ...
```

---

# 32. `PTHiddenOBDConnector` 应该负责什么

它只负责：

```text
CoreBluetooth
FFF0
连接/断开
characteristic discovery
notify
write
ASCII framing
>
ELM/YMOBD transport
```

不要继续把以下东西塞进去：

```text
AT+VERSION business logic
YMOBD authentication
Firmware API
RSA
AES
OTA
RCSP
firmware downloader
```

否则这个类会越来越不可维护。

---

# 33. 建议拆出 `PTYMOBDInitializer`

职责：

```text
19-step queue
retry
timeout
AUTH slot
0100 判定
```

示例：

```swift
final class PTYMOBDInitializer {

    enum State {
        case idle
        case initializing
        case authenticating
        case checkingECU
        case ready
        case failed(Error)
    }

    let queue: [PTYMOBDInitStep]
}
```

connector 只提供：

```swift
send(command:)
```

initializer 决定：

```text
下一条发什么
何时 retry
何时 fail
```

---

# 34. 建议拆出 `PTYMOBDAuthenticator`

负责：

```text
crypt32
AT+CRYPT
AT+SETCRYPT
challenge
response verify
isOfficial
```

## 34.1 P1 已落地的兼容迁移边界

P1 已按“策略服务 + 旧连接器兼容门面”的方式完成。新增文件位于：

```text
Global/OBD/YMOBD/
├── PTYMOBDInitializer.swift
├── PTYMOBDVersionParser.swift
├── PTYMOBDAuthenticator.swift
├── PTYMOBDDeviceClassifier.swift
└── PTOBDPollingProfile.swift
```

本轮没有移动或重写 `PTHiddenOBDConnector` 的 CoreBluetooth、ASCII 分帧、连接发现和收发路径。旧连接器仍负责调用顺序和兼容 API，但已将版本解析、认证生成/校验、0100 重试策略、设备筛选和轮询队列策略委托给上述类型。普通 ELM327 只返回版本信息时仍会跳过 YMOBD 认证；FFF0 只是优先识别线索，不会成为全局扫描硬过滤。

`PTOBDPollingProfile.adaptive` 是默认值，保持现有产品轮询顺序；`officialYMOBD` 只供协议复现和兼容性测试主动选择。OTA、固件下载、RCSP 和写入逻辑不属于本次 P1。

接口建议：

```swift
struct PTYMOBDAuthResult {
    let command: String
    let challenge: UInt32?
}

func makeAuthCommand(
    versionInfo: PTYMOBDVersionInfo
) -> PTYMOBDAuthResult
```

以及：

```swift
func verify(
    command: String,
    response: String,
    challenge: UInt32?
) -> Bool
```

---

# 35. `PTYMOBDFirmwareCrypto`

职责：

```text
UUID key
RSA encryption
AES/OFB decrypt
```

API：

```swift
struct PTYMOBDFirmwareSecret {
    let keyString: String
    let encryptKey: String
    let publicKeyVersion: Int
}
```

```swift
func createSecret() throws -> PTYMOBDFirmwareSecret
```

```swift
func decryptFirmware(
    encryptedData: Data,
    keyString: String
) throws -> Data
```

注意 iOS CommonCrypto / CryptoKit：

> CryptoKit 本身不直接提供 AES-OFB。

可能需要：

- CommonCrypto
- OpenSSL
- CryptoSwift

优先根据 CrazyDashboard 当前依赖策略决定。

---

# 36. OTA Session 必须持久保存

OTA 开始后至少保存：

```text
deviceMac
deviceModel
oldFirmwareVersion

firmwareFileUUID
firmwareVersion

keyStr

encryptedFilePath
decryptedFilePath

OTA progress
OTA state
```

建议：

```swift
struct PTOTASession: Codable {
    ...
}
```

因为：

```text
onNeedReconnect
```

可能发生在 OTA 中途。

---

# 37. OTA 第一阶段不要直接刷真机

建议实现顺序：

## P0

修普通 OBD / YMOBD 初始化。

## P1

完成：

```text
firmware check
```

但不下载。

## P2

完成：

```text
createEncryptKey
download
decrypt
```

但不：

```text
startOTA
```

验证：

```text
AES 解密后的 firmware
```

是否能被 Jieli SDK识别。

## P3

使用备用 YMOBD 适配器：

```text
startOTA
```

## P4

确认：

```text
onNeedReconnect
reconnect
onStopOTA
```

## P5

OTA 完成后重新：

```text
AT+VERSION
```

只有版本确实变化才显示：

```text
升级成功
```

---

# 38. 推荐优先级

## P0：立即修改

- [x] 修 `<AUTH>` 覆盖 `ATRV`
- [x] `AT+VERSION` 无空格字段
- [x] 保存 `AT+CRYPT` challenge
- [x] 校验 challenge response
- [x] 增加 `isOfficialYMOBD`
- [x] `0100 UNABLE TO CONNECT`
- [x] `AT+DEBUG_FLG`（仅 YMOBD 能力探测成功后）
- [x] `0100 NO DATA`
- [x] init command 20s timeout
- [x] 0100 non-zero success condition
- [x] FFF0 优先校验，同时保留通用 ELM327 扫描
- [x] 30s BLE scan timeout
- [x] service discovery timeout
- [x] abnormal disconnect reconnect
- [x] 新设备名 whitelist 与非 OBD 设备排除

## P1：结构重构

- [x] `PTYMOBDInitializer`
- [x] `PTYMOBDVersionParser`
- [x] `PTYMOBDAuthenticator`
- [x] `PTYMOBDDeviceClassifier`
- [x] `PTOBDPollingProfile`

## P2：OTA read-only

- [ ] firmware version check
- [ ] firmware metadata model
- [ ] RSA public key
- [ ] createEncryptKey
- [ ] firmware download
- [ ] AES-OFB decrypt
- [ ] firmware hash / size logging
- [ ] 不执行 OTA

## P3：Jieli OTA

- [ ] 集成官方 Jieli iOS OTA SDK
- [ ] PTJieliOTAManager
- [ ] PTJieliBLETransport
- [ ] AE00/AE01/AE02 真机确认
- [ ] RCSP AUTH
- [ ] upgrade callback
- [ ] reconnect
- [ ] retry
- [ ] cancel
- [ ] error recovery

## P4：产品化

- [ ] OTA UI
- [ ] mandatory OTA
- [ ] battery / power warning
- [ ] progress
- [ ] resume
- [ ] firmware version verify
- [ ] analytics/log export

---

# 39. 日志系统建议

建议所有 OBD / YMOBD / OTA 日志统一包含：

```text
timestamp
sessionId

BLE state
deviceName
deviceId/MAC
RSSI

serviceUUID
writeUUID
notifyUUID

command
response

retryCount
timeoutReason

obdModel
obdVersion
obdMac
custId
isOfficial

firmwareVersion
firmwareFileUUID
firmwareSize

OTA state
OTA phase
OTA progress

disconnectReason
reconnectCount
```

不要记录：

```text
完整 token
账户隐私
敏感服务器凭证
```

---

# 40. 建议新增协议日志

定义：

```swift
struct PTOBDProtocolLog {
    let timestamp: Date
    let direction: Direction
    let command: String?
    let raw: Data?
    let text: String?
}
```

这样后续可直接导出：

```text
CrazyDashboard_OBD_Session_YYYYMMDD.log
```

用于：

- 官方 App 对比
- 真机失败分析
- OTA 前后比较
- CAN / UDS 研究

---

# 41. OTA 真机安全要求

OTA 先测试：

```text
备用 YMOBD adapter
```

不要首先拿唯一可用设备测试。

必须确保：

```text
外部供电稳定
手机电量足够
App 不被系统杀死
OTA 中禁止主动断开
```

OTA 页面要禁止：

```text
多次点击 start
普通 OBD polling
同时 reconnect FFF0
同时发送 ELM command
```

否则普通 OBD transport 和 Jieli RCSP 可能互相抢 BLE。

---

# 42. OTA 失败恢复

至少设计：

```text
.downloadFailed
.decryptFailed
.otaInitFailed
.authFailed
.transferFailed
.reconnectTimeout
.deviceNotFound
.versionVerifyFailed
```

不要把：

```text
onStopOTA
```

直接等价为最终成功。

最终成功应：

```text
onStopOTA
↓
重新连接普通 YMOBD
↓
AT+VERSION
↓
newVersion == targetVersion
```

---

# 43. 待验证项目

以下内容目前建议标记为“待真机 / 更深层 DEX 验证”：

- [ ] AE01 / AE02 谁是 write、谁是 notify
- [ ] YMOBD OTA 模式广播名是否发生变化
- [ ] OTA 模式 MAC 是否变化
- [ ] iOS Jieli SDK 的 device reconnect matching 规则
- [ ] `BluetoothOTAConfigure` 所有 YMOBD 自定义参数
- [ ] Jieli RCSP `authKey` / `linkKey` 是否有 YMOBD 自定义值
- [ ] mandatory update 的服务端返回字段
- [ ] firmware 文件是否还有 Jieli 自己的二次 header/filter
- [ ] `nativeFilterFile` 在 iOS SDK 内对应实现
- [ ] firmware hash / CRC 最终由哪一层校验

---

# 44. 下一次继续开发时的推荐顺序

下一次打开 ChatGPT / Codex，可以直接让它：

```text
根据《CrazyDashboard OBD / YMOBD / Jieli OTA 优化与实现计划》
先处理 P0。
```

具体第一批建议只改：

```text
PTHiddenOBDConnector.swift
```

完成：

```text
1. AUTH slot bug
2. AT+VERSION parser
3. challenge verify
4. 0100 retry
5. init timeout
6. pid0100 success gate
7. FFF0 scan
8. reconnect
```

第一批不要同时写 OTA。

当普通 YMOBD 链路稳定后，再进行：

```text
YMOBD 模块解耦
```

最后才：

```text
Jieli OTA
```

---

# 45. 第一阶段验收标准

普通 OBD：

- [x] FFF0 设备优先校验，同时不破坏通用 ELM327 发现
- [x] 30s 后停止 scan
- [x] 连接后 10s 内找到 service
- [x] notify 开启后延迟约 1s
- [x] YMOBD 能力设备完整跑过 19-step；普通 ELM327 跳过可选 AUTH
- [x] ATRV 没有被 AUTH 覆盖
- [x] AT+VERSION 正确解析无空格和兼容空格字段
- [x] crypt challenge 能保存并验证
- [x] `0100 NO DATA` 会 retry
- [x] YMOBD 能力设备 `0100 UNABLE` 首次会触发 `AT+DEBUG_FLG`
- [x] command 无 prompt 20s 后断开
- [x] pid0100 全 0 不会进入 connected
- [x] pid0100 非全 0 才 connected
- [x] 异常 BLE disconnect 会 reconnect
- [x] 用户主动 disconnect 不 reconnect

---

# 46. OTA 第一阶段验收标准

只读 / Dry Run：

- [ ] 能拿到当前 `obdModel`
- [ ] 能拿到当前 `obdVersion`
- [ ] 能构造 firmware check request
- [ ] 能识别 protocolType 7 / 9
- [ ] 能解析 firmware metadata
- [ ] 能生成 UUID `key`
- [ ] remove `-` 后为 32 ASCII bytes
- [ ] RSA-2048 PKCS1 encrypt 成功
- [ ] `encryptKey` 是大写 HEX
- [ ] `pubKeyVer = 3`
- [ ] 能下载 encrypted firmware
- [ ] AES-256/OFB/NoPadding 解密
- [ ] IV 全 0
- [ ] decrypted firmware 非空
- [ ] 尚未调用 OTA

---

# 47. OTA 真机阶段验收标准

- [ ] Jieli SDK 初始化成功
- [ ] OTA characteristic 正确识别
- [ ] RCSP auth 成功
- [ ] onOtaReady
- [ ] startOTA
- [ ] onProgress phase 0
- [ ] onProgress phase 1
- [ ] onNeedReconnect 可恢复
- [ ] OTA offset / resume 正常
- [ ] onStopOTA
- [ ] 设备 reboot
- [ ] FFF0 再次出现
- [ ] `AT+VERSION` 可读
- [ ] target firmware version 匹配
- [ ] 普通 PID polling 恢复

---

# 48. 最终目标架构

```text
CrazyDashboard
│
├── CoreBluetooth Transport
│
├── ELM / YMOBD Transport
│
├── YMOBD Initialization
│
├── YMOBD Authentication
│
├── OBD PID / UDS / CAN
│
├── YMOBD Firmware Service
│   ├── Check
│   ├── Secret
│   ├── Download
│   └── Decrypt
│
└── Jieli RCSP OTA
    ├── Prepare
    ├── Auth
    ├── Upgrade
    ├── Progress
    ├── Reconnect
    ├── Resume
    └── Verify
```

核心原则：

> `PTHiddenOBDConnector` 是 transport，不应该继续承担所有 YMOBD business logic。

> OTA 复刻 YMOBD 的“上层流程”，底层 RCSP 优先使用 Jieli 官方 SDK，不重新发明 OTA packet protocol。

> OTA 最终成功必须以重新读取 `AT+VERSION` 并确认目标版本为准。

---

# 49. 下次给 ChatGPT / Codex 的推荐提示词

可以直接复制：

```text
请读取《CrazyDashboard OBD / YMOBD / Jieli OTA 优化与实现计划》。

现在先不要做 OTA。

先检查 CrazyDashboard 当前 Global/OBD/Function/PTHiddenOBDConnector.swift，
按照文档 P0 顺序完成：

1. 修复 AUTH slot 覆盖 ATRV
2. 修复 AT+VERSION parser
3. 保存和验证 AT+CRYPT challenge
4. 实现 0100 NO DATA / UNABLE TO CONNECT / AT+DEBUG_FLG retry
5. 给初始化命令增加 20 秒 prompt timeout
6. 只有 pid0100 mask 非全 0 才允许 isUnlocked
7. BLE scan 使用 FFF0 service filter + 30 秒 timeout
8. 补 service discovery timeout
9. 补 abnormal disconnect reconnect
10. 补齐 YMOBD normal OBD device names

要求：
- Swift + UIKit
- 不使用 SwiftUI
- 保持现有公开 API 尽可能兼容
- 先重构状态机，不要一次性修改 OTA
- 给出修改文件和理由
- 修改后逐项对照文档验收
```

---

# 50. 文档维护规则

以后如果进一步逆向得到：

```text
新 BLE UUID
新 firmware API
OTA reconnect 规则
Jieli SDK configure 参数
新的 YMOBD deviceType
firmware header
```

不要重新建另一份散乱文档。

直接追加到本文：

```text
已确认事实
待验证项目
变更记录
```

建议后续增加：

```text
## Change Log

2026-09-08
- 初版
- 整合 YMOBD BLE / init / OTA / OTASecret / Jieli RCSP
```

---

## Change Log

### 2026-09-08

初版：

- 整理 CrazyDashboard 当前 OBD 缺陷
- 整理 YMOBD 官方 19-step 初始化
- 整理 YMOBD 24-command homepage polling
- 整理 BLE FFF0 行为
- 整理 AT+CRYPT
- 整理 OTA firmware API
- 确认 Jieli `jl_bt_ota`
- 确认 `utsJieliOta`
- 确认 `OTAModule`
- 确认 `BleManager`
- 还原 `OTASecret`
- 整理 RSA / AES-OFB 参数
- 给出 CrazyDashboard 分层与实施优先级
