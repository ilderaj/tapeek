# T06 ZIP central directory 读取

| 项 | 内容 |
| --- | --- |
| ID | T06 |
| 状态 | 完成 |
| 依赖 | T03 |
| 执行角色 | executor；解析边界由 thinker 复核 |
| 预计产物 | `ZipArchiveReader`、条目模型、ZIP 夹具与解析测试 |

## 必读

- [ZIP 规格](../specs/zip-preview.md) §2 至 §5、§9。
- [实施计划](../impl-plan.md) §9.4。
- [测试规格](../specs/testing-and-fixtures.md) §4、§5。

## 目标

只读解析 ZIP 的 EOCD、ZIP64 记录和 central directory，返回扁平条目列表与摘要。不解压、不写盘、不构建树；树由 T07 处理。

## 允许改动

- `Packages/TapeekCore/Sources/TapeekCore/Archive/ZipEntry.swift`
- `Packages/TapeekCore/Sources/TapeekCore/Archive/ZipListing.swift`
- `Packages/TapeekCore/Sources/TapeekCore/Archive/ZipArchiveReader.swift`
- `Packages/TapeekCore/Sources/TapeekCore/ByteReader.swift`（仅补充需要的读取方法）
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipEOCDTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/Zip64Tests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipEncodingTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipPathTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipListingTests.swift`
- `scripts/make-fixtures.py`（新建，基础 ZIP 夹具）
- `Samples/zip/**`（基础夹具与 `manifest.json`）
- `docs/verification/T06.md`

## 禁止改动

- 不实现 `ZipTree` 或任何 SwiftUI 视图。
- 不实现解压、提取、内容读取或嵌套 ZIP 递归。
- 不引入 ZIPFoundation 或其他归档库；本 ticket 验证自写读取器。
- 不修改 Markdown 相关文件。
- 不添加网络、全盘访问或临时路径权限。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
python3 --version
unzip -v | head -2
```

确认 T03 测试通过，Python 3 和 `unzip` 可用。

## 步骤

### 1. 定义条目与摘要模型

`ZipEntry.swift`：

```swift
public enum ZipEntryKind: String, Equatable, Sendable {
    case file, directory, symlink
}

public struct ZipEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let path: String
    public let name: String
    public let kind: ZipEntryKind
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let isEncrypted: Bool
}
```

`ZipListing.swift`：

```swift
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
```

语义：

- `entries` 已经过路径规范化、NFC 和去重。
- `shownEntryCount == entries.count`。
- `totalEntryCount` 来自 EOCD/ZIP64；无法读取时为 `nil`。
- `skippedEntryCount` 是已读取但未进入 `entries` 的条目数（重复、非法路径、无法解码等）。
- `isTruncated` 表示因条目上限、目录字节上限或时间上限而未读完 central directory；不包括「跳过非法条目」。
- `fileCount` 与 `directoryCount` 只统计 `entries` 中的显式条目，不包含 T07 合成的父目录；树视图的摘要使用 `ZipTree` 的计数。
- `totalUncompressedBytes` 只累加文件/符号链接，使用饱和加法。
- `archiveBytes` 是磁盘文件大小。

### 2. 实现 EOCD 查找

在 `ZipArchiveReader.swift` 中实现：

- 只读 `FileHandle`。
- 读取尾部 `min(fileSize, 22 + 65535)` 字节。
- 从后向前搜索 `0x06054b50`。
- 校验 `offset + 22 + commentLength <= fileSize`。
- 优先精确结束于文件末尾的候选。
- 解析 EOCD 字段，拒绝多磁盘。
- 找不到合法 EOCD → `PreviewFailure.archiveUnreadable`。

细节以 [ZIP 规格](../specs/zip-preview.md) §3.1、§3.2 为准。

### 3. 实现 ZIP64

按规格 §3.3：

- 识别 locator 和 ZIP64 EOCD。
- 校验签名、记录长度、磁盘号。
- 使用 ZIP64 的 `totalEntries`、`cdSize`、`cdOffset`、`directoryEnd`。
- 多磁盘 → `archiveUnsupported("分卷压缩包")`。
- 自解压 + ZIP64 → `archiveUnsupported("自解压 ZIP64 暂不支持")`。
- 普通自解压 ZIP 通过 `archiveStart = directoryEnd - cdSize - cdOffset` 支持。

### 4. 读取 central directory

按规格 §3.4、§3.5：

- 计算 `cdStart`，做所有边界检查。
- 读取 `min(cdSize, maxZipCentralDirectoryBytes)` 字节。
- 逐条解析，检查剩余 46 字节、条目上限、时间上限。
- 遇到非法签名：
  - 第一条就非法 → `archiveUnreadable`。
  - 后续非法 → 记录 `.malformedEntry(offset:)`，停止解析，保留已读条目。
- 每条解析固定头字段，按规格 §3.6。
- ZIP64 extra 按 §3.7。
- 不读取 local header，不解压。

### 5. 文件名解码

实现提示：先用 Python 写一个一次性的参考脚本，按同样的字节偏移读取 `typical.zip`、`zip64-entry.zip`、`sfx.zip` 的 EOCD 和 central directory，打印条目数、偏移和名称；确认偏移公式无误后，再写 Swift。参考脚本不进入产品、不提交。

Swift 侧建议顺序：

1. `findEOCD()`：只返回 `(eocdOffset, directoryEnd, totalEntries, cdSize, cdOffset)`。
2. `parseCentralDirectory()`：只返回原始条目（未规范化）。
3. `normalizeEntries()`：路径、编码、去重、警告。
4. `makeListing()`：摘要。
5. 每步都有单元测试，不要等整个解析器写完再测。按规格 §4：

- UTF-8 标志优先。
- 无标志但合法 UTF-8 → UTF-8。
- CP437 回退。使用 CoreFoundation：

```swift
let cf = CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
let ns = CFStringConvertEncodingToNSStringEncoding(cf)
let name = String(data: raw, encoding: String.Encoding(rawValue: ns))
```

若该枚举在当前 SDK 不可用，使用内置 CP437 128 字符映射表，并在验收记录中说明。

- GB18030 启发式严格按规格条件，不得对所有非 UTF-8 名称强行按 GBK 解码。
- 解码失败或替换字符：记录 `.invalidUTF8Name` 或保留 CP437 结果。
- 统一 NFC。

### 6. 路径规范化与去重

按规格 §5：

- 反斜杠转斜杠、去前导斜杠、折叠重复斜杠、去掉 `./`。
- 拒绝 NUL、`..`、空段、超长路径、超过 256 段的路径。
- 目录类型按尾斜杠和 external attrs 判断。
- 符号链接按 mode 判断。
- 以 NFC 路径为键去重；重复保留第一条，记录 `.duplicatePath`。
- 文件与目录同路径时目录优先，记录 `.duplicatePath`。
- 被拒绝的条目计入 `skippedEntryCount`，不进入 `entries`。

### 7. 计算摘要

- `fileCount` 统计 `.file` 与 `.symlink`；`directoryCount` 统计 `.directory`。两者只统计显式条目。
- `totalUncompressedBytes` 饱和加法。
- `hasEncryptedEntries` 与 `.encryptedEntries(count:)`。
- `isTruncated` 与 `.truncated`/`.timedOut`。
- 条目全部被跳过时仍返回 listing，由 UI 显示错误状态；不要伪造空包。
- 空包（totalEntries == 0）返回 `entries: []`、`isTruncated: false`、无警告。

### 8. 创建基础 ZIP 夹具

新建 `scripts/make-fixtures.py`，只使用标准库和系统 `zip`。至少生成：

- `typical.zip`：两层目录、文件、显式空目录、中文名。
- `flat.zip`。
- `empty.zip`。
- `chinese-utf8.zip`。
- `chinese-gbk.zip`：手写 central directory，GBK 字节，不设置 UTF-8 标志。最小结构为 local header `0x04034b50`、central header `0x02014b50`、EOCD `0x06054b50`；文件名用 `"中文.txt".encode("gbk")`，flags 保持 0，数据可为空，CRC 为 0。
- `encrypted.zip`：`zip -P tapeek`；若不可用，设置 flags bit 0。
- `corrupt.zip`：截断 `typical.zip` 尾部。
- `zip64-entry.zip`：Python `force_zip64=True`。
- `duplicates.zip`：同一路径写入两次。
- `unsafe-paths.zip`：`../evil.txt`、`/abs.txt`、`a/../../b.txt`。
- `missing-dirs.zip`：只写 `a/b/c.txt`。
- `empty-dirs.zip`：`empty/`、`nested/empty/`。
- `sort.zip`：乱序写入文件夹与文件。
- `single-root.zip`：所有内容在 `Project/` 下。
- `long-names.zip`：接近 200 字符的名称。
- `macos-noise.zip`：`__MACOSX/._readme.md`、`.DS_Store`。
- `symlink.zip`：`external_attr` 设置为 `S_IFLNK`。
- `sfx.zip`：普通 ZIP 前拼接固定文本。

固定时间戳和压缩级别。生成后写入 `Samples/zip/manifest.json`，包含条目数、文件数、目录数、总大小、加密标记、ZIP64 标记和排序后的名称列表。大样本（70,000 条和 25,000 条）留给 T11。

### 9. 写测试

覆盖：

| 测试组 | 断言 |
| --- | --- |
| EOCD | 正常、空包、注释、截断、尾部垃圾、多磁盘 |
| ZIP64 | EOCD、条目 extra、偏移、缺 extra 的错误 |
| 文件名 | UTF-8 标志、无标志 UTF-8、CP437、GB18030 启发式、非法字节 |
| 路径 | 反斜杠、`..`、绝对路径、NUL、超长、重复 |
| 类型 | 文件、目录、符号链接、加密标记 |
| 摘要 | 数量、总大小、跳过数、截断标记 |
| 限额 | 条目上限、目录字节上限、超时 |
| 无写入 | 解析前后目录内容一致 |

与 `unzip` 交叉验证：

```sh
unzip -Z1 Samples/zip/typical.zip | sort > /tmp/typical.names
```

测试读取 manifest 和 `.names`，比较排序后的名称集合。字段（大小、类型）用 `unzip -l` 对照至少 3 个样本。

## 验收

| 项 | 命令 | 预期 |
| --- | --- | --- |
| 测试 | `swift test --package-path Packages/TapeekCore` | 0 失败 |
| 夹具生成 | `python3 -I scripts/make-fixtures.py` | 退出码 0，manifest 生成 |
| 与 unzip 一致 | 对比 `typical.zip`、`flat.zip`、`chinese-utf8.zip` | 名称、数量、类型一致 |
| 加密 | 解析 `encrypted.zip` | 条目可列，`hasEncryptedEntries == true` |
| 损坏 | 解析 `corrupt.zip` | 抛 `archiveUnreadable` 或返回明确错误 |
| ZIP64 | 解析 `zip64-entry.zip` | 大小与名称正确 |
| 路径安全 | 解析 `unsafe-paths.zip` | 危险条目被跳过，其余正常 |
| 无解压 | 预览前后 `find` | 无新增文件 |

## 证据

`docs/verification/T06.md`：

- `swift test` 摘要。
- `make-fixtures.py` 输出。
- `unzip -Z1` 与解析结果的对比。
- 加密、损坏、ZIP64、GBK 的实际结果。
- 任何与规格不一致的偏差。

## 停止条件

- 解析结果与 `unzip` 在标准样本上不一致，连续两次修正仍失败 → 触发 D3，切换 ZIPFoundation，并更新规格。
- EOCD/ZIP64 偏移导致无法在 2 小时内定位问题 → 缩小到最小样本，记录字节偏移，请求复核。
- 需要解压或读取条目内容才能判断 → 说明需求越界，停止。
- 需要引入第三方库才能完成 → 先请求批准，不自行添加。

## 交接

给 T07：

- `ZipEntry`、`ZipListing`、`ZipArchiveReader.list`。
- 夹具与 manifest。
- 已知的编码与异常行为。
- 与 `unzip` 对比的结果。
