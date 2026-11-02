# 任务计划：Tapeek MVP 实施

## 目标

按 tickets 实现 macOS Quick Look 预览扩展：Markdown 格式化预览与 ZIP 只读目录列表，保持轻量、快速、低资源占用，并逐步提交、自测和留证。

## 下一步

MVP 已完成并安装。剩余动作是用户在 Finder 中手动确认空格预览和宿主 App 两个按钮；代码侧无待办。

## 当前阶段

阶段 6：最终验收与交付

## 各阶段

### 阶段 1：工程骨架与 Quick Look 注册
- [x] 初始化 Git 并提交文档基线。
- [x] 实现 T01 宿主 App、预览扩展与最小预览。
- [x] 验证构建、ad-hoc 签名、`pluginkit` 注册与 `qlmanage`。
- **状态：** complete

### 阶段 2：Markdown Core 与预览
- [x] T03 Core 基础类型与测试。
- [x] T04 Markdown 加载、编码、front matter。
- [x] T02 MarkdownUI 探针。
- [x] T05 正式 Markdown 预览 UI。
- **状态：** complete

### 阶段 3：ZIP Core 与预览
- [x] T06 central directory 读取器与夹具。
- [x] T07 树模型、排序、展开行。
- [x] T08 ZIP 摘要、目录树、错误与截断状态。
- **状态：** complete

### 阶段 4：路由、宿主 App 与集成
- [x] T09 路由、生命周期、日志和多文件切换。
- [x] T10 宿主 App 说明页与示例资源。
- [x] 集成构建、安装和 Quick Look 预览。
- **状态：** complete

### 阶段 5：夹具、性能与端到端验收
- [x] T11 全量夹具、manifest、TapeekBench。
- [x] T12 安装/卸载脚本与端到端验收。
- [x] 大文档分块懒加载，修复 500 KB 预览卡顿。
- **状态：** complete

### 阶段 6：最终验收与交付
- [x] T13 汇总证据、已知限制与 README。
- [x] 记录 Finder/宿主按钮/VoiceOver 的未验证项。
- **状态：** complete

## 关键问题

1. ad-hoc 签名在当前 macOS 27 上能稳定注册并被调用，无需开发证书。
2. MarkdownUI 在扩展进程中可用；同目录图片被沙盒拒绝，按占位处理。
3. 自写 ZIP 解析器与 `unzip` 结构一致，支持 ZIP64、加密标记、GBK 启发式和截断。
4. 轻量目标：500 KB Core 解析 0.66 ms，Quick Look 首窗口 913 ms；20k ZIP 首窗口约 0.4 s；Release 包 2.9 MB。

## 已做决策

| 决策 | 理由 |
| --- | --- |
| MarkdownUI 2.4.1 + SwiftUI view-based | 原生滚动、选择、明暗模式；避开 WKWebView |
| 自写 ZIP central directory 读取器 | 可列加密条目，控制编码与限额 |
| 大文档按标题/空行分块 + LazyVStack | 避免 MarkdownUI 一次性布局 500 KB 导致高内存和空白 |
| 安装脚本核对 bundle ID/签名并备份旧版 | 避免误删用户已有 App |
| 环境判断以同上下文 `pwd/uname/id` 为准 | remote-magpie 会注入错误的 Linux 环境说明 |

## 遇到的错误

| 错误 | 尝试次数 | 解决方案 |
| --- | --- | --- |
| T04 CRLF front matter 值残留 `\r` | 1 | 改用 `.whitespacesAndNewlines` |
| `ImageAltIndex` 测试基准目录缺少尾斜杠 | 1 | 使用目录 URL，修正代码块用例 |
| zsh 的 `log` 是内建函数，日志看不到 | 1 | 改用 `/usr/bin/log` |
| 500 KB Markdown 预览 12 秒空白、约 900 MB | 1 | MarkdownChunker + LazyVStack，降至约 132 MB、913 ms |
| `pluginkit` 指向 DerivedData 构建产物 | 1 | 安装脚本移除旧构建注册 |
| 会话误报 Linux 环境 | 3 | 根因是 remote-magpie VPS 环境说明；以工具实测为准 |

## 备注

MVP 功能完成；T10/T12 的宿主按钮、Finder 空格和 VoiceOver 仍待用户手动确认，已在 `FINAL.md` 中列为部分通过。
