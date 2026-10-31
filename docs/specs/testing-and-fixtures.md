# 测试、夹具与证据规格

## 1. 目的

本规格规定如何构造可重复的样本、如何验证 Markdown 与 ZIP 行为、如何测量性能，以及如何记录证据。执行 agent 不得用「手动看过，没问题」代替可复核的结果。

## 2. 目录

```
Samples/
├── markdown/          # 提交到仓库的静态样本
└── zip/               # 提交到仓库的 ZIP 样本与 manifest
.build/
└── fixtures/          # 生成的超大样本，不提交
docs/verification/     # 每个 ticket 的验收记录与截图
scripts/
├── make-fixtures.py
├── run-tests.sh
└── ...
```

## 3. Markdown 夹具

| 文件 | 用途 | 关键内容 |
| --- | --- | --- |
| `smoke.md` | T01 注册验证 | 唯一字符串 `TAPEEK-SMOKE` |
| `gfm.md` | 常用 GFM 渲染 | 标题、段落、强调、列表、任务列表、表格、代码、引用、分隔线、链接 |
| `chinese.md` | 中文排版 | 中英文数字混排、长段落、标点 |
| `front-matter.md` | 前置元数据 | `title`、`tags`、`date`、带引号值 |
| `malformed-front-matter.md` | 无闭合分隔符 | 开头 `---`，没有结束行 |
| `empty.md` | 空文档 | 0 字节 |
| `only-front-matter.md` | 只有元数据 | front matter 后无正文 |
| `utf8-bom.md` | BOM | UTF-8 BOM + 中文标题 |
| `utf16le.md` | UTF-16 LE | BOM + 中文正文 |
| `utf16be.md` | UTF-16 BE | BOM + 中文正文 |
| `invalid-utf8.md` | 编码错误 | 非法 UTF-8 字节序列 |
| `relative-image.md` | 相对图片 | 引用 `assets/pixel.png` |
| `missing-image.md` | 图片缺失 | 引用不存在的文件 |
| `remote-image.md` | 远程图片 | `https://example.com/x.png` |
| `long-code.md` | 长代码行 | 超过 200 字符的单行代码 |
| `wide-table.md` | 宽表格 | 8 列，长单元格 |
| `tasks.md` | 任务列表 | 已选、未选、嵌套 |
| `long.md` | 长文档 | 约 200 个段落 |
| `raw-html.md` | 原始 HTML | `<script>`、`<b>`、`<div>` |
| `image-no-alt.md` | 空 alt | `![](assets/pixel.png)` |
| `many-front-matter.md` | 多条目 | 12 个键值对 |

静态样本必须使用 UTF-8 保存，`utf16le.md`、`utf16be.md`、`utf8-bom.md` 和 `invalid-utf8.md` 例外。

`assets/pixel.png` 使用一个有效的 1×1 PNG，由生成脚本写出；不要提交 base64 文本冒充图片。

## 4. ZIP 夹具

| 文件 | 用途 | 预期 |
| --- | --- | --- |
| `typical.zip` | 基本树 | 两层目录、文件、显式空目录、中文名 |
| `flat.zip` | 扁平列表 | 所有文件在第一层 |
| `empty.zip` | 空包 | EOCD 条目数为 0 |
| `chinese-utf8.zip` | UTF-8 中文 | 标志 bit 11 置位，名称正确 |
| `chinese-gbk.zip` | 旧式编码 | 无 UTF-8 标志，GBK 字节，触发启发式或记录限制 |
| `encrypted.zip` | 加密标记 | 条目 flags bit 0 置位，名称可读 |
| `corrupt.zip` | 损坏 | 截断 EOCD 或目录，返回错误 |
| `zip64.zip` | ZIP64 EOCD | 70,000 条，触发 ZIP64 记录 |
| `zip64-entry.zip` | 条目级 ZIP64 | 单个条目带 ZIP64 extra |
| `many-entries.zip` | 条目上限 | 25,000 条，截断到 20,000 |
| `duplicates.zip` | 重复路径 | 同名文件出现两次 |
| `unsafe-paths.zip` | 路径安全 | `../evil.txt`、`/abs.txt`、`a/../../b.txt` |
| `missing-dirs.zip` | 合成父目录 | 只有 `a/b/c.txt`，没有目录条目 |
| `empty-dirs.zip` | 显式空目录 | `empty/`、`nested/empty/` |
| `sort.zip` | 排序 | 文件夹与文件混合，含数字名称 |
| `single-root.zip` | 单根目录 | 所有内容在 `Project/` 下 |
| `long-names.zip` | 长名称 | 接近 200 字符的文件名 |
| `macos-noise.zip` | 系统噪音 | `__MACOSX/._file`、`.DS_Store` |
| `symlink.zip` | 符号链接 | Unix mode 为 `S_IFLNK` |
| `sfx.zip` | 自解压前缀 | 普通 ZIP 前加任意字节 |
| `manifest.json` | 期望值 | 条目数、文件数、目录数、加密、ZIP64、名称列表 |

### 4.1 生成规则

`scripts/make-fixtures.py` 只使用 Python 标准库：

- 固定时间戳（例如 `2026-01-01 00:00:00`），保证重复生成结果稳定。
- 固定压缩级别，避免不同 zlib 版本产生不可比字节；测试只比较结构，不比较压缩后字节。
- 写入前删除旧文件，避免残留。
- 生成后打印每个文件的条目数和 SHA-256，写入 `manifest.json`。
- 大文件（`zip64.zip`、`many-entries.zip`、`large-2.1mb.md`）输出到 `.build/fixtures/`，不提交。
- `chinese-gbk.zip` 需要手写 ZIP 结构：使用 GBK 编码文件名字节，central directory 的 flags 不设置 bit 11。生成脚本必须显式构造 local header 和 central directory，不能依赖 `zipfile` 自动写入 UTF-8 标志。
- `encrypted.zip` 使用系统 `zip -P tapeek` 生成；若命令不可用，用脚本设置 flags bit 0 并写入未加密数据，仅用于列表测试，不得用于内容解密测试。
- `sfx.zip` 在普通 ZIP 前拼接一段固定文本，保持 EOCD 偏移相对原 ZIP 起点。

### 4.2 期望值

`manifest.json` 由生成脚本独立计算，不由 App 的解析器生成。至少包含：

```json
{
  "typical.zip": {
    "totalEntries": 9,
    "fileCount": 5,
    "directoryCount": 4,
    "totalUncompressedBytes": 1234,
    "hasEncryptedEntries": false,
    "zip64": false,
    "names": ["docs/", "docs/readme.md", "..."]
  }
}
```

数值以实际生成结果为准，文档中的示例不构成固定答案。测试读取 manifest，与 `ZipArchiveReader` 的结果比较；名称比较前统一 NFC 并排序。

### 4.3 与系统工具交叉验证

对每个非损坏的 ZIP：

```sh
unzip -Z1 Samples/zip/typical.zip | sort > /tmp/tapeek-expected-names.txt
unzip -l Samples/zip/typical.zip
```

测试或验收记录保存命令输出。解析结果与 `unzip` 的差异必须解释：

- `unzip` 会列出目录条目；本解析器也列出。
- `unzip` 可能省略某些系统条目；以 central directory 为准。
- 编码不同的名称按显示规则比较，不直接比较字节。

## 5. 自动化测试矩阵

### 5.1 Core 单元测试

| 测试组 | 覆盖 | 关键断言 |
| --- | --- | --- |
| `PreviewLimitsTests` | 默认值、边界 | 2 MiB、20,000、4,096、16 MiB、2 s |
| `PreviewKindTests` | 类型路由 | md/markdown/mdown/mkd/zip、大小写、未知类型 |
| `ByteReaderTests` | 小端读取 | 正常、越界、空数据、溢出 |
| `MarkdownLoaderTests` | 解码 | UTF-8、BOM、UTF-16 LE/BE、无效 UTF-8、NUL、空文件 |
| `MarkdownLimitTests` | 限额 | 刚好 2 MiB、超过 1 字节、文件增长 |
| `FrontMatterTests` | 前置元数据 | 正常、引号、空值、重复键、超过 20 项、无闭合、非首行 |
| `ZipEOCDTests` | EOCD | 正常、空包、注释、截断、多磁盘 |
| `Zip64Tests` | ZIP64 | EOCD、条目 extra、偏移 |
| `ZipEntryTests` | 字段 | 名称、大小、日期、目录、符号链接、加密 |
| `ZipEncodingTests` | 编码 | UTF-8 标志、无标志 UTF-8、CP437、GB18030 启发式 |
| `ZipPathTests` | 规范化 | 反斜杠、重复斜杠、`..`、绝对路径、NUL、超长 |
| `ZipTreeTests` | 树 | 合成父目录、去重、冲突、排序、子项数 |
| `ZipRowsTests` | 展开 | 默认展开、折叠、深度、稳定性 |
| `ZipListingTests` | 摘要 | 文件数、目录数、总大小、截断、跳过 |
| `ErrorMappingTests` | 错误 | 每个 `PreviewFailure` 对应一个错误视图模型 |

### 5.2 测试命名

```swift
func test_load_utf8BOM_removesBOM() throws
func test_list_zip64EOCD_readsAllEntries() throws
func test_rows_singleRoot_expandsTwoLevels() throws
```

测试名说明输入和预期，不使用 `test1`、`testWorks`。

### 5.3 运行

```sh
swift test --package-path Packages/TapeekCore
```

要求：

- 0 失败。
- 不允许跳过测试来通过验收；确实无法在当前系统运行的测试，必须在验收记录中写明原因。
- 测试输出保存到 `docs/verification/Txx.md` 的「命令与结果」表。

## 6. 手工测试

手工测试按 `quicklook-integration.md` 和两份功能规格的验收用例执行。每个用例至少保存一张截图或一段命令输出。

### 6.1 截图

- 使用 `screencapture -x` 或系统截图工具。
- 文件名：`Txx-序号-说明.png`，例如 `T05-01-light.png`。
- 截图必须包含 Quick Look 窗口内容，不得只截桌面。
- 深色模式另存一张，不覆盖浅色截图。
- 不对截图做裁剪以外的修饰；不要用示意图代替真实运行结果。

### 6.2 目录写入检查

预览 ZIP 前后执行：

```sh
find "$(dirname "$ZIP")" -maxdepth 2 -not -name '.DS_Store' -print | sort > /tmp/tapeek-before.txt
# 预览
find "$(dirname "$ZIP")" -maxdepth 2 -not -name '.DS_Store' -print | sort > /tmp/tapeek-after.txt
diff -u /tmp/tapeek-before.txt /tmp/tapeek-after.txt
```

预期无差异。把 `diff` 输出写入验收记录。

### 6.3 网络检查

首版没有网络权限。验证方式：

- 代码审查：搜索 `URLSession`、`NetworkImage`、`http`、`WKWebView`，确认没有调用路径。
- 关闭 Wi-Fi 后预览远程图片样本，确认正文和占位正常。
- 不要求用抓包工具证明「零请求」；代码审查 + 离线测试足够。

## 7. 性能测量

### 7.1 基准工具

`TapeekBench` 是 Core 包中的可执行 target，提供：

```sh
swift run --package-path Packages/TapeekCore TapeekBench markdown <path>
swift run --package-path Packages/TapeekCore TapeekBench zip <path>
```

输出：

```
kind=markdown bytes=512000 median_ms=84 runs=3
kind=zip entries=20000 median_ms=310 runs=3
```

要求：

- 每个样本运行 3 次，取中位数。
- 第一次运行不计入，避免冷启动偏差。
- 记录 macOS 版本、芯片、样本路径和字节数。
- 不把 Debug 构建的数字当作最终性能；Debug 和 Release 各记录一次。

### 7.2 目标

| 样本 | 目标 |
| --- | --- |
| `gfm.md`（≤ 100 KB） | 解析 ≤ 100 ms |
| `large-500kb.md` | 解析 ≤ 300 ms |
| `many-entries.zip`（25,000 条，截断到 20,000） | 列表 ≤ 1 s |
| `zip64.zip`（70,000 条，截断到 20,000） | 列表 ≤ 1 s |
| `typical.zip` | 列表 ≤ 50 ms |

未达标时：

1. 先确认测量方法正确。
2. 再优化解析循环或降低上限。
3. 仍不达标，在验收记录中写实际值、影响和后续计划，不伪造通过。

## 8. 证据模板

每个 ticket 新建 `docs/verification/Txx.md`，使用 [TEMPLATE.md](../verification/TEMPLATE.md)。

最低内容：

- 执行日期、执行者、环境。
- 改动文件列表。
- 命令、退出码、关键输出。
- 自动化测试结果。
- 手工用例逐项结果。
- 截图文件名与说明。
- 未通过项、阻塞原因、下一步。
- 结论只能是「通过」「部分通过」「阻塞」三者之一。

## 9. 最终验收

`docs/verification/FINAL.md` 汇总：

| PRD 验收标准 | 证据 | 结论 |
| --- | --- | --- |
| Markdown 样本可读 | MD-001 至 MD-022 | 通过/失败 |
| ZIP 样本符合 F2 | ZIP-001 至 ZIP-025 | 通过/失败 |
| 不产生解压文件、不联网 | ZIP-022、QL-010、QL-011 | 通过/失败 |
| 超限有明确降级 | MD-010、ZIP-009、ZIP-021 | 通过/失败 |
| 宿主 App 可用 | APP-001 至 APP-010 | 通过/失败 |
| 全部 ticket 有证据 | 各 Txx 文件 | 通过/失败 |

任何一项失败，MVP 不得标记完成。环境阻塞（例如 Bear 抢占）单独列出，不混入功能失败。
