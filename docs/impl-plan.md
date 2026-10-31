# Tapeek 实施计划

| 项目 | 内容 |
| --- | --- |
| 状态 | 方案基线，等待实施 |
| 版本 | 0.1 |
| 日期 | 2026-10-31 |
| 目标系统 | macOS 27.x，arm64 |
| 对应需求 | [PRD](PRD.md) |
| 对应规格 | [功能规格](specs/README.md) |
| 对应任务 | [执行 tickets](tickets/README.md) |

## 1. 文档用途

本文说明如何把 PRD 落成可运行的本机 App。读者是执行 agent，而不是最终用户。文档给出模块边界、公开接口、构建命令、技术探针、失败回退和完成定义。执行时以 ticket 为最小工作单元，不按本文一次性重写整个工程。

本轮只创建文档，未生成 Xcode 工程、未编译、未安装扩展。文中所有系统行为都标注为「已验证」「待探针」或「假设」，不得把待验证项当成事实写进完成报告。

## 2. 环境基线

| 项 | 实测值 |
| --- | --- |
| 工作目录 | `/Users/jared/Personal Projects/Tapeek` |
| 系统 | macOS 27.0，build 26A428 |
| 架构 | arm64 |
| Xcode | 27.0（27A266a） |
| Swift | 6.4 |
| macOS SDK | 27.0 |
| XcodeGen | 2.45.3，路径 `/opt/homebrew/bin/xcodegen` |
| SwiftLint | 0.63.2 |
| Python | `/usr/bin/python3`，3.9，标准库 `zipfile` 可用 |
| 签名 | 钥匙串存在有效开发身份；首版先尝试 ad-hoc，不默认绑定团队 |
| 已有扩展 | Bear Quick Look 扩展已注册；技术核查未见其 Info.plist 声明 `QLSupportedContentTypes`，是否处理 `.md` 待日志确认 |

`.md` 与 `.markdown` 的系统 UTI 均为 `net.daringfireball.markdown`；`.zip` 为 `public.zip-archive`。这两个值由本机 `mdls` 和 `UTType(filenameExtension:)` 验证。

## 3. 总体架构

```
Finder / qlmanage
        │
        ▼
系统 Quick Look 宿主
        │ 加载
        ▼
TapeekPreview.appex（沙盒）
  ├─ PreviewViewController：系统适配、路由、生命周期
  ├─ MarkdownPreviewView：SwiftUI + MarkdownUI
  └─ ZipPreviewView：SwiftUI 目录树
        │ 调用
        ▼
TapeekCore（本地 Swift Package，纯逻辑、可单测）
  ├─ MarkdownLoader / FrontMatter
  └─ ZipArchiveReader / ZipTree
        ▲
        │ 同一份代码
Tapeek.app（沙盒，宿主 App）
  └─ 单页启用说明与示例入口
```

设计约束：

- 扩展只做系统适配和视图组合，解析、规范化、排序、摘要全部放在 `TapeekCore`。
- Core 不依赖 SwiftUI、AppKit 或 Quick Look，便于用 `swift test` 验证。
- 首版同步解析。文件大小和条目数都有硬上限，避免在 Quick Look 的短生命周期内做不可控工作。
- 预览不写入用户目录，不创建临时解压目录，不发起网络请求。

## 4. 仓库结构

```
Tapeek/
├── project.yml
├── README.md
├── .gitignore
├── docs/
│   ├── PRD.md
│   ├── impl-plan.md
│   ├── specs/
│   │   ├── README.md
│   │   ├── markdown-preview.md
│   │   ├── zip-preview.md
│   │   ├── quicklook-integration.md
│   │   ├── host-app.md
│   │   └── testing-and-fixtures.md
│   ├── tickets/
│   │   ├── README.md
│   │   └── T01-...md … T13-...md
│   └── verification/
│       ├── README.md
│       └── TEMPLATE.md
├── Packages/
│   └── TapeekCore/
│       ├── Package.swift
│       ├── Sources/TapeekCore/
│       │   ├── PreviewLimits.swift
│       │   ├── PreviewFailure.swift
│       │   ├── PreviewKind.swift
│       │   ├── ByteReader.swift
│       │   ├── Markdown/
│       │   │   ├── MarkdownDocument.swift
│       │   │   ├── MarkdownLoader.swift
│       │   │   ├── FrontMatter.swift
│       │   │   └── ImageAltIndex.swift
│       │   └── Archive/
│       │       ├── ZipEntry.swift
│       │       ├── ZipListing.swift
│       │       ├── ZipArchiveReader.swift
│       │       └── ZipTree.swift
│       ├── Sources/TapeekBench/
│       │   └── TapeekBench.swift
│       └── Tests/TapeekCoreTests/
├── TapeekApp/
│   ├── TapeekApp.swift
│   ├── OnboardingView.swift
│   ├── Info.plist
│   ├── TapeekApp.entitlements
│   └── Resources/Samples/
├── TapeekPreview/
│   ├── PreviewViewController.swift
│   ├── PreviewErrorPresentation.swift
│   ├── MarkdownPreviewView.swift
│   ├── LocalImageProvider.swift
│   ├── PreviewTheme.swift
│   ├── MarkdownStateViews.swift
│   ├── ZipPreviewView.swift
│   ├── ZipTreeView.swift
│   ├── ZipStateViews.swift
│   ├── Info.plist
│   └── TapeekPreview.entitlements
├── Samples/
│   ├── markdown/
│   └── zip/
├── scripts/
│   ├── generate.sh
│   ├── build.sh
│   ├── install-local.sh
│   ├── uninstall-local.sh
│   ├── verify-extension.sh
│   ├── make-fixtures.py
│   └── run-tests.sh
└── .build/                  # 忽略
```

`Samples/zip` 中提交可复现的二进制样本；生成脚本必须能重建它们。大文件样本不提交，由脚本生成到 `.build/fixtures/`（忽略）。

## 5. 技术选型与决策门

| 领域 | 首选 | 理由 | 失败回退 |
| --- | --- | --- | --- |
| 预览接入 | 系统 Quick Look 预览扩展，view-based `QLPreviewingController` | 保留 Finder 空格；SwiftUI 原生滚动、选择与明暗模式 | 若 view-based 在当前系统异常，改用 data-based HTML |
| Markdown 渲染 | MarkdownUI 2.4.1 | 原生 SwiftUI，GFM 覆盖广，代码块自带横向滚动；该库处于维护模式，固定版本使用 | 用 swift-markdown 解析后自绘；或 data-based HTML |
| Markdown 图片 | 自定义 `ImageProvider`，只读本地文件 | 默认 provider 会联网，必须替换 | 图片全部显示占位，正文继续 |
| ZIP 目录 | 自写 central directory 读取器，不引入解压库 | 只读元数据；可精确处理加密标记、ZIP64、旧式文件名编码 | 用 ZIPFoundation 0.9.20，接受加密条目被跳过的限制 |
| 工程生成 | XcodeGen `project.yml` | 文本化、可重复、适合 agent 执行 | 手工 Xcode 工程（不推荐） |
| 签名 | ad-hoc（`CODE_SIGN_IDENTITY="-"`） | 本机自用，不绑定账号 | 经用户同意后改用 Apple Development |
| 测试 | SwiftPM `swift test` + 脚本 + 手工截图 | Core 可自动测，UI 需真实 Quick Look | 无 |

**决策门 D1（T01 完成后）**：若 ad-hoc 签名的扩展无法注册或被系统忽略，停止后续 UI 工作，先解决签名，不把失败归因于代码。

**决策门 D2（T02 完成后）**：若 MarkdownUI 在当前扩展进程中无法稳定渲染，记录现象，改用 data-based HTML 方案；不要同时维护两套渲染器。

**决策门 D3（T06 完成后）**：若自写 ZIP 读取器在标准样本上与 `unzip -Z1` 不一致，先修解析器；若连续两次无法修复，改用 ZIPFoundation，并在规格中把加密条目和旧式编码标为限制。

## 6. 工程配置

### 6.1 Bundle 标识

| 目标 | Bundle ID | 说明 |
| --- | --- | --- |
| 宿主 App | `com.local.Tapeek` | 本机自用，不使用公司或他人域名 |
| 预览扩展 | `com.local.Tapeek.Preview` | 必须位于宿主 `Contents/PlugIns/TapeekPreview.appex` |
| Core 包 | `TapeekCore` | 本地 Swift Package，不单独分发 |

如果实施时发现 `com.local` 与现有标识冲突，统一替换为 `com.<用户名>.Tapeek`，并同步所有文档与脚本中的 `pluginkit` 命令。

### 6.2 `project.yml` 参考

以下片段是实施起点，T01 必须在真实环境中验证并修正。参数名以 XcodeGen 2.45.3 为准。

```yaml
name: Tapeek
options:
  bundleIdPrefix: com.local
  deploymentTarget:
    macOS: "27.0"
  createIntermediateGroups: true

packages:
  TapeekCore:
    path: Packages/TapeekCore
  MarkdownUI:
    url: https://github.com/gonzalezreal/swift-markdown-ui
    exactVersion: 2.4.1

settings:
  base:
    SWIFT_VERSION: "5.0"
    MACOSX_DEPLOYMENT_TARGET: "27.0"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    PROVISIONING_PROFILE_SPECIFIER: ""
    ENABLE_HARDENED_RUNTIME: NO

targets:
  Tapeek:
    type: application
    platform: macOS
    sources: [TapeekApp]
    dependencies:
      - target: TapeekPreview
        embed: true
        codeSign: true
    info:
      path: TapeekApp/Info.plist
      properties:
        CFBundleDisplayName: Tapeek
        LSMinimumSystemVersion: "27.0"
    entitlements:
      path: TapeekApp/TapeekApp.entitlements
      properties:
        com.apple.security.app-sandbox: true

  TapeekPreview:
    type: app-extension
    platform: macOS
    sources: [TapeekPreview]
    settings:
      base:
        APPLICATION_EXTENSION_API_ONLY: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.local.Tapeek.Preview
    dependencies:
      - package: TapeekCore
      - package: MarkdownUI
    info:
      path: TapeekPreview/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.quicklook.preview
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).PreviewViewController
          NSExtensionAttributes:
            QLSupportedContentTypes:
              - net.daringfireball.markdown
              - public.zip-archive
            QLSupportsSearchableItems: false
    entitlements:
      path: TapeekPreview/TapeekPreview.entitlements
      properties:
        com.apple.security.app-sandbox: true

schemes:
  Tapeek:
    build:
      targets:
        Tapeek: all
    run:
      config: Debug
```

XcodeGen 默认是否生成 scheme 取决于版本；显式声明 `schemes`，避免 `xcodebuild -scheme Tapeek` 找不到 scheme。

扩展 entitlements 首版只保留 `com.apple.security.app-sandbox`。不添加网络、全盘访问或临时例外。若 T02 证明同目录图片无法读取，按规格显示占位，不通过放宽权限绕过。

### 6.3 版本与语言模式

- 部署目标固定 `27.0`，不写兼容分支。
- Swift 语言模式先用 `5.0`。Core 的公开类型仍标注 `Sendable`，为后续迁移保留空间。
- 不启用严格并发检查；若编译器因 MarkdownUI 产生并发警告，记录但不阻塞首版。
- 关闭 Hardened Runtime 仅用于本机 ad-hoc；若改用 Developer ID 分发，另开 ticket 评估。

## 7. 构建、安装与验证命令

所有脚本使用 `set -eu`，从仓库根目录运行，路径用绝对路径推导，不依赖当前目录。

### 7.1 生成工程

```sh
cd "/Users/jared/Personal Projects/Tapeek"
xcodegen generate --spec project.yml
```

预期：生成 `Tapeek.xcodeproj`，包含 `Tapeek`、`TapeekPreview` 两个 target 和本地包 `TapeekCore`。

### 7.2 构建

```sh
xcodebuild \
  -project Tapeek.xcodeproj \
  -scheme Tapeek \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
```

预期产物：

```
.build/DerivedData/Build/Products/Debug/Tapeek.app
.build/DerivedData/Build/Products/Debug/Tapeek.app/Contents/PlugIns/TapeekPreview.appex
```

### 7.3 本机安装

安装到 `~/Applications`，避免使用 `sudo`。

```sh
DEST="$HOME/Applications/Tapeek.app"
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
ditto ".build/DerivedData/Build/Products/Debug/Tapeek.app" "$DEST"
codesign --verify --deep --strict --verbose=2 "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/TapeekPreview.appex"
open "$DEST"
qlmanage -r
```

`lsregister` 或 `pluginkit -a` 的路径若在当前系统变化，脚本应打印失败命令和退出码，不静默继续。

### 7.4 检查扩展注册

```sh
pluginkit -m -p com.apple.quicklook.preview | grep -F "com.local.Tapeek.Preview"
```

预期看到扩展条目。`pluginkit -m` 前缀的含义以当前系统输出为准，不把 `+` 或 `-` 写死为启用状态。

强制本扩展优先：

```sh
pluginkit -e use -i com.local.Tapeek.Preview
```

若仍被其他扩展抢先，不要执行 `pluginkit -e ignore` 停用对方，先记录阻塞并请求用户决定。

### 7.5 烟雾测试

```sh
qlmanage -p Samples/markdown/smoke.md
```

预期打开 Quick Look 窗口，画面包含唯一字符串 `TAPEEK-SMOKE`。关闭窗口后命令返回。

无界面输出测试：

```sh
mkdir -p /tmp/tapeek-ql
qlmanage -p -o /tmp/tapeek-ql Samples/markdown/gfm.md
find /tmp/tapeek-ql -maxdepth 3 -type f
```

`-o` 的实际输出结构需在 T01/T12 记录；如果当前系统不输出预览文件，不把该命令作为自动验收，只保留窗口截图。

### 7.6 卸载

```sh
pluginkit -e ignore -i com.local.Tapeek.Preview || true
pluginkit -r "$HOME/Applications/Tapeek.app/Contents/PlugIns/TapeekPreview.appex" || true
rm -rf "$HOME/Applications/Tapeek.app"
qlmanage -r
```

只删除 Tapeek 自己的 App 和扩展注册，不删除用户文件、不修改 Bear 的设置。

## 8. 技术探针

探针只回答「这个系统路径是否可用」，不追求产品完成度。结果写入 `docs/verification/`，并在 `findings.md` 更新事实。

### P0-1 签名、注册与最小预览（T01）

步骤：

1. 用最小宿主 App 和扩展构建，扩展只显示静态文本 `TAPEEK-SMOKE`。
2. 按 7.3 安装，按 7.4 检查注册。
3. 运行 7.5 的 `qlmanage -p`，截图。

通过标准：

- `codesign --verify --deep --strict` 返回 0。
- `pluginkit` 能看到 `com.local.Tapeek.Preview`。
- Quick Look 窗口显示 `TAPEEK-SMOKE`。
- 没有崩溃日志。

失败处理：

- 签名失败：记录完整 `codesign` 与 `pluginkit` 输出，停止，不尝试关闭系统完整性保护。
- ad-hoc 已注册但 Finder 仍回退：记录 TN3127 所述签名要求变化问题；不要反复重签同一构建，改为请求用户同意使用开发证书。
- 扩展未注册：检查 `.appex` 是否在 `Contents/PlugIns`，`NSExtensionPointIdentifier` 是否为 `com.apple.quicklook.preview`。
- Quick Look 仍显示系统默认内容：先 `qlmanage -r`，再 `pluginkit -e use`；仍失败则记录冲突。

### P0-2 MarkdownUI 与图片访问（T02）

步骤：

1. 用 `MarkdownUI` 渲染 `Samples/markdown/gfm.md`。
2. 同目录放 `assets/pixel.png`，文档用相对路径引用；再放一个 `https://example.com/x.png` 远程引用。
3. 分别截图浅色、深色。
4. 在 `log stream` 或代码审查中确认没有网络请求。

通过标准：

- 标题、列表、表格、代码块、任务列表可读。
- 代码块长行可横向滚动。
- 远程图片不加载，显示占位或替代文字，正文不阻塞。
- 相对图片：Apple 论坛 773050 与 QLMarkdown 有沙盒拒绝读取的明确报告，默认预期是「不可读」；本机若可读，记录「好于默认预期」。两种结果都只影响图片，不影响正文。
- 预览打开后 1 秒内出现内容。

失败处理：

- MarkdownUI 编译失败或运行时崩溃：改用 data-based HTML，不再尝试在 WKWebView 中修补。
- 相对图片不可读：接受占位，更新 PRD 和验收用例，不添加全盘访问权限。

### P0-3 扩展选择与多文件切换（T04/T09 前）

步骤：

1. 在 Bear 扩展启用的情况下，用 `pluginkit -e use` 让 Tapeek 优先。
2. 依次预览两个不同的 `.md` 文件，再预览一个 `.zip`。
3. 观察窗口内容是否与当前文件一致。

通过标准：

- Tapeek 被选中，或明确记录系统仍选择 Bear 的行为。
- 连续切换不残留上一个文件的内容。
- ZIP 与 Markdown 路由正确。

失败处理：

- 系统仍选择其他扩展（包括 Bear）：记录为环境冲突。T12 的手工验收可临时要求用户手动在系统设置中调整顺序；不自动停用其他扩展。
- 内容串台：视为生命周期 bug，回到 T09 修复。

### P0-4 ZIP 目录读取（T06）

步骤：

1. 用 `Samples/zip/typical.zip` 和 `Samples/zip/zip64-entry.zip` 运行 Core 单元测试；完整 ZIP64 EOCD 由 T11 的 70,000 条样本覆盖。
2. 用 `unzip -Z1` 输出条目名，与解析结果逐项比较。
3. 记录 20,000 条样本的读取耗时和内存峰值。

通过标准：

- 条目名、目录/文件类型、未压缩大小与 `unzip -Z1`/`unzip -l` 一致。
- 加密样本能被识别并显示标注，不误报为空包。
- 损坏样本返回明确错误，不崩溃。
- 20,000 条样本在 1 秒内完成列表构建。

失败处理：

- 与 `unzip` 不一致：先修解析器；两次修复仍失败则切换 ZIPFoundation，并在规格中记录限制。

## 9. Core 公开契约

执行 agent 可以增加内部类型，但下列类型和语义是 UI、测试与规格的共同边界。命名可以按 Swift 风格微调，语义不得改变。

### 9.1 限制与错误

```swift
public struct PreviewLimits: Equatable, Sendable {
    public var maxMarkdownBytes: Int          // 默认 2 * 1024 * 1024
    public var maxZipEntries: Int             // 默认 20_000
    public var maxZipPathBytes: Int           // 默认 4_096
    public var maxZipPathDepth: Int           // 默认 256
    public var maxZipCentralDirectoryBytes: Int // 默认 16 * 1024 * 1024
    public var maxZipListingDuration: TimeInterval // 默认 2.0
    public var maxImageBytes: Int             // 默认 20 * 1024 * 1024
    public var maxImagePixelSize: Int         // 默认 4_096
    public static let `default`: PreviewLimits
}

public enum PreviewFailure: Error, Equatable, Sendable {
    case unreadableFile
    case unsupportedTextEncoding
    case fileTooLarge(actualBytes: Int, limitBytes: Int)
    case archiveUnreadable
    case archiveEncrypted
    case archiveUnsupported(message: String)
    case listingTimedOut
}
```

`archiveEncrypted` 只在 central directory 本身无法读取时使用；能列出条目但条目带加密标记时，返回正常列表并设置 `hasEncryptedEntries = true`，不抛错。

### 9.2 预览类型

```swift
public enum PreviewKind: Equatable, Sendable {
    case markdown
    case zip
    case unsupported
}

public enum PreviewKindResolver {
    public static func resolve(fileURL: URL) -> PreviewKind
    public static func resolve(pathExtension: String) -> PreviewKind
}
```

规则：优先使用 `URLResourceKey.contentTypeKey`；取不到时按扩展名。`.md`、`.markdown`、`.mdown`、`.mkd` 为 Markdown；`.zip` 为 ZIP；其余为 unsupported。大小写不敏感。

### 9.3 Markdown

```swift
public struct FrontMatterEntry: Equatable, Sendable {
    public let key: String
    public let value: String
}

public struct MarkdownDocument: Equatable, Sendable {
    public let body: String
    public let frontMatter: [FrontMatterEntry]
    public let byteCount: Int
    public let encoding: MarkdownTextEncoding
    public let baseURL: URL
}

public enum MarkdownTextEncoding: String, Equatable, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian
}

public enum MarkdownLoader {
    public static func load(
        url: URL,
        limits: PreviewLimits = .default
    ) throws -> MarkdownDocument

    public static func load(
        data: Data,
        baseURL: URL,
        limits: PreviewLimits = .default
    ) throws -> MarkdownDocument
}
```

语义：

- 文件大于 `maxMarkdownBytes` 时抛 `fileTooLarge`，不返回部分正文。
- 支持 UTF-8、UTF-8 BOM、UTF-16 LE/BE BOM；其他编码抛 `unsupportedTextEncoding`。
- 空文件返回空 `body`，不抛错。
- `frontMatter` 只包含扁平键值；没有合法前置元数据时为空数组。
- `body` 已移除前置元数据块。
- `baseURL` 是文件所在目录，用于解析相对链接与图片。

### 9.4 ZIP

```swift
public enum ZipEntryKind: String, Equatable, Sendable {
    case file, directory, symlink
}

public struct ZipEntry: Equatable, Sendable, Identifiable {
    public let id: String                  // 规范化后的 NFC 路径
    public let path: String                // 规范化路径，目录不带尾斜杠
    public let name: String                // 最后一段
    public let kind: ZipEntryKind
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let isEncrypted: Bool
}

public enum ZipWarning: Equatable, Sendable {
    case duplicatePath(String)
    case unsafePath(String)
    case invalidUTF8Name
    case guessedLegacyEncoding
    case truncated(shown: Int, total: Int?)
    case timedOut(shown: Int, total: Int?)
    case encryptedEntries(count: Int)
    case multiDiskUnsupported
    case malformedEntry(offset: Int)
}

public struct ZipListing: Equatable, Sendable {
    public let entries: [ZipEntry]
    public let shownEntryCount: Int
    public let totalEntryCount: Int?
    public let skippedEntryCount: Int
    public let isTruncated: Bool
    public let fileCount: Int
    public let directoryCount: Int
    public let totalUncompressedBytes: UInt64
    public let archiveBytes: UInt64
    public let hasEncryptedEntries: Bool
    public let warnings: [ZipWarning]
}

public enum ZipArchiveReader {
    public static func list(
        url: URL,
        limits: PreviewLimits = .default
    ) throws -> ZipListing
}
```

语义：

- 只读取 EOCD、ZIP64 记录和 central directory，不解压任何条目，不写入磁盘。
- `shownEntryCount` 是实际解析并纳入模型的条目数；`totalEntryCount` 在 EOCD 可读时给出，否则为 `nil`。
- 超过 `maxZipEntries` 或时间上限时返回部分列表，并附带 `truncated` 或 `timedOut` 警告。
- 加密条目仍列出，`isEncrypted = true`，并汇总 `hasEncryptedEntries`。
- `fileCount` 与 `directoryCount` 只统计显式条目；树视图使用 `ZipTree` 的计数（含合成父目录）。
- 路径规范化、去重、父目录合成规则见 [ZIP 规格](specs/zip-preview.md)。

### 9.5 树与行

```swift
public struct ZipTree: Equatable, Sendable {
    public let root: ZipNode
    public let listing: ZipListing
    public let fileCount: Int        // 包含文件与符号链接
    public let directoryCount: Int   // 包含显式目录与合成目录，不含根

    public init(listing: ZipListing, archiveName: String)
    public func rows(expanded: Set<String>) -> [ZipRow]
    public func defaultExpandedIDs() -> Set<String>
}

public struct ZipNode: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let path: String
    public let kind: ZipEntryKind
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let isEncrypted: Bool
    public let children: [ZipNode]
}

public struct ZipRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let node: ZipNode
    public let depth: Int
    public let isExpanded: Bool
}
```

`rows(expanded:)` 是纯函数，按树深度优先输出当前可见行。展开状态只影响返回值，不修改树。

## 10. 实施顺序

阶段与 ticket 对应：

| 阶段 | Tickets | 结果 |
| --- | --- | --- |
| A. 骨架与系统接入 | T01 | 可注册、可显示静态内容的扩展 |
| B. 技术探针 | T02 | MarkdownUI、图片和明暗模式结论 |
| C. Core 基础 | T03 | 限制、错误、字节读取、测试骨架 |
| D. Markdown | T04 → T05 | 加载、前置元数据、正式预览 UI |
| E. ZIP | T06 → T07 → T08 | 目录解析、树模型、树 UI |
| F. 整合 | T09 | 路由、生命周期、统一错误状态 |
| G. 宿主体验 | T10 | 启用说明与示例入口 |
| H. 测试与交付 | T11 → T12 → T13 | 夹具、性能、安装脚本、验收记录 |

并行规则：

- T02 与 T03 可在 T01 后并行，但不要同时改 `project.yml`。
- T04 与 T06 可在 T03 后并行，分别只改 `Markdown/` 和 `Archive/`。
- T05 与 T08 可在各自 Core 完成后并行，但共用 `PreviewTheme.swift` 时先由 T05 建立，T08 只读复用。
- 同一文件同一时间只由一个执行者修改。冲突时以 ticket 的「允许改动」为准。

## 11. 测试策略

### 11.1 自动化

- Core 单元测试：`swift test --package-path Packages/TapeekCore`。
- 覆盖：编码、前置元数据、限额、路径规范化、ZIP 字段解析、ZIP64、加密标记、树构建、排序、展开行、错误映射。
- 夹具对比：对每个 ZIP 样本运行 `unzip -Z1`，把条目列表保存为 `.expected.txt`，测试逐行比较。
- 静态检查：`swiftlint lint --strict` 只作为提示，不阻塞首版；若阻塞，记录规则编号并单独处理。
- 构建检查：`xcodebuild` 必须无错误；警告数量记录在验收文件中，不要求零警告。

### 11.2 手工

UI 和系统集成无法只靠单元测试。T12 按以下顺序执行：

1. 安装并注册扩展。
2. 预览 `Samples/markdown/gfm.md`，截图浅色。
3. 切换系统深色外观，重复截图。
4. 预览 `Samples/markdown/front-matter.md`，确认元数据卡片。
5. 预览 `Samples/markdown/relative-image.md`，记录图片显示或占位。
6. 预览 `Samples/markdown/invalid-utf8.md`，确认错误文案。
7. 预览 `Samples/zip/typical.zip`，展开两层，截图。
8. 预览 `Samples/zip/empty.zip`、`encrypted.zip`、`corrupt.zip`、`zip64.zip`，逐项记录。
9. 连续切换 Markdown 与 ZIP，确认不串内容。
10. 预览前后对样本目录执行 `find`，确认没有新增解压文件。

### 11.3 证据格式

每个 ticket 在 `docs/verification/Txx.md` 记录：

```markdown
# Txx 验收记录

- 执行日期：
- 执行者：
- 环境：macOS 27.0 / Xcode 27.0 / arm64

## 命令与结果
| 命令 | 退出码 | 关键输出 |
| --- | --- | --- |

## 截图
- `Txx-01.png`：说明

## 未通过项
| 项 | 现象 | 处理 |
| --- | --- | --- |

## 结论
通过 / 阻塞 / 部分通过（列出未覆盖项）
```

没有命令输出或截图的项目，不得写「通过」。

## 12. 性能与资源

首版目标：

| 场景 | 目标 | 测量方式 |
| --- | --- | --- |
| 典型 README（≤ 100 KB） | 解析 ≤ 100 ms，预览 ≤ 1 s 出现内容 | `TapeekBench` 或 XCTest 计时，取 3 次中位数 |
| 中等笔记（约 500 KB） | 解析 ≤ 300 ms | 同上 |
| ZIP 1,000 条 | 列表 ≤ 200 ms | 同上 |
| ZIP 20,000 条 | 列表 ≤ 1 s | 同上 |
| 超过上限的 Markdown | 立即返回 `fileTooLarge` | 单元测试 |
| 超过 20,000 条的 ZIP | 部分列表 + 截断提示 ≤ 1 s | 单元测试 + 手工 |

测时使用 `ContinuousClock` 或 `Date`，记录机器、系统版本和样本大小。目标不是硬性 SLA；未达标时记录实际值，并判断是否影响使用。若超过 2 秒，必须降低上限或优化后再交付。

内存约束：

- Markdown 最多读取 2 MiB。
- ZIP central directory 最多读取 16 MiB；条目模型最多 20,000 条。
- 不把整个 ZIP 读入内存；用 `FileHandle` 读取尾部窗口和目录区。
- 不缓存跨文件结果；每次预览重新读取，避免陈旧内容。

## 13. 风险与回退

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| ad-hoc 签名扩展不被注册或 Finder 仍回退 | 无法进入 Quick Look | T01 先验证；注意 TN3127 的签名要求变化；失败则请求用户同意使用开发证书 |
| Bear 扩展抢占 `.md` | 预览不是 Tapeek | 先用 `pluginkit -e use`；日志确认 Bear 是否真的处理 `.md`；仍失败则记录，不擅自停用 Bear |
| 相对图片被沙盒拒绝 | README 图片缺失 | 显示替代文字/占位，正文不受影响；更新验收 |
| MarkdownUI 在扩展中崩溃 | 无法预览 | 切 data-based HTML；不保留 WKWebView 路线 |
| 自写 ZIP 解析器遗漏边界 | 错误列表或崩溃 | 夹具覆盖 ZIP64、加密、损坏、GBK、重复路径；与 `unzip` 对比 |
| ZIP 文件名编码无法判定 | 中文乱码 | UTF-8 优先，CP437 回退，GB18030 启发式；仍不确定时显示原始名称并提示 |
| 大文件超时 | 预览空白 | 硬上限 + 截断/错误提示；不无限等待 |
| Quick Look 缓存旧扩展 | 改动不生效 | `qlmanage -r`，重新安装，重启 Finder 仅在必要时使用 |
| 扩展生命周期复用导致串内容 | 显示上一个文件 | 每次 `preparePreviewOfFile` 重建 hosting view；T09 专项验证 |

## 14. 完成定义

MVP 完成必须同时满足：

1. PRD 第 8 节的六条验收标准全部有证据。
2. T01 至 T13 全部关闭，或有用户确认的明确例外。
3. `swift test` 全部通过；`xcodebuild` 构建成功；`codesign --verify --deep --strict` 通过。
4. `docs/verification/FINAL.md` 包含逐项通过/失败表和已知限制。
5. 安装、卸载脚本可重复执行，不残留扩展注册。
6. 没有为了通过验收而放宽沙盒、添加网络权限或写入用户目录。

## 15. 执行 Agent 工作协议

每个 ticket 独立执行，遵守以下规则：

1. 先读 ticket、PRD 对应章节、规格对应章节和本计划第 9 节契约。
2. 只改 ticket 的「允许改动」范围。需要越界时停止，在 ticket 中写阻塞原因，不自行扩大范围。
3. 先写测试或夹具，再写实现；至少覆盖 ticket 列出的验收用例。
4. 每完成一步，把命令、退出码和关键输出写入 `docs/verification/Txx.md`，不要凭记忆补写。
5. 不修改 `docs/PRD.md` 的需求结论；发现需求矛盾时记录到 ticket 的「问题」并请求协调者决定。
6. 不安装新的全局工具；使用已安装的 XcodeGen、Swift、Python。需要新依赖时先说明理由并等待批准。
7. 不执行 `sudo`、不关闭 SIP、不修改 Bear 或其他 App 的扩展状态。
8. 遇到连续两次相同失败，停止并记录，不进行第三次相同尝试。
9. 完成后只汇报：改了什么、验证了什么、还有什么未验证。不要用「应该可以」代替证据。

## 16. 后续工作

以下不在本轮范围：公开发布、公证、自动更新、App Store、多语言、Intel 兼容、Markdown 编辑、ZIP 解压、包内文件预览、远程图片、公式、Mermaid、文内搜索。需要时单独立项，不塞进 MVP。
