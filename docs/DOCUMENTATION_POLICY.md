---
doc_id: CD-POLICY-001
title: Documentation Policy
type: policy
status: active
canonical: true
domain: documentation-policy
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds: []
supersedes: []
superseded_by:
---

# CrazyDashboard 文档治理策略

本文是仓库 Markdown 的可执行规则。`docs/README.md` 是自动生成的索引；产品现状以产品总纲为准，当前工作以 Active Work 为准，历史结果和研究证据不得重新当作待办计划。

## 文档路由

| 内容 | 唯一入口 | 规则 |
| --- | --- | --- |
| 产品功能、入口、平台和状态 | [`product/APP_FEATURE_BLUEPRINT.md`](product/APP_FEATURE_BLUEPRINT.md) | 当前产品事实源 |
| 当前 1–3 个 Build 的工作 | [`planning/ACTIVE_WORK.md`](planning/ACTIVE_WORK.md) | 只放未完成工作、验收门和回滚点 |
| 未排期想法、技术债和候选项 | [`planning/BACKLOG.md`](planning/BACKLOG.md) | 不承诺交付时间 |
| 系统、OBD、遥测架构 | [`architecture/`](architecture/) | 记录稳定边界和数据流，不记录一次性任务清单 |
| XP400 BLE / YMOBD/Jieli 协议参考 | [`protocols/`](protocols/) | 只记录协议事实、证据等级和安全边界 |
| 抓包、解析和设备观察 | [`research/`](research/) | 滚动追加，区分 confirmed / inferred / unknown |
| 已完成 Build 的结果 | [`history/BUILD_HISTORY_2026.md`](history/BUILD_HISTORY_2026.md) | 一年一份索引，必要时链接详细验收记录 |
| 退役路线图、迁移表和旧状态记录 | [`archive/`](archive/) | 只修元数据和断链，不继续改正文 |

`PTSpeedTests/ReplayFixtures/README.md` 是测试夹具旁的局部说明，保留在夹具目录中；它不是项目级文档入口，项目级索引不把它当作 canonical 文档。

## 根目录规则

根目录只保留 `README.md`。新的 Markdown 必须先找到上表中的 canonical 入口；普通 Build 不得单独创建根目录计划文件。若确实需要独立文档，必须满足至少两个条件：跨三个以上模块、有独立生命周期或审计需要、需要独立回滚矩阵、超过约 500 行且不能自然放入 canonical 文档，或需要独立对外交付。

## Front Matter

`docs/` 下除 `docs/README.md` 外的每份文档都必须有以下元数据：

```yaml
---
doc_id: CD-EXAMPLE-001
title: Example Document
type: architecture
status: active
canonical: true
domain: example
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds: []
supersedes: []
superseded_by:
---
```

允许的 `type`：`product`、`planning`、`architecture`、`protocol`、`research`、`history`、`archive`、`policy`。

允许的 `status`：`draft`、`active`、`stable`、`superseded`、`archived`。同一个 `domain` 只能有一份 `canonical: true` 文档。

## 命名与生命周期

- canonical 文件名使用职责名，不使用仓库名前缀，也不使用 `V2`、`V3`、`FINAL`、`NEW`、`LATEST`、`COPY` 或“新版/最终版”。
- Build 完成后，从 Active Work 提取结果到年度 History，并同步产品、架构、协议或研究文档；不继续在旧路线图追加任务。
- 归档文档保留原正文，Front Matter 标记 `status: archived`、`archived_at` 和 `superseded_by`，正文顶部必须出现“Archived ... must not be used as the current implementation plan.”警告。
- 功能 ID 永不复用；删除功能时在产品总纲标为 `🗑️ 已退役`。

## 每次变更的最小事务

1. 更新一个 canonical 文档或明确移动到正确的职责目录。
2. 同步交叉链接、Build History 和产品状态。
3. 若改变协议/安全边界，补充证据等级、验证层级和回滚说明。
4. 运行 `Scripts/docs_lint.sh` 和 `Scripts/generate_docs_index.py --check`。
5. 代码变更另行执行对应 Build 检查；文档检查不能替代编译、真机或实车验收。

## 研究与高风险规则

协议文档必须同时写明：当前实现、自动化测试和真车证据。未知字段、Seed-Key、刷写、SecurityAccess、CAN injection 和固件实验只能进入研究或 Dev 边界，不能因为日志、Mock 或静态编译通过就提升为产品能力。

## 自动门禁

本地执行：

```text
Scripts/docs_lint.sh
Scripts/generate_docs_index.py --check
```

Pull Request 中只要修改 Markdown、文档脚本或本策略，就由 `.github/workflows/docs-governance.yml` 自动执行这两项检查。检查失败时先修复路径、元数据或索引，再提交代码。

