# Tapeek

Tapeek 是一个 macOS Quick Look 预览增强工具：在 Finder 中选中 Markdown 或 ZIP 文件，按空格即可阅读排版后的文档或浏览压缩包目录，不需要打开编辑器或先解压。

当前状态：**需求、实施计划、规格与执行 tickets 已完成，尚未生成工程或实现功能。**

## 范围

MVP 只包含两项能力：

- Markdown：渲染项目 README 和技术笔记常见的 GFM 语法，支持 front matter、图片占位、明暗模式。
- ZIP：只读 central directory，显示目录树、文件大小、摘要和异常提示，不解压、不写入磁盘。

第一版面向当前 macOS 27 arm64 的个人使用，不做公开分发、App Store、Intel 兼容或 Markdown 编辑。

## 文档

| 文档 | 内容 |
| --- | --- |
| [PRD](docs/PRD.md) | 产品目标、范围、功能需求、验收标准和后续方向 |
| [实施计划](docs/impl-plan.md) | 架构、工程配置、构建命令、技术探针、Core 契约、风险与完成定义 |
| [功能规格](docs/specs/README.md) | Markdown、ZIP、Quick Look 集成、宿主 App、测试与夹具 |
| [执行 tickets](docs/tickets/README.md) | 按依赖排序的可执行任务、允许改动范围、验收与证据 |
| [验收记录](docs/verification/README.md) | 每个 ticket 的截图、命令输出和结论 |

## 实施顺序

1. T01：骨架、签名与最小预览。
2. T02 与 T03：MarkdownUI 探针、Core 基础。
3. T04/T05：Markdown 加载与预览。
4. T06/T07/T08：ZIP 解析、树模型与预览。
5. T09：路由与生命周期。
6. T10：宿主 App。
7. T11/T12/T13：夹具、性能、端到端验收与最终交付。

完整依赖图见 [tickets 索引](docs/tickets/README.md)。

## 计划中的本机命令

以下命令在实施完成后使用，当前尚未生成对应脚本：

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

启用方式：系统设置 → 通用 → 登录项与扩展 → Quick Look → 启用 Tapeek。然后在 Finder 中选中 `.md` 或 `.zip`，按空格。

测试：

```sh
./scripts/run-tests.sh
```

卸载：

```sh
./scripts/uninstall-local.sh
```

## 设计约束

- 预览扩展沙盒运行，默认只保证被预览文件的读取权限。
- 不联网、不上传文件、不写入用户目录、不创建解压产物。
- 同目录图片可能被沙盒拒绝，按占位处理，不通过放宽权限绕过。
- 系统可能选择其他 Quick Look 扩展，Tapeek 不承诺覆盖。
- 超过限额的输入显示明确错误或截断提示，不静默省略。
