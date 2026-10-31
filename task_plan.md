# 任务计划：Tapeek MVP 实施

## 目标

按 tickets 实现 macOS Quick Look 预览扩展：Markdown 格式化预览与 ZIP 只读目录列表，保持轻量、快速、低资源占用，并逐步提交、自测和留证。

## 下一步

提交 T01，然后并行推进 Markdown Core（T03/T04）与 ZIP Core（T06/T07）。

## 当前阶段

阶段 2：Markdown Core 与预览

## 各阶段

### 阶段 1：工程骨架与 Quick Look 注册
- [x] 完成 PRD、实施计划、规格与 tickets。
- [x] 初始化 Git 并提交文档基线。
- [x] 实现 T01 宿主 App、预览扩展与最小 `TAPEEK-SMOKE` 预览。
- [x] 验证构建、ad-hoc 签名、`pluginkit` 注册与 `qlmanage` 调用。
- **状态：** complete

### 阶段 2：Markdown Core 与预览
- [ ] T03 Core 基础类型与测试。
- [ ] T04 Markdown 加载、编码、front matter 与测试。
- [ ] T02 MarkdownUI 探针与图片/深色模式结论。
- [ ] T05 正式 Markdown 预览 UI。
- **状态：** in_progress

### 阶段 3：ZIP Core 与预览
- [ ] T06 自写 central directory 读取器与夹具。
- [ ] T07 树模型、排序、展开行与测试。
- [ ] T08 ZIP 摘要、目录树、错误与截断状态。
- **状态：** pending

### 阶段 4：路由、宿主 App 与集成
- [ ] T09 路由、生命周期、错误展示与多文件切换。
- [ ] T10 宿主 App 单页说明与示例入口。
- [ ] 集成构建、安装并做第一轮手工预览。
- **状态：** pending

### 阶段 5：夹具、性能与端到端验收
- [ ] T11 全量夹具、manifest、TapeekBench 与性能记录。
- [ ] T12 安装/卸载脚本与端到端验收。
- [ ] 针对轻量目标优化：启动、解析、内存、包体与无谓后台工作。
- **状态：** pending

### 阶段 6：最终验收与交付
- [ ] T13 汇总证据、已知限制与 README。
- [ ] 确认所有验收项有证据，未通过项如实记录。
- **状态：** pending

## 关键问题

1. ad-hoc 签名在当前 macOS 27 上能否稳定注册并被 Finder 调用？
2. MarkdownUI 在 Quick Look 扩展进程中是否能稳定渲染，相对图片是否可读？
3. 自写 ZIP 解析器在 ZIP64、加密标记、旧式编码和损坏样本上的行为是否与 `unzip` 一致？
4. 轻量目标：典型 README 解析 ≤ 100 ms、500 KB ≤ 300 ms、20,000 条 ZIP ≤ 1 s；包体和常驻内存尽量小。

## 已做决策

| 决策 | 理由 |
| --- | --- |
| 按 T01 → Core → UI → 集成的顺序实施 | 先验证系统接入，再写业务逻辑，避免在未注册的扩展上堆代码 |
| 原生 subagent 分担独立模块，协调者统一提交 | 宿主 worker 协作不可用；subagent 可并行 Core/ZIP，但共享文件由协调者合并 |
| MarkdownUI 2.4.1 + SwiftUI view-based | 原生滚动、选择、明暗模式；避开 WKWebView 的沙盒与网络问题 |
| 自写 ZIP central directory 读取器 | ZIPFoundation 会跳过加密条目；自写可控制编码、限额和错误 |
| 轻量优先：同步解析、硬上限、无网络、无落盘 | Quick Look 生命周期短，不能引入后台任务和重型依赖 |
| 先 ad-hoc 签名，失败再请求开发证书 | 本机自用，避免未确认时绑定账号 |

## 遇到的错误

| 错误 | 尝试次数 | 解决方案 |
| --- | --- | --- |
| 宿主 worker PRECONDITION_FAILED（先前回合） | 1 | 不重试宿主 worker；使用原生 subagent |
| rg 包装器未找到可执行文件 | 1 | 使用隔离 Python 或 `grep` |
| 文档初稿把 Bear 写成已启用冲突 | 1 | 核查 Info.plist 后改为「已注册，是否处理 .md 待日志确认」 |

## 备注

协调者维护计划、Git 提交和最终验收。subagent 只在分配的文件范围内工作，不自行提交；完成后由协调者跑测试、审查差异并提交。
