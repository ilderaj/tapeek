# T02 MarkdownUI 与图片探针

| 项 | 内容 |
| --- | --- |
| ID | T02 |
| 状态 | 完成 |
| 依赖 | T01 |
| 执行角色 | executor；结论由 thinker 复核 |
| 预计产物 | MarkdownUI 渲染结论、图片访问结论、浅色/深色截图 |

## 必读

- [PRD](../PRD.md) §3.1、§4 F1、§7。
- [Markdown 规格](../specs/markdown-preview.md) §3、§4、§6、§8。
- [实施计划](../impl-plan.md) §5 决策门 D2、§8 P0-2。
- [Quick Look 集成规格](../specs/quicklook-integration.md) §4、§9。

## 目标

确认 MarkdownUI 能否在 Quick Look 扩展进程中稳定渲染常见 GFM，并确认相对图片在沙盒中的实际行为。此 ticket 不追求完整产品 UI，只回答技术可行性。

## 允许改动

- `project.yml`（只添加 MarkdownUI 包与扩展依赖）
- `TapeekPreview/MarkdownPreviewView.swift`（新建）
- `TapeekPreview/LocalImageProvider.swift`（新建）
- `TapeekPreview/PreviewViewController.swift`（临时路由）
- `Samples/markdown/gfm.md`
- `Samples/markdown/relative-image.md`
- `Samples/markdown/remote-image.md`
- `Samples/markdown/assets/pixel.png`
- `docs/verification/T02.md`
- `docs/verification/T02-*.png`

## 禁止改动

- 不创建 `TapeekCore`；T03 才创建。
- 不实现 ZIP 视图；ZIP 分支只显示占位文字。
- 不引入 WKWebView、`URLSession`、`AsyncImage` 或网络图片库。
- 不添加网络 entitlement、全盘访问或临时路径例外。
- 不改宿主 App 的正式界面；T10 负责。

## 前置检查

```sh
./scripts/verify-extension.sh
qlmanage -p Samples/markdown/smoke.md
```

确认 T01 的 `TAPEEK-SMOKE` 仍可显示。若不可显示，先修复 T01，不继续。

## 步骤

### 1. 添加 MarkdownUI

在 `project.yml` 的 `packages` 添加：

```yaml
  MarkdownUI:
    url: https://github.com/gonzalezreal/swift-markdown-ui
    exactVersion: 2.4.1
```

若 T03 已经修改过 `project.yml`，只追加 MarkdownUI 条目和依赖，不覆盖 `TapeekCore` 的声明。

在 `TapeekPreview` 的 `dependencies` 添加：

```yaml
      - package: MarkdownUI
```

重新生成工程并构建。若 SwiftPM 解析失败，记录完整错误和网络状态，不改为本地拷贝源码。

### 2. 准备 Markdown 样本

`Samples/markdown/gfm.md` 至少包含：

- 一级、二级、三级标题。
- 粗体、斜体、删除线、行内代码。
- 有序列表、无序列表、嵌套列表、任务列表。
- 引用块。
- 表格（含对齐）。
- 围栏代码块，包含长行。
- 链接。
- 分隔线。

`Samples/markdown/relative-image.md`：

```markdown
# 相对图片

![pixel](assets/pixel.png)
```

`Samples/markdown/remote-image.md`：

```markdown
# 远程图片

![remote](https://example.com/x.png)

正文仍然可读。
```

`assets/pixel.png` 必须是有效的 1×1 PNG。可以用 `sips` 或 Python 生成，不要用文本文件改名。

### 3. 实现临时 Markdown 视图

`MarkdownPreviewView.swift`：

```swift
import MarkdownUI
import SwiftUI

struct MarkdownPreviewView: View {
    let fileURL: URL
    let markdown: String

    var body: some View {
        ScrollView {
            Markdown(markdown, baseURL: fileURL.deletingLastPathComponent())
                .markdownTheme(.basic)
                .markdownImageProvider(LocalImageProvider())
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
```

要求：

- 只使用 `MarkdownUI`，不引入 `NetworkImage` 的直接调用。
- 不设置固定窗口尺寸。
- `baseURL` 使用文件所在目录，保证相对图片和链接能解析。

### 4. 实现本地图片 Provider

`LocalImageProvider.swift` 使用 `ImageProvider` 协议。示意：

```swift
import AppKit
import MarkdownUI
import SwiftUI

struct LocalImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Group {
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ImagePlaceholder(url: url)
            }
        }
    }
}
```

要求：

- 只接受 `file:` URL。
- `http`、`https`、`data`、自定义 scheme 直接进入占位，不发起请求。
- 占位显示 `图片不可用` 或 `远程图片未加载`，并显示 alt 或文件名。占位视图需要在本 ticket 中自行实现，可以先用简单图标加文字。
- 此版本可以同步 `NSImage(contentsOf:)`；T05 再改为 ImageIO 缩略图和大小限制。
- 不使用 `AsyncImage`。

### 5. 临时路由

修改 `PreviewViewController`：

- 读取文件文本（此 ticket 可以用 `String(contentsOf:encoding:.utf8)`，T04/T05 会替换）。
- `.md`/`.markdown` → `MarkdownPreviewView`。
- `.zip` → 静态文字 `ZIP-TODO`。
- 读取失败 → 静态错误文字。
- 每次重建 `NSHostingView`，移除旧视图。

不要在此 ticket 实现完整错误分类、前置元数据或限额。

### 6. 构建与安装

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

### 7. 验证与截图

1. `qlmanage -p Samples/markdown/gfm.md`，浅色截图 `T02-01-light.png`。
2. 切换系统深色外观，重新打开预览，截图 `T02-02-dark.png`。
3. 预览 `relative-image.md`：
   - 图片显示：记录「相对图片可读」。
   - 占位：记录「沙盒拒绝或读取失败」，保存截图 `T02-03-relative-image.png`。
4. 关闭网络，预览 `remote-image.md`，截图 `T02-04-remote-image.png`。
5. 观察代码块长行是否横向滚动，表格是否可读，任务列表是否只读。
6. 代码审查：搜索 `URLSession`、`AsyncImage`、`WKWebView`、`NetworkImage`，确认没有调用路径。

### 8. 记录决策

在 `docs/verification/T02.md` 写明：

- MarkdownUI 是否可用。
- 相对图片是否可读。
- 远程图片是否被阻止。
- 代码块/表格/任务列表是否满足规格。
- 是否触发决策门 D2。
- 给 T05 的具体建议。

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| 编译 | `./scripts/build.sh` | 退出码 0 |
| GFM 渲染 | 预览 `gfm.md` | 标题、列表、表格、代码、引用可读 |
| 相对图片 | 预览 `relative-image.md` | 显示图片，或显示可读占位并记录原因 |
| 远程图片 | 离线预览 `remote-image.md` | 不加载网络图片；正文可读 |
| 深色模式 | 切换外观 | 无浅底浅字、深底深字 |
| 无网络代码 | 代码审查 | 没有 `URLSession`/`AsyncImage`/`WKWebView` 调用 |
| 性能 | 打开 `gfm.md` | 1 秒内出现内容 |

对应规格用例：MD-001（部分）、MD-011、MD-013、MD-018、MD-021。

## 证据

- `docs/verification/T02.md`：决策记录、命令输出、代码审查结果。
- `T02-01-light.png`、`T02-02-dark.png`。
- `T02-03-relative-image.png`、`T02-04-remote-image.png`。

## 停止条件

- MarkdownUI 连续两次构建失败，且错误与网络无关 → 触发 D2，停止并报告。
- 预览空白且 T01 的烟雾测试仍正常 → 记录，不反复改代码。
- 相对图片失败 → 不视为阻塞，记录为限制，继续 T05 的占位方案。
- 出现崩溃 → 保存崩溃日志，停止。

## 交接

给 T05：

- 可用的 `MarkdownPreviewView` 和 `LocalImageProvider` 起点。
- 相对图片是否可读的结论。
- 需要替换的临时文本读取和错误处理。
- 深色模式、代码块、表格的实际表现。
