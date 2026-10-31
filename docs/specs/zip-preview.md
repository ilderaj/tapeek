# ZIP 目录预览规格（F2）

## 1. 范围

本规格覆盖 Finder 空格预览 ZIP 文件时的目录读取、文件名解码、路径规范化、树构建、排序、摘要、展开交互、错误和限额。输出是只读的 SwiftUI 目录树。

核心约束：只读取 ZIP 的 End of Central Directory（EOCD）、ZIP64 记录和 central directory；不解压任何条目，不把包内文件写入磁盘，不打开包内文件内容。

不覆盖：解压、提取、拖出、删除、重命名、重新打包、密码输入、分卷合并、包内文件正文预览、嵌套 ZIP 递归浏览、搜索、筛选。

## 2. 输入

- 扩展声明的 UTI：`public.zip-archive`。
- 路由时接受扩展名 `.zip`，大小写不敏感。
- 输入必须是普通本地文件；不处理网络 URL、符号链接指向的远端卷或不可读文件。
- 0 字节文件不是有效 ZIP，显示「无法读取压缩包」。

## 3. 读取算法

实现位于 `TapeekCore/Archive/ZipArchiveReader.swift`。所有多字节整数按小端读取。任何越界读取都必须先检查长度，不能依赖崩溃或异常。

### 3.1 打开与尾部窗口

1. 以只读方式打开文件，取得 `fileSize`。
2. 若 `fileSize < 22`，返回 `archiveUnreadable`。
3. 读取文件尾部窗口：`tailLength = min(fileSize, 22 + 65535)`，起点为 `fileSize - tailLength`。
4. 从窗口末尾向前搜索 EOCD 签名 `0x06054b50`。候选位置必须满足：
   - `offset + 22 <= fileSize`。
   - `offset + 22 + commentLength <= fileSize`。
   - 优先选择 `offset + 22 + commentLength == fileSize` 的候选；若没有，接受最靠后的合法候选，并记录尾部多余字节。
5. 找不到 EOCD：返回 `archiveUnreadable`。

### 3.2 EOCD 字段

EOCD 固定头 22 字节，字段如下：

| 偏移 | 长度 | 字段 | 用途 |
| --- | --- | --- | --- |
| 0 | 4 | signature | 必须为 `0x06054b50` |
| 4 | 2 | diskNumber | 当前磁盘号，必须为 0 |
| 6 | 2 | cdStartDisk | 目录起始磁盘号，必须为 0 |
| 8 | 2 | entriesOnDisk | 本磁盘条目数 |
| 10 | 2 | totalEntries | 总条目数 |
| 12 | 4 | cdSize | central directory 字节数 |
| 16 | 4 | cdOffset | central directory 起始偏移 |
| 20 | 2 | commentLength | 注释长度 |

`diskNumber != 0` 或 `cdStartDisk != 0` 时返回 `archiveUnsupported("分卷压缩包")`。

### 3.3 ZIP64

满足任一条件时按 ZIP64 处理：

- `totalEntries == 0xFFFF`。
- `cdSize == 0xFFFFFFFF`。
- `cdOffset == 0xFFFFFFFF`。
- 在 `eocdOffset - 20` 处存在 ZIP64 locator 签名 `0x07064b50`。

ZIP64 locator 字段：

| 偏移 | 长度 | 字段 |
| --- | --- | --- |
| 0 | 4 | signature，`0x07064b50` |
| 4 | 4 | diskWithZip64EOCD，必须为 0 |
| 8 | 8 | zip64EOCDOffset |
| 16 | 4 | totalDisks，必须为 1 |

ZIP64 EOCD 从 `zip64EOCDOffset` 开始，字段：

| 偏移 | 长度 | 字段 |
| --- | --- | --- |
| 0 | 4 | signature，`0x06064b50` |
| 4 | 8 | sizeOfRecord，至少 44 |
| 12 | 2 | versionMadeBy |
| 14 | 2 | versionNeeded |
| 16 | 4 | diskNumber，必须为 0 |
| 20 | 4 | cdStartDisk，必须为 0 |
| 24 | 8 | entriesOnDisk |
| 32 | 8 | totalEntries |
| 40 | 8 | cdSize |
| 48 | 8 | cdOffset |

限制：

- `zip64EOCDOffset + 56 > fileSize` 时返回 `archiveUnreadable`。
- 多磁盘 ZIP64 返回 `archiveUnsupported("分卷压缩包")`。
- 首版不支持「自解压前缀 + ZIP64」组合；检测到 `archiveStart < 0` 或记录偏移异常时返回 `archiveUnsupported("自解压 ZIP64 暂不支持")`。

### 3.4 计算目录起点

- 普通 ZIP：`directoryEnd = eocdOffset`。
- ZIP64：`directoryEnd = zip64EOCDOffset`。
- `archiveStart = directoryEnd - cdSize - cdOffset`。
- `cdStart = archiveStart + cdOffset`。

校验：

- `archiveStart >= 0`。
- `cdStart >= 0` 且 `cdStart <= directoryEnd`。
- `cdSize <= fileSize`。
- `cdStart + min(cdSize, maxZipCentralDirectoryBytes) <= fileSize`。

任何一项失败：返回 `archiveUnreadable`。`archiveStart > 0` 表示文件有自解压或其他前缀；普通 ZIP 仍可继续。

### 3.5 读取 central directory

1. 实际读取长度：`readLength = min(cdSize, maxZipCentralDirectoryBytes)`。
2. 从 `cdStart` 读取 `readLength` 字节到内存。
3. 若 `readLength < cdSize`，标记目录被截断，最终列表附带 `.truncated` 警告。
4. 从偏移 0 开始逐条解析。每轮先检查：
   - 剩余字节至少 46。
   - 已解析条目数小于 `maxZipEntries`。
   - 当前时间未超过 `maxZipListingDuration`。
5. 任一条件不满足时停止，并按原因附加 `.truncated` 或 `.timedOut` 警告。

### 3.6 Central directory 条目字段

固定头 46 字节：

| 偏移 | 长度 | 字段 | 用途 |
| --- | --- | --- | --- |
| 0 | 4 | signature | 必须为 `0x02014b50` |
| 4 | 2 | versionMadeBy | 高位表示创建系统 |
| 6 | 2 | versionNeeded | 最低解压版本 |
| 8 | 2 | flags | bit 0 加密，bit 11 UTF-8 文件名 |
| 10 | 2 | method | 压缩方法，仅记录，不解压 |
| 12 | 2 | modTime | DOS 时间 |
| 14 | 2 | modDate | DOS 日期 |
| 16 | 4 | crc32 | 校验值，仅展示时不需要 |
| 20 | 4 | compressedSize | 压缩后大小 |
| 24 | 4 | uncompressedSize | 原始大小 |
| 28 | 2 | nameLength | 文件名长度 |
| 30 | 2 | extraLength | 扩展字段长度 |
| 32 | 2 | commentLength | 注释长度 |
| 34 | 2 | diskStart | 起始磁盘号，必须为 0 |
| 36 | 2 | internalAttrs | 内部属性 |
| 38 | 4 | externalAttrs | 外部属性，含 Unix mode |
| 42 | 4 | localHeaderOffset | 本地头偏移，仅记录 |
| 46 | n | name | 文件名原始字节 |
| 46+n | m | extra | 扩展字段 |
| 46+n+m | k | comment | 注释，跳过 |

`nextOffset = 46 + nameLength + extraLength + commentLength`。若 `nextOffset > data.count`，说明目录被截断：停止解析并附加 `.truncated`。

`nameLength == 0` 的条目跳过，并记录 `.unsafePath("空文件名")`。

### 3.7 ZIP64 扩展字段

当 32 位字段为 `0xFFFFFFFF` 时，从 extra 字段中查找 header ID `0x0001`：

| 顺序 | 长度 | 字段 | 触发条件 |
| --- | --- | --- | --- |
| 1 | 8 | uncompressedSize | 原始字段为 `0xFFFFFFFF` |
| 2 | 8 | compressedSize | 原始字段为 `0xFFFFFFFF` |
| 3 | 8 | localHeaderOffset | 原始字段为 `0xFFFFFFFF` |
| 4 | 4 | diskStart | 原始字段为 `0xFFFF` |

extra 字段结构为 `headerID(2) + dataSize(2) + data`，可以包含多个子字段。只读取 `0x0001`，其余跳过。缺少所需数据时，该条目跳过并记录 `.truncated` 或 `.malformedEntry`，不能让整个预览崩溃。

## 4. 文件名解码

按以下顺序决定文件名：

1. **UTF-8 标志**：`flags` 的 bit 11 为 1，按 UTF-8 严格解码。
   - 成功：使用结果。
   - 失败：用替换字符解码，记录 `.invalidUTF8Name`，继续显示。
2. **无标志但字节是合法 UTF-8**：按 UTF-8 解码。这是对未设置标志但实际使用 UTF-8 的常见归档的兼容。
3. **否则按 CP437**：使用 CoreFoundation 的 DOS Latin US 编码解码。
4. **GB18030 启发式**：仅当以下条件同时满足时，改用 GB18030 解码并记录 `.guessedLegacyEncoding`：
   - CP437 结果中至少 2 个字符落在 U+00A0–U+00FF 或 U+2500–U+257F。
   - GB18030 结果中至少 2 个字符是 CJK 统一表意文字（U+4E00–U+9FFF）。
   - GB18030 解码没有替换字符。
5. 仍无法解码：保留 CP437 结果；若为空，使用 `未命名条目`。

补充规则：

- 显示名称统一做 NFC 规范化（`precomposedStringWithCanonicalMapping`），避免同一名称的分解形式产生重复节点。
- 原始字节不写入日志，避免把用户文件名带到不必要的持久记录。
- 编码判断只影响显示，不改变 ZIP 内容。

## 5. 路径规范化

对解码后的名称依次执行：

1. 把反斜杠 `\` 替换为 `/`。发生替换时记录 `.unsafePath` 或 `.duplicatePath` 之外的提示；至少让结果可读。
2. 去掉开头的 `/`，去掉重复的 `/`，去掉 `./` 段。
3. 拒绝包含 NUL 的名称。
4. 拒绝任何 `..` 段、空段（除末尾目录斜杠外）。
5. 路径 UTF-8 字节数超过 `maxZipPathBytes` 时跳过。
6. 路径分段数超过 `maxZipPathDepth`（默认 256）时跳过，避免深层树导致栈溢出。
7. 去掉末尾 `/` 作为内部路径；目录类型单独记录。
8. 统一 NFC。

被拒绝的条目不会进入树，但会使 `shownEntryCount < totalEntryCount`，并记录 `.unsafePath(原始名称)`。

### 5.1 类型判断

按以下优先级：

1. 名称以 `/` 结尾：目录。
2. `externalAttrs` 高位 mode 的 `S_IFMT` 为 `S_IFDIR`（`0x4000`）：目录。
3. mode 为 `S_IFLNK`（`0xA000`）：符号链接。
4. 其他：文件。

符号链接只作为条目显示，不跟随、不解析目标。图标与文件相同，可额外显示链接标记。

### 5.2 去重与冲突

- 以规范化后的路径作为唯一键。
- 相同路径重复出现：保留第一条，记录 `.duplicatePath(path)`。
- 同一路径既是文件又是目录：目录优先，文件跳过，记录 `.duplicatePath(path)`。
- 父目录不存在时自动合成目录节点，不记录警告。
- 显式目录条目与合成目录合并，保留显式条目的修改时间和属性。
- 空目录只有 ZIP 显式存储时才能显示；未存储的空目录无法从 central directory 推断，这是格式限制，不是解析错误。

## 6. 树构建与排序

### 6.1 树

- 根节点路径为空字符串，名称使用 ZIP 文件名（不含 `.zip`）。
- 每个条目按 `/` 分段挂到父节点。
- 子节点按以下规则排序：
  1. 目录在文件之前。
  2. 同一类型按名称的 `localizedStandardCompare` 升序。
  3. 名称相同时按路径升序，保证结果稳定。
- 目录的 `uncompressedSize` 为 0；界面显示直接子项数量，不显示大小。
- 文件的 `uncompressedSize` 来自 central directory；0 表示空文件，显示 `0 字节`。无法解析大小的条目应跳过，不以 0 冒充。

### 6.2 行投影

`rows(expanded:)` 是纯函数：

- 从根节点的子节点开始，深度为 0。
- 输出每个可见节点一行。
- 目录节点在 `expanded` 集合中时，递归输出其子节点，深度加 1。
- 文件节点没有子节点。
- 输出顺序与树排序一致。
- 展开状态不修改树；同一份树可以用不同集合反复投影。

### 6.3 默认展开

`defaultExpandedIDs()` 返回：

1. 根节点的所有直接子目录 ID。
2. 若根节点只有一个子节点且它是目录，再加入该目录的所有直接子目录 ID。

效果：普通 ZIP 打开后能看到第一层；单根目录的项目包能看到两层，避免用户先点一次才能看到内容。更深层保持折叠。

## 7. 摘要与视图

### 7.1 头部摘要

显示两行：

```
12 个文件，4 个文件夹
未压缩 18.4 MB · 压缩包 6.2 MB
```

规则：

- `fileCount` 包含普通文件和符号链接；`directoryCount` 包含显式目录和合成的父目录，不含根节点。两者来自 `ZipTree`，不是 `ZipListing` 的显式条目计数。
- 未压缩大小是所有文件 `uncompressedSize` 的和，使用饱和加法，避免溢出。
- 压缩包大小是磁盘上的 ZIP 文件大小。
- 包含加密条目时，在摘要后显示「含加密条目」标记。
- 列表被截断时，第一行改为：

```
已显示 20,000 项，共 123,456 项
```

- 若 EOCD 无法给出总数，改为 `已显示 20,000 项，总数未知`。

- 有跳过项但未截断时，显示：

```
已显示 118 项，共 120 项（2 项被跳过）
```

- 大小格式化使用 `ByteCountFormatter` 的文件样式；0 字节显示 `0 字节`。

### 7.2 行

| 元素 | 规格 |
| --- | --- |
| 缩进 | 每层 16 pt |
| 展开箭头 | 目录有子节点时显示；文件不显示 |
| 图标 | 文件夹 `folder`，文件 `doc`，符号链接 `link`；使用 SF Symbols |
| 名称 | 单行，超出时截断并显示省略号；悬停显示完整路径 |
| 大小 | 文件右对齐显示；目录显示直接子项数量，例如 `3 项` |
| 修改时间 | 不占主行；放在悬停提示中，格式 `yyyy-MM-dd HH:mm`，无日期显示 `—` |
| 行高 | 24 pt |
| 选中 | 不要求多选；目录行可点击展开/折叠 |
| 可访问性 | 目录标签为「文件夹，{名称}，{N} 项」；文件为「文件，{名称}，{大小}」 |

点击行为：

- 点击目录行或箭头：切换展开状态。
- 点击文件行：不执行任何动作，不打开、不提取、不拖出。
- 双击文件行：与单击相同，不打开。
- 键盘：Tab 聚焦目录行，空格或回车切换展开；滚动使用系统行为。

### 7.3 容器

- 顶部摘要区固定，不随树滚动。
- 树在 `ScrollView` + `LazyVStack` 中，行按可见集合渲染。
- 背景使用 `Color(nsColor: .textBackgroundColor)`。
- 分隔线使用系统分隔色。
- 空包、错误、截断提示都占据内容区，不叠加在树上。

### 7.4 状态文案

| 状态 | 显示 |
| --- | --- |
| 空包 | 图标 + 「压缩包为空」+「这个 ZIP 没有可显示的条目。」 |
| 加载 | 首版同步解析，通常不显示；若解析超过 200 ms，可显示「正在读取目录……」 |
| 加密条目 | 摘要区标记「含加密条目」；列表正常显示 |
| 截断 | 列表上方黄色/次要色提示条，文案见 7.1 |
| 超时 | 已解析部分照常显示；提示「读取超时，仅显示已读取的条目。」 |
| 损坏 | 错误视图，见第 8 节 |

## 8. 错误

错误视图居中，包含图标、标题、详情和文件名。不提供重试按钮。

| 情况 | 标题 | 详情 |
| --- | --- | --- |
| 文件不可读 | 无法读取文件 | 文件可能已被移动，或当前没有读取权限。 |
| 找不到 EOCD 或目录无效 | 无法读取压缩包 | 文件可能已损坏，或不是标准 ZIP。 |
| 加密目录无法读取 | 压缩包已加密 | 无法读取加密的目录信息。首版不支持输入密码。 |
| 分卷压缩包 | 暂不支持此压缩包 | 首版不支持分卷 ZIP。 |
| 自解压 ZIP64 | 暂不支持此压缩包 | 自解压 ZIP64 暂不支持。 |
| 读取超时且没有任何条目 | 读取超时 | 压缩包较大或结构异常，未能读取目录。 |
| 条目全部被跳过 | 无法显示压缩包目录 | 所有条目路径均无效或无法解码。 |

部分成功不显示整页错误，只显示列表和提示条。

## 9. 安全与限额

| 项 | 规则 |
| --- | --- |
| 解压 | 禁止。只读 central directory，不调用解压 API |
| 写入 | 禁止写用户目录、临时目录或包内路径 |
| 路径穿越 | 含 `..`、NUL 或绝对路径的条目跳过 |
| 符号链接 | 只显示，不跟随 |
| 嵌套 ZIP | 作为普通文件显示，不递归 |
| 条目上限 | `maxZipEntries = 20_000` |
| 目录字节上限 | `maxZipCentralDirectoryBytes = 16 MiB` |
| 路径长度 | `maxZipPathBytes = 4_096` |
| 路径深度 | `maxZipPathDepth = 256` |
| 时间上限 | `maxZipListingDuration = 2.0 s` |
| 整数溢出 | 所有尺寸求和使用饱和加法；偏移计算先检查负数与越界 |
| 内存 | 不读取整个 ZIP；只读尾部窗口和受限的目录区 |

超过上限时：

- 已解析的条目照常显示。
- 摘要使用「已显示 N 项，共 M 项」。
- 提示条说明原因（条目过多、目录过大或读取超时）。
- 不得把部分列表伪装成完整列表。

## 10. 验收用例

| ID | 前置 | 操作 | 预期 | 证据 |
| --- | --- | --- | --- | --- |
| ZIP-001 | `Samples/zip/typical.zip` | 空格预览 | 显示两层目录；文件夹在前；文件大小正确 | 截图 |
| ZIP-002 | `Samples/zip/flat.zip` | 空格预览 | 所有文件在第一层，排序稳定 | 截图 |
| ZIP-003 | `Samples/zip/empty.zip` | 空格预览 | 显示「压缩包为空」 | 截图 |
| ZIP-004 | `Samples/zip/chinese-utf8.zip` | 空格预览 | 中文文件名正确，无乱码 | 截图 |
| ZIP-005 | `Samples/zip/chinese-gbk.zip` | 空格预览 | 尽量正确显示中文；若使用启发式，显示编码提示 | 截图与说明 |
| ZIP-006 | `Samples/zip/encrypted.zip` | 空格预览 | 能列目录；显示「含加密条目」；不要求密码 | 截图 |
| ZIP-007 | `Samples/zip/corrupt.zip` | 空格预览 | 显示「无法读取压缩包」，不崩溃 | 截图 |
| ZIP-008 | `Samples/zip/zip64.zip` | 空格预览 | 条目正确显示，摘要正常 | 截图 |
| ZIP-009 | `Samples/zip/many-entries.zip`（25,000 条） | 空格预览 | 只显示前 20,000 项，提示总数 | 截图 |
| ZIP-010 | `Samples/zip/duplicates.zip` | 空格预览 | 重复路径只出现一次，提示有跳过项 | 截图 |
| ZIP-011 | `Samples/zip/unsafe-paths.zip` | 空格预览 | `../` 条目被跳过；其余正常；有提示 | 截图 |
| ZIP-012 | `Samples/zip/missing-dirs.zip` | 空格预览 | 缺失的父目录被合成，层级正确 | 截图 |
| ZIP-013 | `Samples/zip/empty-dirs.zip` | 空格预览 | 显式空目录可见；未存储的空目录不可见 | 截图 |
| ZIP-014 | `Samples/zip/sort.zip` | 空格预览 | 文件夹在文件前；同层按名称升序 | 截图 |
| ZIP-015 | `Samples/zip/typical.zip` | 查看摘要 | 文件数、文件夹数、未压缩大小、压缩包大小正确 | 截图 + `unzip -l` 输出 |
| ZIP-016 | `Samples/zip/single-root.zip` | 空格预览 | 默认展开两层，能看到根目录内的内容 | 截图 |
| ZIP-017 | `Samples/zip/long-names.zip` | 悬停长文件名 | 显示完整路径提示，不撑破窗口 | 截图 |
| ZIP-018 | `Samples/zip/macos-noise.zip` | 空格预览 | `__MACOSX`、`.DS_Store` 正常显示，不崩溃 | 截图 |
| ZIP-019 | `Samples/zip/symlink.zip` | 空格预览 | 符号链接显示为条目，不跟随 | 截图 |
| ZIP-020 | `Samples/zip/sfx.zip` | 空格预览 | 有前缀的普通 ZIP 能正确读取目录 | 截图（若实现） |
| ZIP-021 | 分卷样本（如可得） | 空格预览 | 显示「暂不支持分卷 ZIP」 | 截图或记录为未覆盖 |
| ZIP-022 | 任意 ZIP | 预览前后执行 `find` | 目录中没有新增解压文件 | 命令输出 |
| ZIP-023 | 先预览 ZIP，再预览 Markdown | 连续切换 | 内容不串台 | 截图/录屏 |
| ZIP-024 | 任意 ZIP | 切换深色外观 | 行、摘要、提示条对比度正常 | 浅色/深色截图 |
| ZIP-025 | 截断样本 | 查看摘要 | 明确区分「已显示」与「总数」，不声称完整 | 截图 |

## 11. 已知限制

- 未显式存储的空目录无法显示。
- 旧式文件名编码只能启发式识别；判断错误时显示的名称可能不正确。
- 加密条目只列名称，不能预览内容。
- 不支持分卷 ZIP、RAR、7z、TAR 等格式。
- 不支持搜索、筛选、按大小排序、树内多选。
- 嵌套 ZIP 只作为文件显示，不递归展开。
- 自解压 ZIP64 暂不支持；普通自解压 ZIP 可以尝试读取。
- 超过 20,000 条或 16 MiB 目录区时只显示部分结果。
