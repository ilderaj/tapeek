# T07 ZIP 树与行投影

| 项 | 内容 |
| --- | --- |
| ID | T07 |
| 状态 | 完成 |
| 依赖 | T06 |
| 执行角色 | executor |
| 预计产物 | `ZipTree`、`ZipNode`、`ZipRow`、排序与展开测试 |

## 必读

- [ZIP 规格](../specs/zip-preview.md) §6、§7。
- [实施计划](../impl-plan.md) §9.5。
- [测试规格](../specs/testing-and-fixtures.md) §5。

## 目标

把 T06 的扁平条目列表转换成可展开的目录树，并提供纯函数的行投影和默认展开集合。此 ticket 不做 SwiftUI 视图。

## 允许改动

- `Packages/TapeekCore/Sources/TapeekCore/Archive/ZipTree.swift`
- `Packages/TapeekCore/Sources/TapeekCore/Archive/ZipNode.swift`（可合并到 ZipTree.swift）
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipTreeTests.swift`
- `Packages/TapeekCore/Tests/TapeekCoreTests/ZipRowsTests.swift`
- `docs/verification/T07.md`

## 禁止改动

- 不修改 `ZipArchiveReader` 的解析语义；发现问题回到 T06。
- 不修改 Markdown 或 UI 文件。
- 不添加解压、读取条目内容或文件系统写入。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
```

确认 T06 测试通过，夹具可用。

## 步骤

### 1. 定义模型

```swift
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

public struct ZipTree: Equatable, Sendable {
    public let root: ZipNode
    public let listing: ZipListing
    public let fileCount: Int        // 文件与符号链接
    public let directoryCount: Int   // 显式目录与合成目录，不含根

    public init(listing: ZipListing, archiveName: String)
    public func rows(expanded: Set<String>) -> [ZipRow]
    public func defaultExpandedIDs() -> Set<String>
}
```

要求：

- 根节点 `id = ""`，`path = ""`，`kind = .directory`，`name` 是 ZIP 文件名去掉 `.zip`。
- 根节点 `uncompressedSize = 0`，没有修改时间，不加密。
- 目录节点的 `uncompressedSize = 0`；文件/符号链接保留原值。
- 合成目录的 `modificationDate = nil`、`isEncrypted = false`。
- `fileCount` 统计文件与符号链接；`directoryCount` 统计所有目录节点（含合成目录，不含根）。
- 树的子节点顺序稳定，不依赖字典遍历顺序。

### 2. 构建树

建议内部使用引用类型 builder，最后转换成不可变 `ZipNode`：

```swift
private final class NodeBuilder {
    let id: String
    let name: String
    let path: String
    var kind: ZipEntryKind
    var uncompressedSize: UInt64
    var modificationDate: Date?
    var isEncrypted: Bool
    var children: [String: NodeBuilder]
}
```

步骤：

1. 创建根 builder。
2. 对每个 `ZipEntry`，按 `/` 拆分 `path`。
3. 逐段查找/创建子目录 builder。
4. 最后一段根据条目类型设置为文件、目录或符号链接。
5. 目录条目与已有合成目录合并：保留显式目录的修改时间和属性。
6. 文件与目录同路径冲突：T06 已按「目录优先」去重。T07 若仍遇到冲突，保留目录、跳过文件，并在测试日志中记录；不修改 `listing.warnings`（它是值类型，树构建不应回写解析结果）。
7. 路径深度超过 256 段的条目跳过；T06 应已过滤，T07 再防御一次。
8. 递归转换 builder 为 `ZipNode`。若担心深路径栈溢出，使用显式栈转换；首版深度上限 256，普通递归可接受，但必须在测试中包含 200 层路径。
9. 转换完成后统计 `fileCount`（文件 + 符号链接）和 `directoryCount`（所有目录节点，不含根）。不要直接复制 `listing.fileCount`/`listing.directoryCount`，它们不含合成目录。

### 3. 排序

每个节点的子节点按以下顺序排序：

1. `.directory` 在 `.file` 和 `.symlink` 之前。
2. 同类型按 `name.localizedStandardCompare` 升序。
3. 名称完全相同按 `path` 升序。

测试使用 ASCII 名称验证前两条；中文名称只验证不崩溃和顺序稳定，不断言特定拼音顺序。

### 4. 行投影

`rows(expanded:)`：

- 输出根节点的直接子节点，深度 0。
- 目录节点在 `expanded` 中时，输出其子节点，深度加 1。
- 文件/符号链接不展开。
- 使用显式栈或递归；输出顺序必须与树排序一致。
- `isExpanded` 对目录表示「当前是否展开」；文件恒为 false。
- 不修改树，不缓存结果。
- 传入不存在的 ID 忽略。
- 空树返回空数组。

### 5. 默认展开

`defaultExpandedIDs()`：

1. 收集根节点的所有直接子目录 ID。
2. 若根节点只有一个子节点且它是目录，再收集该目录的所有直接子目录 ID。
3. 不展开更深层。
4. 返回集合，不修改树。

示例：

```
root
├── docs/          → 默认展开，显示 docs 的子项
│   ├── a.md
│   └── b.md
└── src/           → 默认展开，显示 src 的子项
    └── main.swift
```

单根示例：

```
root
└── Project/       → 默认展开
    ├── docs/      → 也默认展开（因为根只有一个子节点且是目录）
    │   └── a.md
    └── README.md
```

### 6. 写测试

| 测试 | 预期 |
| --- | --- |
| `typical.zip` | 树层级、文件/目录类型、子节点顺序正确 |
| `missing-dirs.zip` | 父目录被合成，`a/b/c.txt` 可见 |
| `empty-dirs.zip` | 显式空目录作为叶子目录存在 |
| `single-root.zip` | 根只有一个 `Project/`，默认展开两层 |
| `sort.zip` | 目录在文件前，名称升序 |
| 200 层路径 | 不崩溃，行投影深度正确（若 T06 已过滤则断言跳过） |
| 空 listing | 根无子节点，rows 为空 |
| 展开/折叠 | 同一棵树用不同集合投影，结果符合预期 |
| 行深度 | 根子节点 depth 0，下一层 1 |
| 行顺序 | 与树排序一致，稳定重复调用 |
| 合成目录计数 | `missing-dirs.zip` 的 `tree.directoryCount` 大于 `listing.directoryCount`，且树中父目录可见 |

### 7. 运行测试

```sh
swift test --package-path Packages/TapeekCore
```

## 验收

| 项 | 命令 | 预期 |
| --- | --- | --- |
| 测试 | `swift test --package-path Packages/TapeekCore` | 0 失败 |
| 典型树 | `ZipTreeTests` | 层级、类型、排序正确 |
| 合成目录 | `ZipTreeTests` | 缺失父目录可见 |
| 空目录 | `ZipTreeTests` | 显式空目录可见 |
| 默认展开 | `ZipRowsTests` | 普通 ZIP 展开第一层；单根展开两层 |
| 行投影 | `ZipRowsTests` | 深度、顺序、折叠正确 |
| 200 层 | `ZipTreeTests` | 不崩溃，行为有明确断言 |

对应规格用例：ZIP-012、ZIP-013、ZIP-014、ZIP-016、ZIP-025（数据层）。

## 证据

`docs/verification/T07.md`：测试摘要、树结构示例、默认展开示例、深路径结果。

## 停止条件

- 树构建在 20,000 条样本上超过 1 秒。
- 深路径导致崩溃或栈溢出。
- 排序结果不稳定，重复运行不一致。
- 需要修改 T06 的条目模型才能继续。

## 交接

给 T08：

- `ZipTree`、`ZipNode`、`ZipRow`。
- `rows(expanded:)` 与 `defaultExpandedIDs()`。
- 排序与合成目录的行为。
- 可直接使用的测试夹具。
