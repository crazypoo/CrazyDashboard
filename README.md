# CrazyDashboard / PTSpeed

Peugeot XP400 的 iOS 骑行与车辆数据工具，提供原车 BLE、ELM327/OBD、导航、骑行记录、车队对讲和 Apple 平台集成。当前发布渠道为单一的 PTSpeed TestFlight 版本。

## 当前基线

- Marketing Version：`2.0.8`
- 当前 Build：`66`
- 最低系统：iOS 17+；Apple Watch 支持 watchOS 10.6+
- Target：PTSpeed、Widget、Watch App、PTSpeedTests、UI Tests
- 稳定核心：`PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift`、`PTOBDCommand.swift`

## 能力概览

- XP400 原车 BLE 仪表、车辆状态和配置回读
- ELM327 OBD、YMOBD 扩展、只读诊断、CAN 抓包和离线回放
- 地图导航、CarPlay、停车、行程、维护和安全能力
- PTT 车队对讲、Live Activity、Widget、Apple Watch、Siri/App Intents 和通知集成
- Dev 入口中的协议 Evidence、OTA 状态和高风险实验门禁

## 文档入口

从 [`docs/README.md`](docs/README.md) 开始。常用文档：

- [`docs/product/APP_FEATURE_BLUEPRINT.md`](docs/product/APP_FEATURE_BLUEPRINT.md)：当前产品功能和状态唯一事实源
- [`docs/planning/ACTIVE_WORK.md`](docs/planning/ACTIVE_WORK.md)：当前未完成工作和验收门
- [`docs/planning/BACKLOG.md`](docs/planning/BACKLOG.md)：未排期候选功能与技术债
- [`docs/architecture/`](docs/architecture/)：系统、OBD、统一遥测架构
- [`docs/protocols/`](docs/protocols/)：XP400 BLE、YMOBD/Jieli 协议参考
- [`docs/research/`](docs/research/)：抓包、设备和协议研究日志
- [`docs/history/`](docs/history/)：年度 Build 结果和详细验收记录
- [`docs/DOCUMENTATION_POLICY.md`](docs/DOCUMENTATION_POLICY.md)：文档路由、命名、Front Matter 和生命周期规则

## 本地检查

```text
Scripts/docs_lint.sh
Scripts/generate_docs_index.py --check
```

涉及代码时，再运行对应 Build 检查和工程构建。文档、静态检查和 Mock 结果不能替代真实 iPhone、Apple Watch、OBD 或 XP400 验证。
