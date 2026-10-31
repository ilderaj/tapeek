# T05 Markdown 预览 UI

| 项 | 内容 |
| --- | --- |
| ID | T05 |
| 状态 | 待开始 |
| 依赖 | T02、T04 |
| 执行角色 | executor；视觉与交互可由 thinker 复核 |
| 预计产物 | 正式 Markdown 预览视图、前置元数据卡片、错误与空状态 |

## 必读

- [Markdown 规格](../specs/markdown-preview.md) 全文。
- [实施计划](../impl-plan.md) §9.3。
- [T02 ticket](T02-markdownui-spike.md) 的图片与渲染结论；其验收记录在执行后生成。
- [Quick Look 集成规格](../specs/quicklook-integration.md) §4。

## 目标

把 T02 的临时渲染和 T04 的加载器组合成正式 Markdown 预览：正确的排版、front matter 卡片、图片占位、链接策略、空状态和错误状态。

## 允许改动

- `TapeekPreview/MarkdownPreviewView.swift`
- `TapeekPreview/LocalImageProvider.swift`
- `TapeekPreview/PreviewTheme.swift`（新建）
- `TapeekPreview/MarkdownStateViews.swift`（新建）
- `TapeekPreview/PreviewViewController.swift`（只改 Markdown 分支）
- `Packages/TapeekCore/Sources/TapeekCore/Markdown/ImageAltIndex.swift`（新建）
- `Packages/TapeekCore/Tests/TapeekCoreTests/ImageAltIndexTests.swift`
- `Samples/markdown/long-code.md`
- `Samples/markdown/wide-table.md`
- `Samples/markdown/tasks.md`
- `Samples/markdown/raw-html.md`
- `Samples/markdown/image-no-alt.md`
- `Samples/markdown/many-front-matter.md`
- `Samples/markdown/long.md`
- `docs/verification/T05.md`
- `docs/verification/T05-*.png`

## 禁止改动

- 不修改 `MarkdownLoader` 的解码与 front matter 语义；发现问题回到 T04。
- 不修改 ZIP 文件或 ZIP 视图。
- 不引入 WKWebView、网络图片库或新的第三方依赖。
- 不添加网络、全盘访问或临时路径权限。
- 不实现编辑、搜索、目录导航、语法高亮。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
./scripts/build.sh
qlmanage -p Samples/markdown/gfm.md
```

确认 T04 测试通过，T02 的 MarkdownUI 渲染仍可用。

## 步骤

### 1. 实现 ImageAltIndex

放在 Core 的 `Markdown/ImageAltIndex.swift`，供视图查询图片替代文字：

```swift
public struct ImageAltIndex: Sendable {
    public init(markdown: String, baseURL: URL)
    public func alt(for url: URL) -> String?
}
```

规则：

- 识别常见行内图片语法 `![alt](destination)` 和 `![alt](destination "title")`。
- 跳过代码块中的内容；若实现成本高，至少跳过反引号包围的行，并在验收中记录限制。
- 把 destination 按 `baseURL` 解析为绝对 URL，作为键。
- 同一 URL 多次出现，保留第一次的非空 alt。
- alt 为空时返回空字符串，不返回 nil。
- 无法解析的图片语法忽略，不影响正文。
- 用 `NSRegularExpression` 或简单扫描实现；不要引入 Markdown 解析库。
- 测试：相对路径、远程 URL、带 title、空 alt、重复 URL、代码块中的伪图片。

### 2. 实现图片 Provider

`LocalImageProvider` 接收 `altIndex`：

```swift
struct LocalImageProvider: ImageProvider {
    let altIndex: ImageAltIndex
    func makeImage(url: URL?) -> some View { ... }
}
```

规则：

- `url == nil` → 占位，原因为「图片缺失」。
- 非 `file:` URL → 占位，原因为「远程图片未加载」。
- 文件不存在 → 「图片缺失」。
- 文件大小超过 `PreviewLimits.default.maxImageBytes` → 「图片过大」。
- 使用 ImageIO：
  - `CGImageSourceCreateWithURL`。
  - `CGImageSourceCreateThumbnailAtIndex`，选项 `kCGImageSourceCreateThumbnailFromImageAlways: true`、`kCGImageSourceThumbnailMaxPixelSize: maxImagePixelSize`。
  - 失败 → 「图片不可用」。
- 成功：`Image(decorative: cgImage, scale: 1)`，`.resizable().scaledToFit()`，最大宽度填满内容区，圆角 6。
- 占位：图标 + alt + 原因。alt 从 `altIndex.alt(for: url)` 取；为空时用文件名或「图片不可用」。
- 不使用 `NSImage(contentsOf:)` 解码整图，不使用 `AsyncImage`。
- 占位不抛出错误，不影响正文。

### 3. 实现主题

`PreviewTheme.swift` 提供 `View` 扩展或 `Theme` 常量。基于 `Theme.basic`，覆盖：

- 正文字号 15，行距约 1.45。
- 行内代码：等宽、0.9 em、次要背景。
- 代码块：等宽、横向滚动、内边距 12、圆角 6、次要背景。
- 表格：横向滚动，表头加粗，边框使用分隔色。
- 引用：左侧 3 pt 强调线，文字次要色。
- 分隔线：系统分隔色。
- 所有颜色使用语义色，不写死十六进制。

示意（以 MarkdownUI 2.4.1 的 API 为准）：

```swift
extension View {
    func tapeekMarkdownStyle() -> some View {
        self
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(15)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                BackgroundColor(Color.secondary.opacity(0.12))
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                }
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 3)
                    }
            }
    }
}
```

若某个 API 与 2.4.1 不符，以实际编译结果为准，保持视觉目标不变。

### 4. 实现 MarkdownPreviewView

结构：

```swift
struct MarkdownPreviewView: View {
    let document: MarkdownDocument
    let fileURL: URL
    private let altIndex: ImageAltIndex

    init(document: MarkdownDocument, fileURL: URL) {
        self.document = document
        self.fileURL = fileURL
        self.altIndex = ImageAltIndex(
            markdown: document.body,
            baseURL: document.baseURL
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !document.frontMatter.isEmpty {
                    FrontMatterCard(entries: document.frontMatter)
                }
                if document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("正文为空")
                        .foregroundStyle(.secondary)
                } else {
                    Markdown(
                        document.body,
                        baseURL: document.baseURL,
                        imageBaseURL: document.baseURL
                    )
                    .markdownImageProvider(
                        LocalImageProvider(altIndex: altIndex)
                    )
                    .tapeekMarkdownStyle()
                    .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                return .handled
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}
```

要求：

- 只有正文为空且没有 front matter 时，显示空状态；由外层状态视图处理。
- front matter 卡片最多 8 项，超出显示「还有 N 项」。
- 正文最大宽度 860 pt，窄窗口自适应。
- 图片、代码块、表格不撑破容器。
- 链接只放行 http/https/mailto。
- `ImageAltIndex` 在视图初始化时构建一次，不要把正则扫描放在 `body` 里反复执行。

### 5. 实现 FrontMatterCard

```swift
struct FrontMatterCard: View {
    let entries: [FrontMatterEntry]
}
```

要求：

- 标题「文档信息」，次要文字样式。
- 最多 8 行；键使用次要色，值使用正文色。
- 空值显示 `—`。
- 超过 8 项显示「还有 N 项」。
- 背景 `Color.secondary.opacity(0.08)`，圆角 8，内边距 12。
- 键和值都支持选中复制（可选）。
- 不把值解释为链接或 Markdown。

### 6. 实现状态视图

`MarkdownStateViews.swift`：

- `MarkdownEmptyView`：标题「空文档」，详情「这个文件没有可显示的内容。」
- `MarkdownFailureView`：接收 `PreviewFailure` 和 `fileURL`，映射为规格第 9.2 节的标题与详情。
- 错误视图居中，包含 `exclamationmark.triangle` 图标、标题、详情、文件名。
- `fileTooLarge` 使用 `ByteCountFormatter` 显示实际大小和上限。
- 不提供重试按钮。
- 背景与正文视图一致。

### 7. 接入 PreviewViewController

Markdown 分支：

```swift
do {
    let document = try MarkdownLoader.load(url: url)
    if document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       document.frontMatter.isEmpty {
        rootView = AnyView(MarkdownEmptyView())
    } else {
        rootView = AnyView(MarkdownPreviewView(document: document, fileURL: url))
    }
} catch let failure as PreviewFailure {
    rootView = AnyView(MarkdownFailureView(failure: failure, fileURL: url))
} catch {
    rootView = AnyView(MarkdownFailureView(failure: .unreadableFile, fileURL: url))
}
```

要求：

- 每次重建 hosting view，移除旧视图。
- 解析在调用 `handler(nil)` 前完成。
- 不保留 `fileURL` 之外的文件句柄。
- ZIP 分支保持 T02 的占位，T08 替换。

### 8. 创建剩余样本

按 [测试规格](../specs/testing-and-fixtures.md) §3 创建：

- `long-code.md`：超过 200 字符的单行代码。
- `wide-table.md`：8 列宽表。
- `tasks.md`：已选、未选、嵌套任务。
- `raw-html.md`：包含 `<script>alert(1)</script>` 和 `<b>bold</b>`。
- `image-no-alt.md`：`![](assets/pixel.png)`。
- `many-front-matter.md`：12 个键值。
- `long.md`：约 200 段。

### 9. 构建与截图

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
qlmanage -p Samples/markdown/gfm.md
```

逐项截图：

- `T05-01-gfm-light.png`
- `T05-02-gfm-dark.png`
- `T05-03-front-matter.png`
- `T05-04-relative-image.png`
- `T05-05-remote-image.png`
- `T05-06-code-block.png`
- `T05-07-wide-table.png`
- `T05-08-empty.png`
- `T05-09-invalid-utf8.png`
- `T05-10-long.png`

截图必须来自真实 Quick Look 窗口。

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| GFM | 预览 `gfm.md` | 规格第 4 节的结构全部可读 |
| Front matter | 预览 `front-matter.md` | 卡片最多 8 项，正文无元数据 |
| 相对图片 | 预览 `relative-image.md` | 可读则显示；不可读则占位含 alt |
| 远程图片 | 离线预览 `remote-image.md` | 不加载网络图片，占位含原因 |
| 空文档 | 预览 `empty.md` | 「空文档」 |
| 只有元数据 | 预览 `only-front-matter.md` | 卡片 + 「正文为空」 |
| 编码错误 | 预览 `invalid-utf8.md` | 错误标题与详情 |
| 代码块 | 预览 `long-code.md` | 横向滚动，缩进保留 |
| 宽表格 | 预览 `wide-table.md` | 横向滚动，不撑破窗口 |
| 任务列表 | 预览 `tasks.md` | 勾选状态只读 |
| 原始 HTML | 预览 `raw-html.md` | 无弹窗、无脚本执行 |
| 长文档 | 预览 `long.md` | 可滚动到底，无截断 |
| 深色模式 | 切换外观 | 对比度正常 |
| 链接 | 点击外链 | 浏览器打开，预览不导航 |
| 无网络代码 | 代码审查 | 无 `URLSession`/`AsyncImage`/`WKWebView` |

对应规格用例：MD-001 至 MD-009、MD-011 至 MD-022。

## 证据

- `docs/verification/T05.md`：逐项结果、命令、未通过项。
- 上述十张截图。
- `swift test` 输出（含 `ImageAltIndexTests`）。

## 停止条件

- MarkdownUI 的 block style API 与 2.4.1 不符，且一次调整后仍无法编译。
- 图片 Provider 导致预览崩溃或明显卡顿（超过 1 秒）。
- front matter 卡片或状态视图无法在 Quick Look 中显示。
- 需要放宽沙盒或引入网络权限。

## 交接

给 T09：

- 正式的 `MarkdownPreviewView`、`MarkdownFailureView`、`MarkdownEmptyView`。
- 链接拦截和图片 Provider 的行为。
- 已知的图片访问限制。
- 可复用的状态视图样式。
