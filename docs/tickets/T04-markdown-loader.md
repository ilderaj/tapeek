# T04 Markdown 加载与前置元数据

| 项 | 内容 |
| --- | --- |
| ID | T04 |
| 状态 | 待开始 |
| 依赖 | T03 |
| 执行角色 | executor |
| 预计产物 | `MarkdownLoader`、`FrontMatter`、解码与限额测试 |

## 必读

- [Markdown 规格](../specs/markdown-preview.md) §2、§3、§5、§9。
- [实施计划](../impl-plan.md) §9.1、§9.3。
- [测试规格](../specs/testing-and-fixtures.md) §3、§5。

## 目标

把 Markdown 文件安全地读取为可渲染的字符串，并正确识别、移除和返回 YAML front matter。此 ticket 不做 SwiftUI 视图。

## 允许改动

- `Packages/TapeekCore/Sources/TapeekCore/Markdown/MarkdownDocument.swift`
- `Packages/TapeekCore/Sources/TapeekCore/Markdown/MarkdownLoader.swift`
- `Packages/TapeekCore/Sources/TapeekCore/Markdown/FrontMatter.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/MarkdownLoaderTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/FrontMatterTests.swift`
- `Samples/markdown/front-matter.md`
- `Samples/markdown/malformed-front-matter.md`
- `Samples/markdown/empty.md`
- `Samples/markdown/only-front-matter.md`
- `Samples/markdown/utf8-bom.md`
- `Samples/markdown/utf16le.md`
- `Samples/markdown/utf16be.md`
- `Samples/markdown/invalid-utf8.md`
- `docs/verification/T04.md`

## 禁止改动

- 不实现或修改 `MarkdownPreviewView`。
- 不修改 ZIP 相关文件。
- 不引入 Markdown 解析库；本 ticket 只负责读取、解码和 front matter。
- 不把 front matter 解析成完整 YAML；只支持扁平键值。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
```

确认 T03 的测试通过。

## 步骤

### 1. 定义模型

`MarkdownDocument.swift`：

```swift
public struct FrontMatterEntry: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(key: String, value: String) { ... }
}

public struct MarkdownDocument: Equatable, Sendable {
    public let body: String
    public let frontMatter: [FrontMatterEntry]
    public let byteCount: Int
    public let encoding: MarkdownTextEncoding
    public let baseURL: URL
}

public enum MarkdownTextEncoding: String, Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}
```

`URL` 在 Foundation 中符合 `Sendable`；若编译器报错，标记 `@unchecked Sendable` 并写明理由，不删除 `Sendable`。

### 2. 实现 MarkdownLoader

公开接口按 [实施计划](../impl-plan.md) §9.3：

```swift
public enum MarkdownLoader {
    public static func load(url: URL, limits: PreviewLimits = .default) throws -> MarkdownDocument
    public static func load(data: Data, baseURL: URL, limits: PreviewLimits = .default) throws -> MarkdownDocument
}
```

`load(url:)`：

1. 用 `FileManager.default.attributesOfItem(atPath: url.path)[.size]` 读取文件大小。
2. 大小超过 `maxMarkdownBytes` → `PreviewFailure.fileTooLarge(actualBytes:limitBytes:)`。
3. 大小不可读或读取失败 → `unreadableFile`。
4. 读取数据。优先 `Data(contentsOf: url, options: [.mappedIfSafe])`；读取后再次检查 `data.count`，防止文件增长。
5. 调用 `load(data:baseURL:limits:)`，`baseURL = url.deletingLastPathComponent()`。

`load(data:)`：

1. `data.count > maxMarkdownBytes` → `fileTooLarge`。
2. 按 §3 解码。
3. 解码后包含 NUL（U+0000）→ `unsupportedTextEncoding`。
4. 调用 `FrontMatter.parse`。
5. 返回 `MarkdownDocument`。

### 3. 解码顺序

严格按以下顺序，不要用 `String(contentsOf:usedEncoding:)` 让系统猜：

| 前缀 | 编码 | 处理 |
| --- | --- | --- |
| `EF BB BF` | UTF-8 | 去掉 3 字节，按 `.utf8` 解码 |
| `FF FE` | UTF-16 LE | 去掉 2 字节，按 `.utf16LittleEndian` 解码 |
| `FE FF` | UTF-16 BE | 去掉 2 字节，按 `.utf16BigEndian` 解码 |
| 无 BOM | UTF-8 | 按 `.utf8` 严格解码 |

要求：

- 解码失败返回 `unsupportedTextEncoding`，不返回替换字符。
- UTF-16 解码后检查 NUL；UTF-16 文本中正常的 U+0000 也视为异常，直接报错。
- 空 `Data` 返回空字符串，编码记为 `.utf8`，不抛错。
- 记录实际编码到 `MarkdownDocument.encoding`。

### 4. 实现 FrontMatter

`FrontMatter.swift`：

```swift
struct FrontMatterResult {
    let entries: [FrontMatterEntry]
    let body: String
}

enum FrontMatter {
    static func parse(_ text: String) -> FrontMatterResult
}
```

识别规则：

1. 按 `\n` 切行，保留空行。行尾的 `\r` 在判断时去掉，但正文保留原始换行。
2. 第一行去空白后必须是 `---`。否则返回 `entries: []`、`body: text`。
3. 从第二行开始寻找结束行：去空白后是 `---` 或 `...`。
4. 结束行必须在前 8 KiB 内（按 UTF-8 字节数累计），且与开始行之间至少有一行内容。
5. 找不到结束行 → 不视为 front matter，返回原文。
6. 结束行紧邻开始行（中间没有内容）→ 不视为 front matter。

解析键值：

- 逐行去首尾空白；空行、以 `#` 开头的行跳过。
- 只接受第一个 `:` 之前和之后都有内容的行。
- 键允许 `A-Z a-z 0-9 _ . -`，长度 1 至 64。
- 值去掉首尾空白；若首尾是成对的 `'` 或 `"`，去掉一层引号。
- 值最长 512 字符，超出截断并追加 `…`。
- 重复键保留第一次出现的值。
- 最多 20 项；多余项忽略。
- 不符合键规则的行忽略，不报错。
- 缩进的续行忽略，不拼接。

返回：

- `entries`：解析出的扁平键值。
- `body`：结束行之后的所有行，用 `\n` 连接；保留原始 `\r` 和空行。
- 即使 `entries` 为空，只要识别到完整 front matter 块，也从 `body` 中移除。

### 5. 创建样本

按 [测试规格](../specs/testing-and-fixtures.md) §3 创建本 ticket 负责的样本。注意：

- `utf8-bom.md` 必须写入真实 BOM 字节。
- `utf16le.md`、`utf16be.md` 必须写入 BOM 和对应字节序。
- `invalid-utf8.md` 写入非法 UTF-8 序列，例如 `0xFF 0xFE` 之外的孤立 `0x80`。
- `empty.md` 为 0 字节。
- `front-matter.md` 包含 `title`、`tags`、`date`、带引号值和一个空值。
- `many-front-matter.md` 留到 T11；本 ticket 的测试可以在内存中构造 21 项。

### 6. 写测试

至少覆盖：

| 测试 | 预期 |
| --- | --- |
| UTF-8 普通文本 | 编码 `.utf8`，正文一致 |
| UTF-8 BOM | BOM 不出现在 `body` 首字符 |
| UTF-16 LE/BE | 中文正文正确，编码枚举正确 |
| 非法 UTF-8 | 抛 `unsupportedTextEncoding` |
| NUL 字节 | 抛 `unsupportedTextEncoding` |
| 空文件 | `body == ""`，不抛错 |
| 刚好达到上限 | 成功 |
| 超过上限 1 字节 | `fileTooLarge`，实际值和上限正确 |
| 文件不存在 | `unreadableFile` |
| front matter 正常 | 条目正确，`body` 不含元数据 |
| 带引号的值 | 去掉一层引号 |
| 空值 | 值为空字符串 |
| 重复键 | 保留第一次 |
| 21 项 | 只保留 20 项 |
| 无结束分隔符 | 不识别为 front matter，原文返回 |
| 开始行不在第一行 | 不识别 |
| CRLF front matter | 识别，正文保留 CRLF |
| 只有 front matter | 条目存在，`body` 为空白或空 |
| 结束行后有多段正文 | 正文完整，缩进和空行不丢失 |

测试使用 `XCTAssertThrowsError` 并断言具体 `PreviewFailure`，不要只断言「抛错」。

### 7. 运行测试

```sh
swift test --package-path Packages/TapeekCore
```

## 验收

| 项 | 命令 | 预期 |
| --- | --- | --- |
| 全部测试 | `swift test --package-path Packages/TapeekCore` | 0 失败 |
| 解码 | `MarkdownLoaderTests` | UTF-8/UTF-16/BOM/错误均符合 |
| front matter | `FrontMatterTests` | 正常、异常、限额均符合 |
| 构建 | `./scripts/build.sh` | 退出码 0 |

对应规格用例：MD-003、MD-004、MD-005、MD-006、MD-007、MD-008、MD-009、MD-010（数据层）。

## 证据

`docs/verification/T04.md`：

- 测试命令与摘要。
- 新增样本的 `file`/`xxd` 关键字节（BOM、非法序列）。
- 实际编码判断结果。
- 未覆盖项。

## 停止条件

- Foundation 的 UTF-16 解码行为与预期不符，且一次修正后仍失败。
- `URL` 的 `Sendable` 导致无法编译，且无法通过局部标注解决。
- 需要引入 YAML 解析库才能满足规格。

## 交接

给 T05：

- `MarkdownLoader.load` 与 `MarkdownDocument`。
- `FrontMatter` 的条目格式与正文行为。
- 样本文件与测试命令。
- 已知编码限制。
