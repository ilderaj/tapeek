# T08 ZIP 预览 UI

| 项 | 内容 |
| --- | --- |
| ID | T08 |
| 状态 | 完成 |
| 依赖 | T07、T02 |
| 执行角色 | executor；视觉与交互可由 thinker 复核 |
| 预计产物 | ZIP 摘要、目录树、展开交互、空/错误/截断状态 |

## 必读

- [ZIP 规格](../specs/zip-preview.md) §7、§8、§10。
- [实施计划](../impl-plan.md) §9.5。
- [Quick Look 集成规格](../specs/quicklook-integration.md) §4。

## 目标

把 `ZipTree` 显示为可展开的只读目录树，包含文件名、摘要、大小、加密/截断提示和错误状态。不实现任何文件打开或解压动作。

## 允许改动

- `TapeekPreview/ZipPreviewView.swift`（新建）
- `TapeekPreview/ZipTreeView.swift`（新建）
- `TapeekPreview/ZipStateViews.swift`（新建）
- `TapeekPreview/PreviewViewController.swift`（只改 ZIP 分支）
- `docs/verification/T08.md`
- `docs/verification/T08-*.png`

## 禁止改动

- 不修改 `ZipArchiveReader` 或 `ZipTree` 的语义；发现问题回到 T06/T07。
- 不实现解压、打开文件、拖出、搜索、筛选。
- 不修改 Markdown 视图。
- 不添加网络或文件写入权限。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
./scripts/build.sh
qlmanage -p Samples/zip/typical.zip
```

T02 的 ZIP 分支目前只显示 `ZIP-TODO`；确认构建可用。

## 步骤

### 1. 实现 ZipPreviewView

```swift
struct ZipPreviewView: View {
    let tree: ZipTree
    let fileURL: URL

    @State private var expanded: Set<String>

    init(tree: ZipTree, fileURL: URL) {
        self.tree = tree
        self.fileURL = fileURL
        _expanded = State(initialValue: tree.defaultExpandedIDs())
    }
}
```

结构：

```
VStack(spacing: 0) {
    ZipHeader(...)          // 文件名、摘要、加密标记
    if let notice = ... { ZipNoticeBar(...) }
    Divider()
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(tree.rows(expanded: expanded)) { row in
                ZipTreeRow(...)
            }
        }
    }
}
.background(Color(nsColor: .textBackgroundColor))
```

`ZipTreeView` 负责头部、提示条和滚动树的组合；`ZipPreviewView` 持有展开状态并处理空/错误分支。若把两者合并为一个文件，保持职责分离即可。

要求：

- 头部固定，不随树滚动。
- 树使用 `rows(expanded:)` 的输出，不自行递归渲染。
- 每次重建视图时，展开状态从 `defaultExpandedIDs()` 开始；不跨文件持久化。
- 空包、全部跳过、错误由状态视图处理，不显示空树。

### 2. 实现头部摘要

`ZipHeader` 输入 `ZipTree` 和文件名：

- 第一行：文件名，使用标题样式，单行截断，悬停显示完整路径。
- 第二行：`{tree.fileCount} 个文件，{tree.directoryCount} 个文件夹`。
- 第三行：`未压缩 {tree.listing.totalUncompressedBytes} · 压缩包 {tree.listing.archiveBytes}`。
- 加密时追加标记「含加密条目」。
- 截断或跳过时，第一行数量改为规格 §7.1 的文案。
- 大小格式使用 `ByteCountFormatter`，`.file` 样式。
- 0 字节显示 `0 字节`；不显示小数位过多的数字。
- 头部内边距 20 水平、16 垂直。

### 3. 实现提示条

`ZipNoticeBar` 根据 `listing.warnings` 和 `isTruncated` 生成一条或多条提示：

| 条件 | 文案 |
| --- | --- |
| `isTruncated` | `条目过多，仅显示前 {shown} 项，共 {total} 项。` |
| `timedOut` | `读取超时，仅显示已读取的条目。` |
| `skippedEntryCount > 0` 且未截断 | `{skipped} 项因路径或编码问题被跳过。` |
| 加密条目 | `压缩包包含加密条目；首版只显示目录。` |
| 重复路径 | `存在重复路径，已保留第一条。` |
| 旧式编码 | `部分文件名使用了旧式编码，显示可能有误。` |

要求：

- 提示条使用次要背景或警告色，不遮挡树。
- 多条提示合并为一个区域，用换行或小段落分隔，不堆叠多个彩色卡片。
- 不显示内部错误码或字节偏移。
- 无警告时不占空间。

### 4. 实现树行

`ZipTreeRow` 输入 `ZipRow`、是否展开、切换回调：

- 左边距：`depth * 16`。
- 目录有子节点时显示 `chevron.right` / `chevron.down`，可点击。
- 文件无箭头，保留同宽占位，保证名称对齐。
- 图标：目录 `folder`，文件 `doc`，符号链接 `link`。
- 名称：单行，`truncationMode(.middle)`，`.help(node.path)`。
- 文件右侧显示大小；目录右侧显示 `{children.count} 项`。
- 行高 24，水平内边距 8。
- 目录行整行可点击切换；文件行点击无动作。
- `.contentShape(Rectangle())` 保证整行命中。
- 使用 `Button` 或 `onTapGesture`，但键盘焦点只能落在目录行；不要让文件行成为可聚焦按钮。
- 辅助功能标签：
  - 目录：`文件夹，{name}，{count} 项`，值 `已展开`/`已折叠`。
  - 文件：`文件，{name}，{size}`。
  - 符号链接：`符号链接，{name}，{size}`。
- 不显示修改时间在主行；放在 `.help` 中：

```
{path}
修改时间：{yyyy-MM-dd HH:mm}
```

无日期显示 `修改时间：—`。

### 5. 实现状态视图

`ZipStateViews.swift`：

- `ZipEmptyView`：标题「压缩包为空」，详情「这个 ZIP 没有可显示的条目。」
- `ZipAllSkippedView`：标题「无法显示压缩包目录」，详情「所有条目路径均无效或无法解码。」
- `ZipFailureView`：接收 `PreviewFailure`，按 ZIP 规格 §8 映射标题与详情。
- 错误视图居中，图标 `exclamationmark.triangle`，包含文件名。
- 不提供重试按钮。
- 背景与树视图一致。

错误映射：

| Failure | 标题 | 详情 |
| --- | --- | --- |
| `.unreadableFile` | 无法读取文件 | 文件可能已被移动，或当前没有读取权限。 |
| `.archiveUnreadable` | 无法读取压缩包 | 文件可能已损坏，或不是标准 ZIP。 |
| `.archiveEncrypted` | 压缩包已加密 | 无法读取加密的目录信息。首版不支持输入密码。 |
| `.archiveUnsupported(message)` | 暂不支持此压缩包 | 使用 message 的可读文案，不显示内部代码。 |
| `.listingTimedOut` | 读取超时 | 压缩包较大或结构异常，未能读取目录。 |

### 6. 接入 PreviewViewController

ZIP 分支：

```swift
do {
    let listing = try ZipArchiveReader.list(url: url)
    if listing.entries.isEmpty && listing.totalEntryCount == 0 {
        rootView = AnyView(ZipEmptyView())
    } else if listing.entries.isEmpty && listing.skippedEntryCount > 0 {
        rootView = AnyView(ZipAllSkippedView())
    } else {
        let tree = ZipTree(
            listing: listing,
            archiveName: url.deletingPathExtension().lastPathComponent
        )
        rootView = AnyView(ZipPreviewView(tree: tree, fileURL: url))
    }
} catch let failure as PreviewFailure {
    rootView = AnyView(ZipFailureView(failure: failure, fileURL: url))
} catch {
    rootView = AnyView(ZipFailureView(failure: .archiveUnreadable, fileURL: url))
}
```

要求：

- 每次重建 hosting view，移除旧视图。
- 解析在 `handler(nil)` 前完成。
- 不保留 `FileHandle` 或 `Data`。
- 不调用任何解压 API。

### 7. 构建与截图

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
qlmanage -p Samples/zip/typical.zip
```

逐项截图：

- `T08-01-typical.png`：典型树，展开两层。
- `T08-02-empty.png`：空包。
- `T08-03-encrypted.png`：加密提示。
- `T08-04-corrupt.png`：损坏错误。
- `T08-05-truncated.png`：截断提示（需要 T11 大样本；没有则记录未覆盖）。
- `T08-06-long-names.png`：长名称截断与悬停。
- `T08-07-single-root.png`：单根默认展开两层。
- `T08-08-dark.png`：深色模式。
- `T08-09-chinese.png`：中文名称。

截图必须来自真实 Quick Look 窗口。

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| 典型树 | 预览 `typical.zip` | 文件夹在文件前；可展开/折叠 |
| 摘要 | 查看头部 | 文件数、文件夹数、未压缩/压缩大小正确 |
| 展开 | 点击目录行 | 只改变本地视图，不写盘 |
| 文件行 | 点击文件 | 无动作，不打开、不提取 |
| 空包 | 预览 `empty.zip` | 「压缩包为空」 |
| 加密 | 预览 `encrypted.zip` | 列表可见，显示加密提示 |
| 损坏 | 预览 `corrupt.zip` | 错误视图，不崩溃 |
| 中文 | 预览 `chinese-utf8.zip` | 名称正确 |
| 长名称 | 预览 `long-names.zip` | 中间截断，悬停显示完整路径 |
| 单根 | 预览 `single-root.zip` | 默认展开两层 |
| 深色 | 切换外观 | 对比度正常 |
| 无写入 | 预览前后 `find` | 无新增文件 |
| 多文件 | 切换 Markdown/ZIP | 不串内容（T09 复验） |

对应规格用例：ZIP-001 至 ZIP-019、ZIP-024。

## 证据

- `docs/verification/T08.md`：逐项结果、命令、未覆盖项。
- 上述九张截图。
- `swift test` 摘要（Core 仍通过）。

## 停止条件

- `ZipTree.rows` 输出的顺序或深度不符合规格。
- 目录展开导致明显卡顿（超过 200 ms）。
- 预览窗口在窄宽度下出现整页横向滚动。
- 需要修改 Core 语义或添加解压能力。

## 交接

给 T09：

- `ZipPreviewView`、`ZipTreeView`、`ZipStateViews`。
- 统一的头部、提示条、错误视图样式。
- 展开状态与多文件重建行为。
- 截图与已知视觉问题。
