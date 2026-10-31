# T13 最终验收与交付

| 项 | 内容 |
| --- | --- |
| ID | T13 |
| 状态 | 待开始 |
| 依赖 | T12 |
| 执行角色 | thinker 主导验收；executor 补证据 |
| 预计产物 | `FINAL.md`、README、已知限制、tickets 状态 |

## 必读

- [PRD](../PRD.md) §8、§9、§10。
- [实施计划](../impl-plan.md) §14、§16。
- 所有 `docs/verification/Txx.md`。
- [tickets 索引](README.md)。

## 目标

确认 MVP 是否真正达到 PRD 的验收标准，整理证据和已知限制，给用户一个可直接使用的本机 App 和清晰的后续入口。此 ticket 不新增功能。

## 允许改动

- `docs/verification/FINAL.md`
- `README.md`
- `docs/PRD.md`（只改状态、已知限制和后续规划，不改需求结论）
- `docs/tickets/README.md`（只改状态表）
- 各 `docs/tickets/Txx.md`（只改状态和交接，不改范围）
- `docs/verification/T13-*.txt`（命令输出）

## 禁止改动

- 不修改 App 代码、扩展声明、解析逻辑或 UI。
- 不为了让验收通过而降低标准、删除用例或隐藏失败。
- 不把「环境阻塞」写成「功能通过」。
- 不新增功能或格式。

## 前置检查

```sh
./scripts/run-tests.sh
./scripts/build.sh
./scripts/verify-extension.sh
```

三项都必须成功。若失败，回到对应 ticket，T13 不开始。

## 步骤

### 1. 复核 PRD 验收标准

逐条检查 [PRD](../PRD.md) §8：

| 标准 | 需要的证据 |
| --- | --- |
| Markdown 样本可读 | MD-001 至 MD-022 的截图与记录 |
| ZIP 样本符合 F2 | ZIP-001 至 ZIP-025 的截图与记录 |
| 不产生解压文件、不联网 | ZIP-022、QL-010、QL-011、`T12-no-write.txt`、`T12-network-review.txt` |
| 超限有明确降级 | MD-010、ZIP-009、ZIP-021 |
| 宿主 App 可用 | APP-001 至 APP-010 |
| 全部 ticket 有证据 | 每个 `Txx.md` 有结论 |

任何一项没有证据，标记「未通过」或「未验证」，不写「应该没问题」。

### 2. 复核 tickets

打开 [tickets 索引](README.md)，逐项检查：

- 状态是否为「完成」。
- 对应 `docs/verification/Txx.md` 是否存在。
- 验收项是否有命令输出或截图。
- 是否有未关闭的阻塞。

未完成的 ticket 不能通过 T13 的汇总「假装完成」。在 `FINAL.md` 列出未完成项和影响。

### 3. 整理已知限制

至少列出：

- 相对图片在沙盒中可能不可读，只能显示占位。
- 旧式 ZIP 文件名编码只能启发式识别，可能显示错误。
- 加密 ZIP 只列目录，不能预览内容。
- 不支持分卷 ZIP、RAR、7z、TAR。
- 自解压 ZIP64 暂不支持。
- 超过 20,000 条或 16 MiB 目录区的 ZIP 只显示部分。
- Markdown 不支持语法高亮、公式、Mermaid、脚注跳转、文内搜索。
- 超 2 MiB 的 Markdown 直接拒绝。
- ad-hoc 签名可能受系统缓存或签名要求变化影响。
- 系统可能选择其他 Quick Look 扩展；Tapeek 不承诺覆盖。

每条限制写：

- 用户会看到什么。
- 为什么首版不解决。
- 是否有后续计划。

不要写「后续优化」这种没有动作的空话；写具体方向或明确不做。

### 4. 更新 README

`README.md` 至少包含：

- 项目一句话说明。
- 当前状态：MVP 自用版，支持 macOS 27 arm64。
- 安装：

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
```

- 启用：系统设置 → 通用 → 登录项与扩展 → Quick Look → 启用 Tapeek。
- 使用：Finder 选中 `.md` 或 `.zip`，按空格。
- 测试：`./scripts/run-tests.sh`。
- 卸载：`./scripts/uninstall-local.sh`。
- 已知限制的链接。
- 文档地图：PRD、实施计划、规格、tickets、验收。

要求：

- 命令可复制执行。
- 不使用绝对个人路径；用仓库根目录相对路径。
- 不夸大能力。

### 5. 清理

- 确认 `.build/`、`DerivedData/`、`xcuserdata/` 未提交。
- 确认没有临时截图、日志、测试 ZIP 散落在仓库根目录。
- 确认没有密钥、证书、账号、token 写入文件。
- 确认 `docs/verification/` 只包含需要的证据。
- 确认没有 `TODO`、`FIXME`、`TBD` 留在用户可见文案或验收结论中；代码中的内部 TODO 必须列在 `FINAL.md`。

### 6. 写 FINAL.md

结构：

```markdown
# Tapeek MVP 最终验收

- 日期：
- 环境：
- 结论：通过 / 部分通过 / 阻塞

## PRD 验收标准
| 标准 | 证据 | 结论 |

## Tickets
| ID | 状态 | 证据 |

## 已知限制
| 限制 | 用户影响 | 后续 |

## 环境阻塞
| 项 | 现象 | 处理 |

## 未验证项
| 项 | 原因 | 下一步 |

## 交付物
- App 路径
- 文档路径
- 测试命令
```

结论规则：

- 所有 PRD 标准通过 → 「通过」。
- 有功能项失败 → 「部分通过」，列出失败项，不得声称 MVP 完成。
- 扩展无法注册或被系统忽略 → 「阻塞」，不把原因归咎于用户环境而不解决。

### 7. 更新状态

- tickets 索引的状态与实际一致。
- PRD 的状态改为「MVP 已验收」或「部分验收」，并写明日期。
- 不在 PRD 中删掉未实现的排除项。

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| 测试 | `./scripts/run-tests.sh` | 0 失败 |
| 构建 | `./scripts/build.sh` | 退出码 0 |
| 扩展 | `./scripts/verify-extension.sh` | 扩展存在，签名通过 |
| PRD 标准 | 逐条对照 | 每项有证据或明确未通过 |
| Tickets | 逐项对照 | 状态与证据一致 |
| 已知限制 | 阅读 `FINAL.md` | 具体、可理解、无空话 |
| README | 按步骤执行 | 新环境可按文档安装和启用 |
| 清理 | 目录检查 | 无临时文件、密钥、构建产物 |

## 证据

- `docs/verification/FINAL.md`。
- `README.md`。
- 最终测试、构建、扩展检查的命令输出。

## 停止条件

- 任一 PRD 验收标准失败且无法在 MVP 内修复 → 结论写「部分通过」，不继续包装。
- 发现需求与实现矛盾 → 回到 PRD 和用户确认，不自行改需求。
- 需要新增功能才能通过 → 新建 ticket，不塞进 T13。
- 无法确认证据真实性 → 标记未验证。

## 交接

给用户：

- 可运行的 App 路径。
- 启用与使用步骤。
- 验收结论与已知限制。
- 后续可选方向。
