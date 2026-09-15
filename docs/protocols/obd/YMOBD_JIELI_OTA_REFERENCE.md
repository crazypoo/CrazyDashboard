---
doc_id: CD-PROTOCOL-OBD-001
title: YMOBD Jieli OTA Reference
type: protocol
status: stable
canonical: true
domain: ymobd-jieli-ota
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 57
  - 65
supersedes: []
superseded_by:
---

# YMOBD / Jieli OTA 参考

## 核心边界

`PTHiddenOBDConnector` 是通用 ELM327 的底层连接；YMOBD 是在 ELM 会话上识别和启用的厂商扩展。Jieli RCSP OTA 是 YMOBD 适配器维护模式，不是 XP400 仪表 BLE，也不是标准 PID/UDS 的替代路径。

```text
ELM327 transport
  → YMOBD version / capability / ordinary auth
  → firmware metadata and download
  → stop ordinary OBD session
  → official Jieli iOS SDK / RCSP OTA
  → reconnect and AT+VERSION verification
```

## 已记录的协议知识

- YMOBD 初始化包括 `AT+VERSION`、`AT+CRYPT`/`AT+SETCRYPT`、基础 ELM 命令和 `0100` 能力确认；连接成功不能只由 BLE 发现或单次命令成功推断。
- `AT+VERSION` 可能使用 `devicename`、`devicetype`、`version`、`devicemac`、`custid`、`crypt` 等无空格字段；解析器应兼容历史空格形式。
- 普通 YMOBD AUTH 与 Jieli RCSP OTA AUTH 是两套不同的认证，不能混用。
- Jieli iOS OTA SDK `2.5.0` 由 `PTJieliSDKBridge` 接入，官方 `JL_OTALib` 负责 RCSP、CRC、分块、认证、断点和恢复；App 不复制这些协议。
- 固件服务使用 `https://ymobd.com`；检查和下载的请求契约由 `PTYMOBDFirmwareAPI` 保持，下载参数包含服务要求的 firmware UUID 和加密密钥。

## OTA 状态与安全

OTA 适配器必须保留会话 ID、目标版本、文件校验、阶段、进度、取消/失败原因和重连状态。开始前必须完成 YMOBD 身份、固件元数据、稳定供电、开发者安全开关和显式确认；后台、断开、开发者门禁撤销或 SDK 失败时安全停止并恢复普通 OBD 状态。完成的唯一依据是设备重连后再次读取 `AT+VERSION` 并确认目标版本。

普通产品入口禁止：

- SecurityAccess、未知 UDS 写入、任意 CAN injection；
- 自行实现 Jieli RCSP 分包、CRC、认证或固件解密；
- 未有 Bootloader/ACK/断点/回滚证据时刷写 XP400 仪表或 ECU；
- 把模拟成功、日志或下载完成当成设备升级成功。

## 证据等级

| 等级 | 含义 |
| --- | --- |
| Confirmed | 当前源码、官方 SDK/API 契约或可复现样本直接支持 |
| Inferred | 多份研究资料一致，但尚未由目标适配器/车辆完整确认 |
| Unknown | 需要真实硬件、抓包或 SDK 运行时验证 |

当前 `PTJieliSDKBridge`、状态机和请求构造有静态/离线测试；真实 YMOBD OTA、模式广播名/MAC、AE00/AE01/AE02 行为、设备重连匹配和固件兼容性仍是 Unknown。任何新发现写入 [`OBD_DATA_DISCOVERY_LOG.md`](../../research/OBD_DATA_DISCOVERY_LOG.md)，并保留来源、设备和原始证据位置。

历史长计划仅作研究背景：[`CrazyDashboard_OBD_YMOBD_Jieli_OTA_Optimization_Plan.md`](../../archive/roadmaps/CrazyDashboard_OBD_YMOBD_Jieli_OTA_Optimization_Plan.md)。

