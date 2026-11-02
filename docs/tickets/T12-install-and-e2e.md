# T12 安装脚本与端到端验收

| 项 | 内容 |
| --- | --- |
| ID | T12 |
| 状态 | 完成 |
| 依赖 | T09、T10、T11 |
| 执行角色 | executor；验收判断可由 thinker 复核 |
| 预计产物 | 可重复的安装/卸载脚本、完整验收记录与截图 |

## 必读

- [Quick Look 集成规格](../specs/quicklook-integration.md) §6、§7、§10。
- [Markdown 规格](../specs/markdown-preview.md) §10。
- [ZIP 规格](../specs/zip-preview.md) §10。
- [宿主 App 规格](../specs/host-app.md) §8。
- [测试规格](../specs/testing-and-fixtures.md) §6 至 §9。

## 目标

把已实现的功能安装到本机 Quick Look，按 PRD 验收标准跑完端到端检查，留下可复核的命令输出和截图。此 ticket 不新增功能。

## 允许改动

- `scripts/install-local.sh`
- `scripts/uninstall-local.sh`
- `scripts/verify-extension.sh`
- `scripts/build.sh`（仅修复路径或错误处理）
- `README.md`（只补充运行与启用说明）
- `docs/verification/T12.md`
- `docs/verification/T12-*.png`
- `docs/verification/T12-*.txt`

## 禁止改动

- 不修改 Core 解析、UI 布局或扩展声明。
- 不降低限额、不删除测试、不跳过失败用例来让验收通过。
- 不自动停用 Bear 或其他扩展。
- 不使用 `sudo`、不关闭 SIP、不添加全盘访问。
- 不把未验证项写成「通过」。

## 前置检查

```sh
./scripts/run-tests.sh
./scripts/build.sh
```

要求 T11 的测试通过，构建成功。若失败，回到对应 ticket，不开始端到端验收。

## 步骤

### 1. 完成安装脚本

`install-local.sh` 必须：

1. 从仓库根目录推导绝对路径。
2. 检查构建产物存在；不存在时提示先运行 `build.sh`，退出非零。
3. 创建 `$HOME/Applications`。
4. 删除旧的 `$HOME/Applications/Tapeek.app`。
5. 用 `ditto` 复制新 App。
6. `codesign --verify --deep --strict --verbose=2`。
7. `lsregister -f` 注册 App。
8. `pluginkit -a` 注册扩展。
9. `open` 宿主 App 一次。
10. `qlmanage -r`。
11. 打印下一步检查命令。

要求：

- 每一步失败都打印命令和退出码，不以「忽略错误」继续。
- 可重复执行，不产生重复注册或残留。
- 不修改用户文档、不修改其他 App。

`uninstall-local.sh` 必须：

1. `pluginkit -e ignore -i com.local.Tapeek.Preview`，失败不阻塞。
2. `pluginkit -r` 移除扩展，失败不阻塞。
3. 删除 `$HOME/Applications/Tapeek.app`。
4. `qlmanage -r`。
5. 不删除用户文件，不修改 Bear 设置。

`verify-extension.sh` 必须：

1. 检查 App 存在。
2. `codesign --verify --deep --strict`。
3. `pluginkit -m -p com.apple.quicklook.preview` 过滤 Tapeek。
4. 输出扩展路径和当前选择状态。
5. 可选接收一个文件路径，执行 `qlmanage -p` 冒烟测试。

### 2. 验证可重复安装

```sh
./scripts/install-local.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

预期：

- 两次安装都成功。
- 第二次不报「已存在」错误，不产生重复条目。
- 扩展条目唯一。

### 3. 检查扩展选择

```sh
pluginkit -m -v -i com.local.Tapeek.Preview
pluginkit -e use -i com.local.Tapeek.Preview
log show --last 5m --predicate 'process == "TapeekPreview"' --style compact
```

记录：

- Tapeek 是否出现在 `pluginkit`。
- 实际预览由谁提供。
- 若 Bear 被选中，记录其 bundle id 和现象；不执行停用。
- 若 Tapeek 未被调用，记录日志并停止。

### 4. 跑 Markdown 用例

按 [Markdown 规格](../specs/markdown-preview.md) §10 逐项执行。至少覆盖：

- MD-001 GFM。
- MD-002 中文。
- MD-003 front matter。
- MD-004 无闭合 front matter。
- MD-005 空文档。
- MD-006 只有元数据。
- MD-007/008 BOM 与 UTF-16。
- MD-009 编码错误。
- MD-010 超大文档（`.build/fixtures/large-2.1mb.md`）。
- MD-011/012/013 图片。
- MD-014 外链。
- MD-015 长代码。
- MD-016 宽表格。
- MD-017 任务列表。
- MD-018 深色。
- MD-019 长文档。
- MD-020 原始 HTML。
- MD-021 空 alt。
- MD-022 多 front matter。

每项：

- 截图保存为 `T12-MD-xxx-说明.png`。
- 在 `T12.md` 记录实际结果。
- 失败项写明现象、复现步骤和对应 ticket；不要标记通过。

### 5. 跑 ZIP 用例

按 [ZIP 规格](../specs/zip-preview.md) §10 逐项执行。至少覆盖：

- ZIP-001 典型树。
- ZIP-002 扁平。
- ZIP-003 空包。
- ZIP-004 UTF-8 中文。
- ZIP-005 GBK 名称。
- ZIP-006 加密。
- ZIP-007 损坏。
- ZIP-008 ZIP64。
- ZIP-009 25,000 条截断。
- ZIP-010 重复路径。
- ZIP-011 非法路径。
- ZIP-012 缺失父目录。
- ZIP-013 空目录。
- ZIP-014 排序。
- ZIP-015 摘要。
- ZIP-016 单根默认展开。
- ZIP-017 长名称。
- ZIP-018 macOS 噪音。
- ZIP-019 符号链接。
- ZIP-020 自解压前缀。
- ZIP-021 分卷（如无样本，记录未覆盖）。
- ZIP-022 无解压文件。
- ZIP-023 多文件切换。
- ZIP-024 深色。
- ZIP-025 截断文案。

截图命名 `T12-ZIP-xxx-说明.png`。

### 6. 跑宿主 App 用例

按 [宿主 App 规格](../specs/host-app.md) §8 执行 APP-001 至 APP-010，保存截图。

### 7. 检查无写入与无网络

ZIP：

```sh
find Samples/zip -maxdepth 2 -not -name '.DS_Store' -print | sort > /tmp/tapeek-before.txt
# 预览 typical.zip，展开目录
find Samples/zip -maxdepth 2 -not -name '.DS_Store' -print | sort > /tmp/tapeek-after.txt
diff -u /tmp/tapeek-before.txt /tmp/tapeek-after.txt
```

预期无差异。保存 diff 输出到 `T12-no-write.txt`。

网络：

```sh
grep -RInE "URLSession|AsyncImage|WKWebView|NetworkImage|http://|https://" \
  TapeekPreview Packages/TapeekCore
```

预期：没有 `URLSession`、`AsyncImage`、`WKWebView` 或 `NetworkImage` 调用；`http`/`https` 字符串只允许出现在链接白名单和文档中。逐条检查 grep 命中，不把白名单字符串当成网络请求。保存输出到 `T12-network-review.txt`。再关闭网络预览 `remote-image.md`，确认正文和占位正常。

### 8. 卸载与重装

```sh
./scripts/uninstall-local.sh
pluginkit -m -p com.apple.quicklook.preview | grep -F "com.local.Tapeek.Preview" || true
./scripts/install-local.sh
./scripts/verify-extension.sh
```

预期：

- 卸载后 Tapeek 扩展条目消失。
- Bear 状态不变。
- 重装后恢复，预览仍可用。

### 9. 记录结果

`docs/verification/T12.md`：

- 环境、命令、退出码。
- 用例逐项表：ID、结果、证据文件。
- 失败项与对应 ticket。
- 环境阻塞（如 Bear 抢占、ad-hoc 回退）。
- 结论：通过 / 部分通过 / 阻塞。

## 验收

| 项 | 命令或操作 | 预期 |
| --- | --- | --- |
| 重复安装 | 连续执行两次 | 成功，无重复条目 |
| 签名 | `codesign --verify --deep --strict` | 退出码 0 |
| 注册 | `pluginkit` | 扩展存在 |
| 预览 | `.md` 与 `.zip` | 分别显示正确视图 |
| 用例 | MD/ZIP/APP 列表 | 全部通过或有明确记录 |
| 无解压 | `find` + `diff` | 无新增文件 |
| 无网络 | 代码审查 + 离线预览 | 无请求，占位正常 |
| 卸载 | `uninstall-local.sh` | 扩展移除，Bear 不变 |
| 重装 | `install-local.sh` | 恢复可用 |
| 证据 | `T12.md` + 截图 | 完整、可复核 |

## 证据

- `docs/verification/T12.md`。
- 按用例编号命名的截图。
- `T12-no-write.txt`、`T12-network-review.txt`。
- 安装、卸载、`pluginkit`、`log show` 的命令输出。

## 停止条件

- 扩展无法注册或无法被调用，且 T01 的修复方法无效。
- 需要停用 Bear 才能继续，但用户未同意。
- 端到端用例出现崩溃、数据串台或解压写入。
- 需要修改功能代码才能通过验收；先回到对应 ticket，不在本 ticket 直接改。

## 交接

给 T13：

- 完整验收记录。
- 失败与阻塞清单。
- 环境差异（扩展选择、签名、系统设置路径）。
- 已知限制。
