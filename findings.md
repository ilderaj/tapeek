# 发现与决策

## 需求
- 用户于 2026-10-31 确认：Markdown 用于项目 README 和技术笔记；第一版自用、支持当前 macOS；不再考虑 vMark。
- 本轮交付 PRD、Impl plan、specs、tickets；需明确到能力较弱的执行 agent 可以逐票完成。
- 仍遵守先规划、后实施：本轮不创建工程、安装或构建 App。

## 研究发现

### 本机基线（已实际检查）
- 项目路径为 `/Users/jared/Personal Projects/Tapeek`，初始为空目录，不是 Git 仓库；没有上级 `AGENTS.md` 或 `CLAUDE.md`。
- macOS 27.0，build 26A428，arm64。
- Xcode 27.0（27A266a），Swift 6.4，macOS SDK 27.0。
- XcodeGen 2.45.3、SwiftLint 0.63.2 已安装；`xcodebuild`、`codesign`、`pluginkit`、`qlmanage` 可用。
- 钥匙串中存在有效签名身份，但本轮不使用、不记录身份信息。MVP 先尝试 ad-hoc 签名；若扩展无法注册，再单独请求用户决定是否使用开发证书。
- `.md` 与 `.markdown` 的系统 UTI 均为 `net.daringfireball.markdown`；`.zip` 为 `public.zip-archive`（由 `mdls` 与 `UTType(filenameExtension:)` 验证）。
- 本机已注册 Bear 的 Markdown Quick Look 扩展：`net.shinyfrog.bear.Bear-Quicklook-Extension`，位于 `/Applications/Bear.app/Contents/PlugIns/Bear Quicklook Extension.appex`。技术核查显示其 Info.plist 未见 `QLSupportedContentTypes`，是否实际处理 `.md` 需通过日志确认；文档不得直接断言它一定抢占 `.md`。

### 技术资料（已打开页面或源码）
- `QLPreviewingController` 支持 view-based 与 data-based 两种路径；data-based 使用 `QLPreviewReply`，需要 `QLIsDataBasedPreview`。SDK 27 未显示这两个 API 被弃用；macOS 27 release notes 只提到 Quick Look 3D/USD 改为 RealityKit。来源：Apple Quick Look 文档、WWDC18 session 237、macOS 27 release notes。
- `QLSupportedContentTypes` 需要精确匹配 UTI；技术核查提示父 UTI 不会自动匹配，T01 用 `mdls` 与本机预览实测确认。本机 `.md` 与 `.zip` 的 UTI 已实测。
- 预览扩展必须沙盒化。Apple 论坛 773050 与 QLMarkdown README 有同目录图片被 `deny(1) file-read-data` 的明确报告；因此同目录图片默认不可读，T02 仍以本机探针确认，产品按「占位、正文可读」设计。
- WKWebView 可能需要网络客户端 entitlement，且 Ad-hoc 签名下 WebContent 子进程存在失败报告；本项目不采用 WKWebView。
- MarkdownUI 2.4.1（MIT，macOS 12+）是原生 SwiftUI 渲染器；`Markdown` 初始化器支持 `baseURL` 与 `imageBaseURL`；`ImageProvider` 是返回 View 的协议，默认 `DefaultImageProvider` 会联网加载图片，必须替换为本地/禁用网络的实现；`Theme.basic` 的代码块已带横向 `ScrollView`，适合长代码行。
- ZIPFoundation 0.9.20（MIT，macOS 10.11+）支持只读打开与逐条访问，不要求整体解压；但加密条目会被 `guard !isEncrypted` 跳过，非 UTF-8 名称需额外指定编码。因此本项目首选自写 central directory 读取器，ZIPFoundation 仅作回退。
- Apple Archive 面向 AppleArchive/AEA，不是标准 ZIP 的通用读取器；不能作为 ZIP 列表实现。
- swift-markdown 0.9.0（Apache-2.0）可作为 MarkdownUI 不可用时的解析备选，但首版不引入双解析器。
- 归档预览的公开案例（ArchiveQuickLook、Loupe 等）表明“读目录、不落盘”是可行方向；未验证其代码质量，不作为实现依赖。
- ad-hoc 签名的 designated requirement 会随构建变化（TN3127）；可能出现扩展已注册但 Finder 仍回退的情况。T01 必须验证，失败则经用户同意改用钥匙串中的开发证书。

## 技术决策
| 决策 | 理由 |
| --- | --- |
| 预览作为系统 Quick Look 扩展，宿主 App 仅作安装说明与入口 | 保持 Finder 空格工作流 |
| 首选 view-based SwiftUI + MarkdownUI 2.4.1 | 原生滚动、明暗模式与文本选择；避免 WKWebView 的沙盒与网络问题 |
| MarkdownUI 失败时回退到 data-based HTML + `cid:` 附件 | 系统渲染，不依赖 WKWebView；作为 P0 决策门 |
| ZIP 首选自写 central directory 读取器，ZIPFoundation 仅作回退 | 可列出加密条目、控制编码与限额；ZIPFoundation 会跳过加密条目 |
| 先 ad-hoc 签名，不默认使用个人开发证书 | 本机自用；避免在未确认时绑定开发者账号 |
| Core 逻辑放进本地 Swift Package | 可单元测试，扩展层只做系统适配 |
| Swift 5 语言模式，暂不开严格并发 | 降低首版编译复杂度；后续单独迁移 |

## 遇到的问题
| 问题 | 解决方案 |
| --- | --- |
| 宿主 worker 协作在先前回合返回 PRECONDITION_FAILED | 不再次创建宿主 worker；采用原生 subagent |
| rg 的 rtk 包装器无法启动真实命令 | 隔离 Python 只读列举文件 |
| 空目录无法执行 git diff | 不初始化 Git，仅记录基线 |
| MarkdownUI 文档站只返回导航壳 | 直接读取 2.4.1 标签的源码确认接口 |

## 资源
- 中文技术写作技能：`/Users/jared/.claude/skills/tech-doc-style-chinese/SKILL.md`。
- 文件规划技能：`/Users/jared/.claude/skills/planning-with-files-zh/SKILL.md`。
- [Apple Quick Look Previews from the Ground Up (WWDC18)](https://developer.apple.com/videos/play/wwdc2018/237/)
- [QLPreviewingController](https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller)
- [MarkdownUI 2.4.1](https://github.com/gonzalezreal/swift-markdown-ui/tree/2.4.1)
- [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.20)
- [swift-markdown 0.9.0](https://github.com/swiftlang/swift-markdown/releases/tag/0.9.0)
- [ArchiveQuickLook](https://github.com/MikeshCZ/ArchiveQuickLook)
- [QLMarkdown](https://github.com/sbarex/QLMarkdown)
- [Apple 论坛 773050：Quick Look 扩展读取同目录图片被拒绝](https://developer.apple.com/forums/thread/773050)
- [Apple 论坛 116359：WKWebView 与 network.client](https://developer.apple.com/forums/thread/116359)
- [TN3127: Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
