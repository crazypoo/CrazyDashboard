---
doc_id: CD-HISTORY-BUILD-084-PIT-WALL-001
title: Build 84 Pit Wall
type: history
status: draft
canonical: false
domain: build-084-pit-wall
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
  - 77
  - 78
  - 79
  - 80
  - 81
  - 82
  - 83
  - 84
supersedes: []
superseded_by:
---

# Build 84 — Pit Wall / 第二屏

## 范围

Build 84 将 iPhone 上已经存在的只读 XP400/OBD 统一遥测投影到同一局域网中的 Mac、iPad 或浏览器。第一版不增加 Web 3D，而是提供简化 2D Twin、Live Map、Telemetry、Speed/RPM rolling chart 和安全事件流。

```text
iPhone XP400 / OBD
        ↓
PTUnifiedVehicleTelemetrySnapshot
        ↓
PTVehicleTwinStateMapper
        ↓
bounded privacy-filtered snapshot
        ↓
LAN-only GET server + Bonjour
        ↓
Mac / iPad / browser Pit Wall
```

## 工作包状态

| 工作包 | 状态 | 实施内容 | 验收边界 |
| --- | --- | --- | --- |
| B84-01 | ✅ | 新增 `PTPitWallEnabled`，设置页加入 Pit Wall 开关；默认关闭 | 不因安装、启动或连接车辆自动启动 |
| B84-02 | ✅ | `NWListener` TCP server，仅绑定 Wi-Fi，GET-only allow-list | 没有 POST、写入、命令、OTA 或 SecurityAccess 路由 |
| B84-03 | ✅ | 发布 `_pt-pitwall._tcp` Bonjour service，并生成临时 IPv4 配对 URL | Token 不放入 Bonjour TXT；需要同一局域网 |
| B84-04 | ✅ | 24 字节随机 Token，内存保存，设置页展示/分享 | 停止服务、场景失活或进程结束后失效；不落盘 |
| B84-05 | ✅ | `PTPitWallSnapshot`、schema version、ISO8601/排序 JSON、有界样本与事件 | 坐标舍入；不序列化 VIN、UUID、原始 Hex、诊断错误或协议载荷 |
| B84-06 | ✅ | 内置无第三方依赖的 HTML/CSS/JavaScript Web UI | CSP 只允许页面自身的 inline style/script 与本地 API |
| B84-07 | ✅ | SVG/CSS 简化 2D Twin 与 Canvas Live Map | 不替代 iPhone Twin；第一版不实现 Web 3D |
| B84-08 | ✅ | 60 点滚动样本、Speed/RPM chart、事件流 | 内存有界，不保存浏览器历史或车辆档案 |
| B84-09 | ✅ | scene active 生命周期、Consumer 注册/注销、停止时清空 Token/缓存 | 不在后台继续占用遥测租约 |
| B84-10 | 🟨 | HTTP、Token、隐私字段和 Web UI 边界测试已接入 | 已有编译证据；真实局域网、权限、断网和 Release/TestFlight 待验 |

## 安全和隐私边界

- 服务默认关闭，只有用户在设置页打开后才可能启动。
- 监听器只允许 Wi-Fi 接口，且只接受 HTTP/1.1 `GET`。
- 允许路径只有 `/`、`/api/snapshot` 和 `/api/events`。
- 所有请求都必须带当前内存 Token；未授权返回 `401`，未知路径不会提供数据。
- Snapshot 只包含显示 Pit Wall 所需的连接状态、上下文、速度、转速、燃油、电压、倾角、TCS/ABS/边撑/发动机状态、有限坐标、rolling samples 和安全状态事件。
- 不暴露 VIN、Central UUID、蓝牙标识、原始 BLE/ELM327/UDS Hex、错误堆栈、诊断原文、写入命令或固件资料。
- 不新增 BLE 写入、ELM327 写入、YMOBD 写入、CAN 注入、OTA、SecurityAccess 或车辆控制接口。

## 代码边界

- `PTPitWallManager` 是 `@MainActor` 生命周期协调器，只消费 `PTVehicleTelemetryConsumerHub` 的既有统一快照。
- `PTVehicleTwinStateMapper` 仍是唯一的 Twin 映射入口；Pit Wall 不直接读取 `PTBluetoothManager`、`PTHiddenOBDConnector` 或 `PTOBDCommand`。
- `PTPitWallSnapshotSerializer` 是浏览器数据出口，使用有界模型和隐私裁剪，不复用带有协议原文的研究事件模型。
- `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift` 保持零字节变化；ELM327/YMOBD 连接、初始化、握手、能力识别、命令顺序、轮询和 fallback 未改。
- 设置页使用既有 `PTMotoBaseViewController` 体系；没有创建新的车辆连接或后台采集管线。

## 测试与构建证据

已完成：

- `PTPitWallBuild84Tests.swift` 已接入 `PTSpeedTests`，覆盖：
  - rolling series 的最大长度和最新样本保留；
  - GET、HTTP/1.1、Token header 大小写归一化；
  - POST、未知路径、过大请求拒绝；
  - Snapshot 坐标/数值裁剪；
  - JSON 不包含 `VIN`、`centralIdentifier`、`rawHex`、`errorMessage`；
  - Web UI CSP、只访问本地 API、无外部脚本；
  - HTTP Content-Length、`no-store` 和 `Connection: close`。
- 主 App workspace Debug generic iOS `build`：`BUILD SUCCEEDED`。
- 主 App workspace Debug generic iOS `build-for-testing`：`TEST BUILD SUCCEEDED`。
- Xcode project、Info.plist、InfoPlist.xcstrings 和文档 JSON/索引静态校验已执行。
- 稳定核心 SHA-256 保持 Build 83 基线：
  - `PTBluetoothManager.swift`: `841abfbab70f6c199c3130b68c8f55f42104684e6f6ea39a11ad3215c7b676e4`
  - `PTHiddenOBDConnector.swift`: `21a3657de6c7bfd4ac4e40883fc14ec45aabed168376629e15a2e2573a4632d1`
  - `PTOBDCommand.swift`: `7e61b4961427c087d9ce36769973e71230f9a4c99892fbe71fb911b400633b66`

当前不能替代现场验收：

- 本机 Xcode Scheme 没有可用的具体 iOS Simulator destination，XCTest 尚未在模拟器执行。
- 通用 iOS Simulator 构建仍会遇到仓库既有 Watch App `AppIcon` 素材错误；该错误不来自 Pit Wall 源码。
- 需要真实 iPhone、Mac/iPad/浏览器和同一 Wi-Fi，验证 Local Network 授权、Bonjour 发现、Token 配对、刷新频率、断网、切后台/恢复、停止服务后 Token 失效和多客户端只读访问。
- 需要 Release/TestFlight 包、不同 iOS 版本、长时间运行的 Energy/Memory/Network Instruments 和权限拒绝矩阵。

## 回滚

- 用户关闭设置中的 Pit Wall 开关即可停止 listener、撤销 telemetry consumer、停止 Dashboard context 观察并清空 Token/缓存。
- 代码回滚只需移除 `Global/PTPitWall/`、`PTPitWallBuild84Tests.swift`、设置入口、Scene lifecycle、Bonjour/本地网络配置和 Build 84 文档，不需要迁移或删除车辆、OBD、BLE、行程、iCloud 或协议证据数据。
- 不修改三个稳定 BLE/OBD 核心来处理 Pit Wall 的兼容或网络问题。
