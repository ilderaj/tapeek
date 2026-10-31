# T11 夹具补齐与性能基准

| 项 | 内容 |
| --- | --- |
| ID | T11 |
| 状态 | 待开始 |
| 依赖 | T04、T07 |
| 执行角色 | executor |
| 预计产物 | 全量夹具、manifest 校验、`TapeekBench`、性能记录 |

## 必读

- [测试规格](../specs/testing-and-fixtures.md) 全文。
- [实施计划](../impl-plan.md) §11、§12。
- [Markdown 规格](../specs/markdown-preview.md) §3.2。
- [ZIP 规格](../specs/zip-preview.md) §9。

## 目标

补齐 T04/T06 未覆盖的样本，建立可重复的夹具校验和性能基准。此 ticket 不改变解析语义，只补测试与测量。

## 允许改动

- `scripts/make-fixtures.py`（扩展）
- `scripts/run-tests.sh`（新建）
- `Packages/TapeekCore/Package.swift`（添加 `TapeekBench` executable）
- `Packages/TapeekCore/Sources/TapeekBench/TapeekBench.swift`（新建，不要命名为 `main.swift`，避免与 `@main` 冲突）
- `Packages/TapeekCore/Tests/TapeekCoreTests/ManifestTests.swift`（新建）
- `Packages/TapeekCore/Tests/TapeekCoreTests/TestPaths.swift`（新建，测试路径辅助）
- `Samples/markdown/**`（补齐剩余样本）
- `Samples/zip/**`（补齐剩余样本与 manifest）
- `.build/fixtures/**`（生成的大样本，不提交）
- `docs/verification/T11.md`

## 禁止改动

- 不修改 `MarkdownLoader`、`ZipArchiveReader`、`ZipTree` 的实现。
- 不修改 UI。
- 不降低限额来让测试通过。
- 不把大样本提交到仓库。

## 前置检查

```sh
swift test --package-path Packages/TapeekCore
python3 --version
ls Samples/zip
```

确认 T04/T07 测试通过，基础夹具存在。

## 步骤

### 1. 补齐 Markdown 样本

按 [测试规格](../specs/testing-and-fixtures.md) §3 检查缺失项，至少补齐：

- `gfm.md` 若 T02 已创建，复核是否覆盖表格、任务列表、长代码。
- `chinese.md`
- `long-code.md`
- `wide-table.md`
- `tasks.md`
- `long.md`
- `raw-html.md`
- `image-no-alt.md`
- `many-front-matter.md`
- `relative-image.md` 与 `assets/pixel.png`
- `missing-image.md`
- `remote-image.md`

生成到 `.build/fixtures/`：

- `large-500kb.md`：约 500 KB，重复段落但包含不同标题。
- `large-2.1mb.md`：超过 2 MiB 上限。
- `exact-limit.md`：刚好 2 MiB（可选，用于边界测试）。

### 2. 补齐 ZIP 样本

扩展 `scripts/make-fixtures.py`：

- `zip64.zip`：70,000 个空条目，使用 `ZIP_STORED`，触发 ZIP64 EOCD；输出到 `.build/fixtures/`。
- `many-entries.zip`：25,000 个空条目，输出到 `.build/fixtures/`。
- `zip64-entry.zip`：单条目 `force_zip64=True`，保留在 `Samples/zip/`。
- `chinese-gbk.zip`：若 T06 未生成，补齐；手写 central directory，不设置 UTF-8 标志。
- `sfx.zip`：普通 ZIP 前加固定前缀。
- `symlink.zip`：`external_attr` 设置为 `S_IFLNK`。
- `macos-noise.zip`：包含 `__MACOSX/._readme.md` 和 `.DS_Store`。
- `duplicates.zip`、`unsafe-paths.zip`、`missing-dirs.zip`、`empty-dirs.zip`、`sort.zip`、`single-root.zip`、`long-names.zip`：若 T06 未生成，补齐。

固定时间戳、固定顺序、`ZIP_STORED` 或固定压缩级别。不要依赖运行时的随机数。

### 3. 生成 manifest

`Samples/zip/manifest.json` 至少包含：

```json
{
  "typical.zip": {
    "totalEntries": 9,
    "fileCount": 5,
    "directoryCount": 4,
    "totalUncompressedBytes": 1234,
    "hasEncryptedEntries": false,
    "zip64": false,
    "names": ["docs/", "docs/readme.md"]
  }
}
```

要求：

- 由 Python 独立计算，不调用 App 代码。
- 名称统一 NFC 并排序。
- 包含 `encrypted.zip`、`zip64-entry.zip`、`chinese-utf8.zip`、`chinese-gbk.zip`、`missing-dirs.zip`、`empty-dirs.zip`、`sort.zip`、`single-root.zip`、`macos-noise.zip`、`symlink.zip`。
- 大样本的 manifest 写到 `.build/fixtures/manifest.json`，不提交。

### 4. 实现 ManifestTests

`ManifestTests.swift`：

- 定位仓库根目录（用 `#filePath` 向上找到 `Packages` 的父目录）。
- 读取 `Samples/zip/manifest.json`。
- 对每个样本调用 `ZipArchiveReader.list`。
- 比较：
  - `totalEntryCount`（允许 manifest 为 null）。
  - `fileCount`、`directoryCount`。
  - `totalUncompressedBytes`。
  - `hasEncryptedEntries`。
  - 排序后的名称集合。
- 对 `.build/fixtures/manifest.json` 若存在，同样比较大样本。
- 失败时输出具体差异，不只输出「不相等」。

### 5. 实现 TapeekBench

在 `Package.swift` 添加：

```swift
.executableTarget(
    name: "TapeekBench",
    dependencies: ["TapeekCore"]
)
```

`Sources/TapeekBench/TapeekBench.swift`：

```swift
import Foundation
import TapeekCore

@main
struct TapeekBench {
    static func main() throws {
        // 解析参数：markdown|zip <path>
        // 运行 1 次预热 + 3 次计时
        // 输出 kind=... bytes/entries=... median_ms=... runs=3
    }
}
```

要求：

- `markdown`：调用 `MarkdownLoader.load(url:)`。
- `zip`：调用 `ZipArchiveReader.list(url:)`，再调用 `ZipTree(listing:archiveName:)`，覆盖完整列表构建。
- 使用 `ContinuousClock` 或 `DispatchTime.now().uptimeNanoseconds`。
- 输出机器可读的一行；错误输出到 stderr 并以非零退出。
- 不写入文件，不联网。

### 6. 实现 run-tests.sh

```sh
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift test --package-path Packages/TapeekCore
python3 -I scripts/make-fixtures.py --check
```

`--check` 行为：

- 校验 `Samples/zip/manifest.json` 与现有文件的结构一致（条目、名称、类型、大小）。
- 不比较压缩后字节的 SHA-256，避免不同 zlib 版本导致误报。
- 不重新生成已提交的样本。
- 缺失或结构不符时以非零退出，并打印差异。
- 大样本缺失时打印「未生成，跳过性能」而不是失败。

可选：若 `swiftlint` 存在，运行 `swiftlint lint --quiet`，但退出码不阻塞；把警告写入验收记录。

### 7. 运行基线与测试

```sh
./scripts/run-tests.sh
swift run --package-path Packages/TapeekCore TapeekBench markdown Samples/markdown/gfm.md
swift run --package-path Packages/TapeekCore TapeekBench markdown .build/fixtures/large-500kb.md
swift run --package-path Packages/TapeekCore TapeekBench zip Samples/zip/typical.zip
swift run --package-path Packages/TapeekCore TapeekBench zip .build/fixtures/many-entries.zip
swift run --package-path Packages/TapeekCore TapeekBench zip .build/fixtures/zip64.zip
```

Debug 和 Release 各记录一次：

```sh
swift build -c release --package-path Packages/TapeekCore
swift run -c release --package-path Packages/TapeekCore TapeekBench ...
```

要求：

- 每个样本 3 次，取中位数。
- 记录 macOS 版本、芯片、样本大小。
- 不把 Debug 数字当成最终性能。

### 8. 记录结果

`docs/verification/T11.md`：

| 样本 | Debug 中位数 | Release 中位数 | 目标 | 结论 |
| --- | --- | --- | --- | --- |
| gfm.md | | | ≤ 100 ms | |
| large-500kb.md | | | ≤ 300 ms | |
| typical.zip | | | ≤ 50 ms | |
| many-entries.zip | | | ≤ 1 s | |
| zip64.zip | | | ≤ 1 s | |

未达标时写实际影响和下一步，不修改目标数字来「通过」。

## 验收

| 项 | 命令 | 预期 |
| --- | --- | --- |
| 全部测试 | `./scripts/run-tests.sh` | 0 失败 |
| Manifest | `ManifestTests` | 所有样本与 manifest 一致 |
| 大样本 | `.build/fixtures/zip64.zip` 等存在 | 可由脚本重建 |
| 基准 Markdown | `TapeekBench markdown ...` | 输出中位数 |
| 基准 ZIP | `TapeekBench zip ...` | 输出中位数 |
| 无解析改动 | 文件清单 | 未修改 Core 解析实现 |
| 不提交大文件 | `git status` 或目录检查 | `.build/fixtures` 被忽略 |

## 证据

- `docs/verification/T11.md`：测试摘要、基准表、环境、未达标项。
- `scripts/make-fixtures.py --check` 输出。
- `TapeekBench` 输出片段。

## 停止条件

- 夹具生成不确定，两次运行 manifest 不一致。
- 大样本导致测试或基准超过 10 分钟。
- ManifestTests 发现解析错误 → 记录具体样本和差异，回到 T06/T07 修复；本 ticket 不直接改解析器。
- 性能目标需要大幅降低限额才能达到 → 请求协调者决定，不自行改规格。

## 交接

给 T12：

- 可重复的夹具与 manifest。
- `run-tests.sh`。
- `TapeekBench` 与性能基线。
- 未覆盖或未达标的项目。
