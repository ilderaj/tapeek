# T09 路由、生命周期与错误整合

| 项 | 内容 |
| --- | --- |
| ID | T09 |
| 状态 | 待开始 |
| 依赖 | T05、T08 |
| 执行角色 | executor |
| 预计产物 | 统一预览入口、类型路由、错误展示、多文件重建与日志 |

## 必读

- [Quick Look 集成规格](../specs/quicklook-integration.md) §4、§5、§10。
- [Markdown 规格](../specs/markdown-preview.md) §9。
- [ZIP 规格](../specs/zip-preview.md) §8。
- [实施计划](../impl-plan.md) §8 P0-3。

## 目标

让一个 `PreviewViewController` 可靠地处理 Markdown、ZIP、错误和不支持类型；连续预览不同文件时不串内容；错误状态有一致的呈现；日志足以排查扩展是否被调用。

## 允许改动

- `TapeekPreview/PreviewViewController.swift`
- `TapeekPreview/PreviewRouter.swift`（新建，可选）
- `TapeekPreview/PreviewErrorPresentation.swift`（新建）
- `TapeekPreview/MarkdownStateViews.swift`（只改错误映射调用）
- `TapeekPreview/ZipStateViews.swift`（只改错误映射调用）
- `docs/verification/T09.md`
- `docs/verification/T09-*.png`

## 禁止改动

- 不修改 Core 的解析语义。
- 不修改 Markdown 或 ZIP 的布局与交互，只整合入口和错误文案。
- 不添加新文件类型。
- 不改变扩展 Info.plist 的 UTI 声明。
- 不添加网络或文件写入。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
./scripts/build.sh
```

确认 T05 与 T08 的页面都能单独显示。

## 步骤

### 1. 统一错误展示

新建 `PreviewErrorPresentation.swift`：

```swift
struct PreviewErrorPresentation {
    let title: String
    let detail: String
    let symbolName: String

    init(failure: PreviewFailure, fileName: String)
}
```

要求：

- 所有 `PreviewFailure` 的文案集中在这里，Markdown 和 ZIP 的错误视图只调用它，不各自维护一份映射。
- 文案与两份功能规格一致。
- `fileTooLarge` 使用 `ByteCountFormatter`。
- `archiveUnsupported(message)` 使用可读的 message；如果 message 是内部标识，映射成用户文案。
- 不显示错误码、字节偏移、堆栈。
- `symbolName` 默认 `exclamationmark.triangle`；编码错误可用 `textformat.abc`；文件不可读可用 `doc.questionmark`。

更新 `MarkdownFailureView` 和 `ZipFailureView`，改为使用该结构，不改变布局。

### 2. 统一路由

`PreviewViewController` 的 `preparePreviewOfFile` 按以下顺序：

1. 记录开始时间（`ContinuousClock` 或 `Date`）。
2. 移除旧 hosting view：

```swift
hostingView?.removeFromSuperview()
hostingView = nil
```

3. `PreviewKindResolver.resolve(fileURL: url)`。
4. 构建根视图：

| Kind | 行为 |
| --- | --- |
| `.markdown` | `MarkdownLoader.load` → 空状态或 `MarkdownPreviewView` |
| `.zip` | `ZipArchiveReader.list` → `ZipTree` → 空/全跳过/`ZipPreviewView` |
| `.unsupported` | `UnsupportedPreviewView` |

5. 捕获 `PreviewFailure` 与未知错误，构建对应错误视图。
6. 创建新的 `NSHostingView`，添加到 `view`，设置四边约束。
7. 记录耗时和结果。
8. 调用 `handler(nil)`，且只调用一次。

要求：

- 路由不依赖文件内容或 MIME 猜测。
- 不缓存上一个文件的数据。
- 不在 `handler` 返回后启动任务。
- 不把错误传给 `handler`，除非扩展无法建立视图。
- 所有分支都必须产生一个可见视图，不能留下空白。

### 3. 不支持类型视图

`UnsupportedPreviewView`：

```
无法预览此文件类型
Tapeek 首版只支持 Markdown（.md、.markdown）和 ZIP（.zip）。
```

即使扩展声明只接受两种 UTI，也要保留这个兜底，避免系统或测试直接调用时空白。

### 4. 多文件重建

验证以下序列：

1. `gfm.md` → `front-matter.md`。
2. `typical.zip` → `empty.zip`。
3. `gfm.md` → `typical.zip`。
4. `corrupt.zip` → `gfm.md`。
5. 快速连续切换 5 次。

要求：

- 每次 `hostingView` 是新实例。
- 旧的展开状态、滚动位置、错误状态不残留。
- 不出现两个视图叠加。
- 不出现上一个文件的文件名、摘要或内容。
- 不崩溃。

### 5. 日志

在 `PreviewViewController` 使用 `os.Logger`：

```swift
import os

private let logger = Logger(
    subsystem: "com.local.Tapeek.Preview",
    category: "preview"
)
```

记录：

- 文件扩展名和 `PreviewKind`，不记录完整路径。
- 解析耗时。
- 成功/失败类型。
- 错误 case 名称，不记录文件内容。

示例：

```swift
logger.info("preview kind=\(kind) duration_ms=\(ms) result=success")
logger.error("preview kind=zip duration_ms=\(ms) result=failure case=archiveUnreadable")
```

验证：

```sh
log show --last 5m --predicate 'process == "TapeekPreview"' --style compact
```

日志用于确认扩展是否被调用，不作为功能验收的唯一证据。

### 6. 窗口尺寸

- 不设置固定 `preferredContentSize`。
- 内容和树在窄窗口下自适应。
- 调整 Quick Look 窗口大小，Markdown 正文重新换行，ZIP 摘要不横向溢出，树名称截断。
- 代码块和表格自身的横向滚动不受影响。

### 7. 构建与手工验证

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

按第 4 节序列在 Finder 中切换预览，并截图：

- `T09-01-markdown.png`
- `T09-02-zip.png`
- `T09-03-error.png`
- `T09-04-switch.png`
- `T09-05-narrow.png`

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| Markdown 路由 | 预览 `.md` | 显示 Markdown 视图 |
| ZIP 路由 | 预览 `.zip` | 显示目录树 |
| 不支持类型 | 直接调用或构造未知类型 | 显示兜底文案，不空白 |
| 错误 | 预览 `invalid-utf8.md`、`corrupt.zip` | 显示对应错误，不崩溃 |
| 多文件 | 按第 4 节序列切换 | 内容不串台 |
| 视图清理 | 连续切换 | 无旧视图叠加 |
| 日志 | `log show` | 能看到每次预览的 kind、耗时、结果 |
| 窄窗口 | 缩小窗口 | 无整页横向溢出 |
| 完成回调 | 观察行为 | 每次预览只完成一次，不重复刷新 |
| 无写入/联网 | 代码审查 + `find` | 符合约束 |

对应规格用例：QL-004、QL-005、QL-006、QL-007、QL-015、QL-016。

## 证据

`docs/verification/T09.md`：

- 切换序列的实际结果。
- `log show` 片段。
- 截图。
- 是否出现旧内容、空白、崩溃。
- 完成回调是否只调用一次（代码审查 + 日志）。

## 停止条件

- 多文件切换出现旧内容，且一次清理逻辑修正后仍复现。
- `handler` 被调用两次或从未调用。
- 扩展进程崩溃。
- 需要修改系统扩展选择或停用其他扩展。
- 需要放宽沙盒。

## 交接

给 T12：

- 稳定的统一入口。
- 错误文案与日志格式。
- 多文件切换的验证方法。
- 已知的窗口尺寸行为。
