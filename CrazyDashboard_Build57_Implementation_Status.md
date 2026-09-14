# Build 57 — OBD Architecture 2.0 V2 实施状态

基于 `CrazyDashboard_Build57_60_Upgrade_Plan_V2_2026-09-14.md`。本记录只描述仓库内已实施的 Build 57 范围，不替代原计划。

## 已完成

- [x] B57-01：加入 ELM、PID、YMOBD、UDS、CAN 冻结夹具。
- [x] B57-02：加入字节级 `PTOBDTransport` 协议和传输错误模型。
- [x] B57-03：加入 BLE/Wi-Fi 旧连接器兼容桥接，以及离线 `PTOBDMockTransport`。
- [x] B57-04：加入 `PTELM327Session`、状态机、Prompt 解析和监听分流。
- [x] B57-05：加入单队列串行化、优先级、取消、超时和 flush。
- [x] B57-06：加入 Vendor Extension 协议和注册/探测/激活 Registry。
- [x] B57-07：加入基于同一 ELM Session 的 `PTYMOBDVendorExtension` 和 YMOBD capability。
- [x] B57-08：加入 `PTOBDBusCoordinator`，复用现有 `PTOBDBusLease`。
- [x] B57-09：加入普通 ELM 到 Jieli OTA 的适配器模式协调与失败恢复判断。
- [x] B57-10：加入 `PTJieliSDKBridge`，保持官方 Jieli SDK 2.5.0 为唯一 RCSP 实现。
- [x] B57-11：加入独立的 V2 命令分类和 Adapter Maintenance 分类。
- [x] B57-12：加入可选兼容门面；未接入新 Session 时仍走原有稳定管理器。
- [x] B57-13：加入统一 OBD/YMOBD/OTA 会话标识和有界事件追踪。

## 有意保留的边界

- `PTHiddenOBDConnector.swift` 未修改，仍是通用 ELM327 CoreBluetooth 物理连接和既有状态机的唯一拥有者。
- `PTOBDCommand.swift`、`PTBluetoothManager.swift` 未修改。
- 新架构通过兼容桥接和可选 Session 接入，不在 Build 57 引入第二套 CoreBluetooth 或 ELM 物理写入器。
- 高风险 OTA 仍要求开发者安全开关和显式确认；静态测试不等同于真实车辆 OTA 验证。

## 本次验证

- [x] 所有 Build 57 新增 Swift 源文件通过语法解析。
- [x] ELM327 Session、Prompt Parser、Command Queue、Monitor、Bus Coordinator 和 Session Trace 通过 Swift 6 完整并发检查及 Swift 5 / iOS 17 目标类型检查。
- [x] `CrazyDashboard.xcodeproj/project.pbxproj` 通过 plist 语法检查，Git 空白检查通过。
- [x] 测试夹具使用真实分行文本，测试会从测试 Bundle 读取 PID、UDS 和 YMOBD 夹具。
- [ ] 完整 `xcodebuild`：当前 Xcode 构建服务卡在仓库既有 Pods 编译阶段，未得到 `BUILD SUCCEEDED`；这不作为新增业务源码通过完整构建的证据。
