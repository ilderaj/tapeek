# T10 宿主 App 单页说明

| 项 | 内容 |
| --- | --- |
| ID | T10 |
| 状态 | 待开始 |
| 依赖 | T01 |
| 执行角色 | executor |
| 预计产物 | 单窗口启用说明、示例文件入口、系统设置跳转 |

## 必读

- [宿主 App 规格](../specs/host-app.md) 全文。
- [Quick Look 集成规格](../specs/quicklook-integration.md) §6。
- [PRD](../PRD.md) §4 F4。

## 目标

把 T01 的占位页面替换为正式单页：说明如何启用扩展、打开系统设置、在 Finder 中查看示例文件。不伪造扩展状态，不添加设置项。

## 允许改动

- `TapeekApp/TapeekApp.swift`
- `TapeekApp/OnboardingView.swift`
- `project.yml`（只添加示例资源）
- `TapeekApp/Resources/Samples/gfm.md`
- `TapeekApp/Resources/Samples/typical.zip`
- `docs/verification/T10.md`
- `docs/verification/T10-*.png`

## 禁止改动

- 不修改预览扩展的解析或视图。
- 不修改扩展 Info.plist。
- 不添加网络、分析、账户、更新器或偏好设置。
- 不通过 shell 调用 `pluginkit` 检测扩展状态。
- 不写入用户目录。

## 前置检查

```sh
./scripts/build.sh
open "$HOME/Applications/Tapeek.app"
```

确认 T01 的占位窗口可以打开。

## 步骤

### 1. 实现窗口

`TapeekApp.swift`：

- SwiftUI `@main`。
- 单窗口，标题 `Tapeek`。
- 关闭最后一个窗口后退出。
- 窗口默认 640 × 480，最小 520 × 420。
- 不使用 `WindowGroup` 创建多个窗口；使用 `Window`（macOS 13+）或设置 `.windowResizability`。
- 不添加菜单栏常驻项。

### 2. 实现 OnboardingView

布局按 [宿主 App 规格](../specs/host-app.md) §3：

1. 图标 `doc.text.magnifyingglass`。
2. 标题 `Tapeek`。
3. 副标题 `在 Finder 中按空格，直接阅读 Markdown 和 ZIP。`
4. 三步说明：
   - `打开「系统设置」→「通用」→「登录项与扩展」→「Quick Look」。`
   - `启用 Tapeek。`
   - `回到 Finder，选中 .md 或 .zip 文件，按空格。`
5. 状态说明块：
   ```
   扩展状态由系统管理，App 无法可靠读取。
   如果预览没有出现，请确认 Tapeek 扩展已启用，并尝试重新打开 Finder。
   ```
6. 按钮：`打开扩展设置`、`查看示例文件`。
7. 页脚：`本地处理 · 只读预览 · 不联网`，以及版本号。

要求：

- 标题和步骤使用系统字体，不使用自定义品牌字体。
- 状态块背景 `Color.secondary.opacity(0.08)`，圆角 8，内边距 12。
- 内容最大宽度 520，水平居中。
- 窗口变窄时按钮换行或纵向排列。
- 所有文字可选中复制。
- 不显示绿色勾选、警告三角或「已启用」状态。

### 3. 打开扩展设置

实现 `openExtensionSettings()`：

1. 尝试：

```swift
URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPoint=com.apple.quicklook.preview")
```

2. 失败后尝试：

```swift
URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")
```

3. 再失败，打开 `System Settings.app`。
4. 全部失败，在按钮下方显示：

```
请手动进入「系统设置」→「通用」→「登录项与扩展」。
```

要求：

- 不弹出自定义错误对话框。
- 不调用 `Process` 或 shell。
- 记录实际成功的 URL 到验收文件，供后续系统版本参考。

### 4. 查看示例文件

- 将 `Samples/markdown/gfm.md` 复制到 `TapeekApp/Resources/Samples/gfm.md`。
- 在临时目录创建示例 ZIP，再复制到 `TapeekApp/Resources/Samples/typical.zip`：

```sh
TMP="$(mktemp -d)"
ROOT="$(pwd)"
mkdir -p "$TMP/docs"
mkdir -p "$ROOT/TapeekApp/Resources/Samples"
printf 'Tapeek sample\n' > "$TMP/readme.txt"
printf 'ZIP preview sample\n' > "$TMP/docs/note.txt"
(cd "$TMP" && /usr/bin/zip -q -r "$ROOT/TapeekApp/Resources/Samples/typical.zip" .)
rm -rf "$TMP"
```

- 在 `project.yml` 中把这两个文件加入宿主 target 的 resources。
- 使用 `Bundle.main.url(forResource:withExtension:subdirectory:)` 定位；若资源被 Xcode 扁平化，按实际路径调整，并在验收记录中写明。
- 使用 `NSWorkspace.shared.activateFileViewerSelecting([markdownURL, zipURL])`。
- 资源缺失时，在按钮下方显示：

```
示例文件缺失，请重新安装 Tapeek。
```

- 不自动打开预览，不复制到 Downloads。

### 5. 版本号

- 从 `Bundle.main.infoDictionary["CFBundleShortVersionString"]` 读取。
- 显示 `版本 0.1`；未知时显示 `版本 —`。
- 不在代码中写死版本。

### 6. 构建与截图

```sh
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
open "$HOME/Applications/Tapeek.app"
```

截图：

- `T10-01-light.png`
- `T10-02-dark.png`
- `T10-03-narrow.png`
- `T10-04-settings.png`（系统设置打开后的页面）
- `T10-05-samples.png`（Finder 选中示例文件）

### 7. 手工验证

- 点击「打开扩展设置」，记录打开的页面。
- 点击「查看示例文件」，确认 Finder 选中两个文件。
- 关闭窗口，确认 App 退出。
- 切换深色外观，确认对比度。
- 用 VoiceOver 浏览标题、步骤和按钮。
- 搜索代码确认没有 `URLSession`、分析 SDK 或 `Process`。

## 验收

| 项 | 操作 | 预期 |
| --- | --- | --- |
| 启动 | 打开 App | 单窗口，内容完整 |
| 设置 | 点击按钮 | 打开系统设置；失败有回退 |
| 示例 | 点击按钮 | Finder 选中两个示例文件 |
| 关闭 | 关闭窗口 | App 退出 |
| 深色 | 切换外观 | 对比度正常 |
| 窄窗口 | 缩小到最小 | 不横向溢出 |
| 状态 | 观察界面 | 不伪造扩展状态 |
| 资源缺失 | 临时重命名资源 | 显示内联提示，不崩溃 |
| 隐私 | 代码审查 | 无网络、无分析、无用户目录写入 |
| 可访问性 | VoiceOver | 标题、步骤、按钮可朗读 |

对应规格用例：APP-001 至 APP-010。

## 证据

`docs/verification/T10.md`：命令、截图、实际设置 URL、资源路径、VoiceOver 结果、未通过项。

## 停止条件

- 所有设置 URL 都失败，且无法打开系统设置。
- 示例资源无法被宿主 App 读取。
- 需要网络、分析 SDK 或额外文件权限才能完成页面。
- 窗口无法限制为单实例。

## 交接

给 T12：

- 可用的宿主页面与两个按钮。
- 实际设置 URL 和回退路径。
- 示例资源的 bundle 路径。
- 截图与已知系统差异。
