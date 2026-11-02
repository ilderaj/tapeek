# T03 Core 基础类型

| 项 | 内容 |
| --- | --- |
| ID | T03 |
| 状态 | 完成 |
| 依赖 | T01 |
| 执行角色 | executor；接口由 thinker 复核 |
| 预计产物 | `TapeekCore` 本地包、限制、错误、类型路由、字节读取与测试骨架 |

## 必读

- [实施计划](../impl-plan.md) §4、§9.1、§9.2、§9.4。
- [Markdown 规格](../specs/markdown-preview.md) §3.2。
- [ZIP 规格](../specs/zip-preview.md) §9。
- [测试规格](../specs/testing-and-fixtures.md) §5。

## 目标

建立不依赖 SwiftUI/AppKit 的 Core 包。此 ticket 只提供基础设施和测试，不实现 Markdown 解析或 ZIP 解析。

## 允许改动

- `Packages/TapeekCore/Package.swift`
- `Packages/TapeekCore/Sources/TapeekCore/PreviewLimits.swift`
- `Packages/TapeekCore/Sources/TapeekCore/PreviewFailure.swift`
- `Packages/TapeekCore/Sources/TapeekCore/PreviewKind.swift`
- `Packages/TapeekCore/Sources/TapeekCore/ByteReader.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/PreviewLimitsTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/PreviewKindTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/ByteReaderTests.swift`
- `project.yml`（添加本地包和扩展依赖）
- `docs/verification/T03.md`

## 禁止改动

- 不实现 `MarkdownLoader`、`ZipArchiveReader`、`ZipTree`。
- 不修改 `TapeekPreview` 的视图或路由。
- 不添加第三方依赖。
- 不改变 T01 的 Bundle ID、签名或扩展声明。

## 前置检查

```sh
swift --version
xcodebuild -version
./scripts/build.sh
```

确认 T01 仍可构建。若不可构建，先修复 T01。

## 步骤

### 1. 创建 Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapeekCore",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "TapeekCore", targets: ["TapeekCore"])
    ],
    targets: [
        .target(name: "TapeekCore"),
        .testTarget(
            name: "TapeekCoreTests",
            dependencies: ["TapeekCore"]
        )
    ]
)
```

若 SwiftPM 不接受 `.macOS("27.0")`，改为 `.macOS(.v14)` 并记录；App target 的部署目标仍为 27.0。

### 2. 实现 PreviewLimits

```swift
public struct PreviewLimits: Equatable, Sendable {
    public var maxMarkdownBytes: Int
    public var maxZipEntries: Int
    public var maxZipPathBytes: Int
    public var maxZipPathDepth: Int
    public var maxZipCentralDirectoryBytes: Int
    public var maxZipListingDuration: TimeInterval
    public var maxImageBytes: Int
    public var maxImagePixelSize: Int

    public init(
        maxMarkdownBytes: Int = 2 * 1024 * 1024,
        maxZipEntries: Int = 20_000,
        maxZipPathBytes: Int = 4_096,
        maxZipPathDepth: Int = 256,
        maxZipCentralDirectoryBytes: Int = 16 * 1024 * 1024,
        maxZipListingDuration: TimeInterval = 2.0,
        maxImageBytes: Int = 20 * 1024 * 1024,
        maxImagePixelSize: Int = 4_096
    ) { ... }

    public static let `default` = PreviewLimits()
}
```

要求：

- 所有值必须为正。
- 不提供静默的 `0` 表示无限；0 视为非法，测试应覆盖。
- `default` 的数值与实施计划一致。
- `maxZipPathDepth` 默认 256，防止深层路径导致递归或投影栈溢出。

### 3. 实现 PreviewFailure

```swift
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

要求：

- 不在此类型中放中文文案；文案由视图层映射。
- `fileTooLarge` 的实际值和上限都保留，便于错误视图显示。
- `archiveUnsupported` 的 message 是稳定的短原因，不拼接用户文件内容。
- 可以增加内部错误类型，但公开 API 只使用以上 case。

### 4. 实现 PreviewKind

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

规则：

- `resolve(pathExtension:)` 忽略大小写和前导点；`.md`、`.markdown`、`.mdown`、`.mkd` → markdown；`.zip` → zip；其余 → unsupported。
- `resolve(fileURL:)` 优先读取 `URLResourceKey.contentTypeKey`：
  - `UTType` 符合 `public.zip-archive` → zip。
  - `UTType` 符合 `net.daringfireball.markdown` → markdown。
  - 取不到或不符合时回退到扩展名。
- 不把 `public.plain-text` 当作 Markdown，避免误路由普通文本。

测试：

- 扩展名大小写。
- 未知扩展名。
- 一个真实临时 `.md` 文件的 `contentType` 路由。
- 一个真实临时 `.zip` 文件的 `contentType` 路由。

### 5. 实现 ByteReader

内部工具，供 ZIP 解析使用：

```swift
struct ByteReader {
    let data: Data

    func readUInt16LE(at offset: Int) throws -> UInt16
    func readUInt32LE(at offset: Int) throws -> UInt32
    func readUInt64LE(at offset: Int) throws -> UInt64
    func readBytes(at offset: Int, count: Int) throws -> Data
}
```

要求：

- 所有读取先检查 `offset >= 0`、`count >= 0`、`offset + count <= data.count`，避免整数溢出。
- 越界抛 `ByteReaderError.outOfBounds(offset:count:available:)`。
- 小端解析使用显式移位，不依赖主机字节序。
- 不为越界返回 0；错误必须可见。
- 测试覆盖：正常值、边界（刚好读到最后字节）、越界 1 字节、空数据、负偏移、超大 count。

### 6. 添加本地包到 project.yml

在 `packages` 添加：

```yaml
  TapeekCore:
    path: Packages/TapeekCore
```

若 T02 已经修改过 `project.yml`，只追加 TapeekCore 条目和依赖，不覆盖 MarkdownUI 的声明。

在 `TapeekPreview` 的 `dependencies` 添加：

```yaml
      - package: TapeekCore
```

此时扩展还没有调用 Core，但应能构建。

### 7. 运行测试与构建

```sh
swift test --package-path Packages/TapeekCore
./scripts/generate.sh
./scripts/build.sh
```

记录输出。

## 验收

| 项 | 命令 | 预期 |
| --- | --- | --- |
| Core 测试 | `swift test --package-path Packages/TapeekCore` | 0 失败 |
| 默认限额 | `PreviewLimitsTests` | 七个默认值与规格一致 |
| 类型路由 | `PreviewKindTests` | md/markdown/mdown/mkd/zip/未知均正确 |
| 字节读取 | `ByteReaderTests` | 正常、边界、越界、负值均符合预期 |
| App 构建 | `./scripts/build.sh` | 退出码 0 |
| 无 UI 改动 | `git diff` 或文件清单 | 未修改视图与路由 |

## 证据

`docs/verification/T03.md`：

- `swift test` 输出摘要。
- `xcodebuild` 退出码。
- 新增文件列表。
- 任何版本适配（例如 `.macOS("27.0")` 改为 `.v14`）的理由。

## 停止条件

- SwiftPM 无法解析本地包，且一次路径修正后仍失败。
- `xcodebuild` 因包集成失败，且错误无法定位到 `project.yml` 的包声明。
- 需要引入第三方依赖才能完成基础类型。

## 交接

给 T04/T06：

- `PreviewLimits`、`PreviewFailure`、`PreviewKindResolver`、`ByteReader` 的可用实现。
- 测试命令与包路径。
- `project.yml` 已包含本地包，后续只需添加源文件。
