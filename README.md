# Tapeek

Tapeek 是一个 macOS Quick Look 预览增强工具：在 Finder 中选中 Markdown 或 ZIP 文件，按空格即可阅读排版后的文档或浏览压缩包目录，不需要打开编辑器或先解压。

当前状态：**MVP 已实现并安装在本机**。Finder 空格和宿主 App 两个按钮已手动确认；VoiceOver/窄窗口留待后续自动化。详细结论见 [FINAL.md](docs/verification/FINAL.md)。

## 能力

- Markdown：GFM 标题、列表、任务列表、表格、代码块、引用、front matter 卡片、图片占位、浅色/深色模式、长文档分块懒加载。
- ZIP：不解压查看目录树、文件大小、摘要、加密标记、空包/损坏/截断状态、中文文件名和 ZIP64。
- 本地处理：不联网、不写用户目录、不产生解压产物。

## 安装与启用

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

然后在「系统设置」→「通用」→「登录项与扩展」→「Quick Look」中启用 Tapeek。回到 Finder，选中 `.md` 或 `.zip`，按空格。

也可以直接用 `qlmanage -p <文件>` 验证同一扩展。

## 测试

```sh
./scripts/run-tests.sh
```

该命令运行 60 项 Core 测试，并要求 `.build/fixtures/` 中的大样本存在。首次运行先生成样本：

```sh
python3 -I scripts/make-fixtures.py
```

性能基准：

```sh
swift run -c release --package-path Packages/TapeekCore TapeekBench markdown <path>
swift run -c release --package-path Packages/TapeekCore TapeekBench zip <path>
```

## 卸载

```sh
./scripts/uninstall-local.sh
```

只删除 `~/Applications/Tapeek.app` 和 Tapeek 自己的扩展注册，不改动其他扩展的启用状态。

## 轻量性

- Release App 约 2.9 MB，预览扩展约 2.7 MB。
- 500 KB Markdown Core 解析约 0.66 ms；Quick Look 首窗口约 913 ms。
- 20,000 条 ZIP 的 Core 列表 + 树构建约 238–245 ms；首窗口约 0.4 s。
- 超过 2 MiB 的 Markdown 直接拒绝；ZIP 最多显示 20,000 条并提示总数。
- 大文档按标题/空行分块，`LazyVStack` 只渲染可见块。500 KB 文档优化前约 900 MB 内存且 12 秒空白，优化后约 132 MB、1 秒内出现窗口。

## 已知限制

- 同目录图片通常被 Quick Look 沙盒拒绝，显示占位和 alt，正文继续。
- 加密 ZIP 只列目录，不支持密码。
- 不支持分卷 ZIP、RAR、7z、TAR 和自解压 ZIP64。
- 旧式 ZIP 文件名编码只能启发式识别。
- 不支持 Markdown 语法高亮、公式、Mermaid、脚注跳转、文内搜索。

## 文档

| 文档 | 内容 |
| --- | --- |
| [PRD](docs/PRD.md) | 产品目标、范围、验收标准 |
| [实施计划](docs/impl-plan.md) | 架构、命令、技术探针、Core 契约 |
| [功能规格](docs/specs/README.md) | Markdown、ZIP、Quick Look、宿主 App、测试 |
| [执行 tickets](docs/tickets/README.md) | 任务、依赖、范围与验收 |
| [最终验收](docs/verification/FINAL.md) | 证据、性能、限制与结论 |
