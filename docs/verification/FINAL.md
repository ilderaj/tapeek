# Tapeek MVP 最终验收

- 日期：2026-11-02
- 环境：macOS 27.0（26A428）/ Xcode 27.0（27A266a）/ Apple M2 / arm64
- 结论：**功能通过，交互验收部分通过**

Tapeek 已能作为本机 Quick Look 扩展运行：Markdown 以格式化文档显示，ZIP 以只读目录树显示。安装、签名、注册、预览、错误状态、限额和轻量优化都有实际证据。Finder 内按空格、宿主 App 两个按钮和 VoiceOver 仍需手动确认。

## PRD 验收标准

| 标准 | 证据 | 结论 |
| --- | --- | --- |
| Markdown 样本可读 | T02/T05 截图；T04 测试；T11 样本 | 通过 |
| ZIP 样本符合 F2 | T08、T12 截图；T06/T07 测试 | 通过 |
| 不产生解压文件、不联网 | `T12-no-write.diff` 为空；`T12-network-review.txt` 无网络调用 | 通过 |
| 超限有明确降级 | 2.1 MB 文档拒绝；25k/70k ZIP 截断提示 | 通过 |
| 宿主 App 可用 | T10 浅色/深色截图；按钮未点击 | 部分通过 |
| 全部 ticket 有证据 | 各 `Txx.md` | 通过 |

## 性能与资源

| 项 | 结果 |
| --- | --- |
| Core Markdown 解析（500 KB，Release） | 0.66 ms |
| Core ZIP 列表 + 树（20,000 条，Release） | 238–245 ms |
| Quick Look 首窗口（gfm.md） | 509 ms |
| Quick Look 首窗口（typical.zip） | 443 ms |
| Quick Look 首窗口（500 KB Markdown） | 913 ms |
| Release App / 扩展 | 2.9 MB / 2.7 MB |
| 扩展 RSS（普通 Markdown / 20k ZIP） | 约 30–82 MB |
| 扩展 RSS（500 KB Markdown） | 约 132 MB |

500 KB 文档最初一次性布局会占用约 900 MB 且 12 秒无内容；`MarkdownChunker` + `LazyVStack` 按标题/空行分块后，首窗口 913 ms、内存约 132 MB。Core 性能数字不代表 UI 首帧，表中已分开列出。

## Tickets

| ID | 状态 | 证据 |
| --- | --- | --- |
| T01 骨架与最小预览 | 完成 | `T01.md` |
| T02 MarkdownUI 探针 | 完成 | `T02.md` |
| T03 Core 基础 | 完成 | `T03.md` |
| T04 Markdown 加载 | 完成 | `T04.md` |
| T05 Markdown UI | 完成 | `T05.md` |
| T06 ZIP 读取 | 完成 | `T06.md` |
| T07 ZIP 树 | 完成 | `T07.md` |
| T08 ZIP UI | 完成 | `T08.md` |
| T09 路由与生命周期 | 完成 | `T09.md` |
| T10 宿主 App | 部分通过 | `T10.md` |
| T11 夹具与性能 | 完成 | `T11.md` |
| T12 安装与端到端 | 部分通过 | `T12.md` |
| T13 最终验收 | 完成 | 本文件 |

## 已知限制

| 限制 | 用户影响 | 后续 |
| --- | --- | --- |
| 同目录图片被沙盒拒绝 | Markdown 显示图片占位和 alt，正文可读 | 不放宽沙盒；未来评估授权书签 |
| 旧式 ZIP 文件名编码 | GBK 等靠启发式识别，可能误判 | 增加更多编码样本 |
| 加密 ZIP | 只列目录，不能读取内容 | 首版不支持密码 |
| 分卷 ZIP / RAR / 7z / TAR | 不支持 | 后续按格式评估 |
| 自解压 ZIP64 | 暂不支持 | 后续实现前缀偏移 |
| 超过 2 MiB Markdown | 拒绝预览 | 用户可拆分或用编辑器 |
| 超过 20,000 条 ZIP | 只显示前 20,000 条并提示 | 后续分页/搜索 |
| 500 KB Markdown 内存 132 MB | 大文档仍有布局开销 | 观察日常使用，必要时再优化 |
| Finder 空格、宿主按钮、VoiceOver | 自动化权限受限，未实际点击 | 用户手动确认 |

## 环境问题

会话中三次出现「环境切到 Linux」的报告。经 transcript 和 Magpie 配置核查，根因是 `group/thinker` 命中 remote-magpie 的 VPS Claude Code 进程，该进程注入了 Linux 环境说明；实际 Bash 工具仍转回 Mac 执行。工具实测始终是 `/Users/jared/Personal Projects/Tapeek`、Darwin、uid 501。后续以同一执行上下文的 `pwd; uname -s; id -u` 为准。

## 交付物

- App：`~/Applications/Tapeek.app`
- 源码：`/Users/jared/Personal Projects/Tapeek`
- 测试：`./scripts/run-tests.sh`（60 项 Core 测试）
- 安装：`./scripts/install-local.sh`
- 卸载：`./scripts/uninstall-local.sh`
- 文档：`README.md`、`docs/PRD.md`、`docs/impl-plan.md`、`docs/specs/`、`docs/tickets/`
