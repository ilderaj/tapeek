# Quick Look 集成规格（F3）

## 1. 范围

本规格覆盖宿主 App 与预览扩展的打包关系、扩展声明、系统调用入口、视图生命周期、路由、签名、安装、缓存刷新、扩展冲突和验证命令。

不覆盖：App Store 上架、公证、自动更新、Thumbnail 扩展、Spotlight 导入器、旧式 `.qlgenerator`。

## 2. 组件关系

```
Tapeek.app
└── Contents/
    ├── MacOS/Tapeek
    ├── Info.plist
    └── PlugIns/
        └── TapeekPreview.appex
            ├── Contents/MacOS/TapeekPreview
            └── Contents/Info.plist
```

- 预览扩展必须嵌入宿主 App 的 `Contents/PlugIns`。
- 宿主 App 负责被 LaunchServices 发现、展示启用说明、打开系统设置。
- 预览扩展负责实现 `QLPreviewingController`，不依赖宿主 App 的运行时状态。
- 扩展不能读取宿主 App 的 bundle 资源；需要的资源应放在扩展 target 自己的 Resources 中，或由 Core 生成。

## 3. 扩展声明

### 3.1 Info.plist

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.quicklook.preview</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).PreviewViewController</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>QLSupportedContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
            <string>public.zip-archive</string>
        </array>
        <key>QLSupportsSearchableItems</key>
        <false/>
    </dict>
</dict>
```

要求：

- `NSExtensionPointIdentifier` 必须准确。
- `NSExtensionPrincipalClass` 使用 `$(PRODUCT_MODULE_NAME)`，不要手写可能变化的模块名。
- 首版使用 view-based，不设置 `QLIsDataBasedPreview`。
- 不声明 `public.plain-text`，避免抢占普通 `.txt` 预览。
- `QLSupportedContentTypes` 需要精确匹配系统识别出的 UTI；技术核查提示父 UTI 不会自动匹配，T01 用 `mdls` 与本机预览确认。
- 不支持 Spotlight 可搜索条目。

### 3.2 Entitlements

扩展：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

宿主 App：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

首版不添加：

- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-write`
- 全盘访问
- 临时路径例外
- 自动化或 Apple Events 权限

若相对图片因沙盒不可读，按 Markdown 规格显示占位，不放宽权限。

### 3.3 Build settings

扩展 target 必须：

- `APPLICATION_EXTENSION_API_ONLY = YES`。
- `SKIP_INSTALL = YES`（由 XcodeGen 处理，验证产物位置）。
- 与宿主使用相同的 `MACOSX_DEPLOYMENT_TARGET`。
- 使用 ad-hoc 签名时，`CODE_SIGN_STYLE = Manual`、`CODE_SIGN_IDENTITY = "-"`、`DEVELOPMENT_TEAM` 为空。

## 4. 视图生命周期

`PreviewViewController` 是 `NSViewController` 并遵守 `QLPreviewingController`。

```swift
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSView?

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        // 1. 清理旧视图
        // 2. 解析路由
        // 3. 读取并构建 SwiftUI 视图
        // 4. 添加到 self.view
        // 5. handler(nil)
    }
}
```

必须遵守：

1. 每次调用 `preparePreviewOfFile` 都重建内容视图，不复用上一个文件的视图或状态。
2. 在调用 `handler` 前，视图层级已经建立，内容已经可显示。
3. 解析失败时，显示本地的错误视图，并调用 `handler(nil)`；只有扩展本身无法初始化时才把错误传给 `handler`。
4. 不持有文件句柄、`FileHandle` 或大块 `Data` 超过本次预览所需。
5. 不在预览之上再 present 其他 view controller。
6. 不在 `handler` 返回后启动后台任务、轮询或网络请求。
7. 不使用 `NSApp.activate` 或抢占焦点。
8. 视图的 `frame` 由 Quick Look 决定；使用 Auto Layout 或 SwiftUI 自适应，不强制窗口尺寸。

### 4.1 多文件切换

Quick Look 可能复用同一个扩展进程或控制器。T09 必须验证：

- 先预览 A.md，再预览 B.md：B 的内容完整出现，A 的内容不残留。
- 先预览 A.zip，再预览 B.md：不显示上一个目录树。
- 快速连续切换：不崩溃，不显示混合内容。
- 旧视图在重建前从父视图移除，并释放引用。

## 5. 路由

使用 `PreviewKindResolver`：

| 条件 | 视图 |
| --- | --- |
| `UTType` 符合 `net.daringfireball.markdown` 或扩展名为 `.md`、`.markdown`、`.mdown`、`.mkd` | `MarkdownPreviewView` |
| `UTType` 符合 `public.zip-archive` 或扩展名为 `.zip` | `ZipPreviewView` |
| 其他 | 不支持视图，显示「无法预览此文件类型」 |

路由不得依赖文件名内容或 MIME 猜测。系统已经把文件交给扩展，扩展只做类型分流。

## 6. 安装与注册

### 6.1 构建产物

确认以下路径存在：

```
$HOME/Applications/Tapeek.app
$HOME/Applications/Tapeek.app/Contents/PlugIns/TapeekPreview.appex
```

### 6.2 注册

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Tapeek.app"
pluginkit -a "$HOME/Applications/Tapeek.app/Contents/PlugIns/TapeekPreview.appex"
open "$HOME/Applications/Tapeek.app"
qlmanage -r
```

`open` 宿主 App 是为了让系统完成注册；不需要用户每次使用前打开 App。

### 6.3 检查

```sh
pluginkit -m -p com.apple.quicklook.preview | grep -F "com.local.Tapeek.Preview"
pluginkit -m -v -i com.local.Tapeek.Preview
```

预期：条目存在，路径指向 `TapeekPreview.appex`。

### 6.4 优先级

```sh
pluginkit -e use -i com.local.Tapeek.Preview
```

系统仍可能按自身规则选择其他扩展。验证时：

1. 先只用 `pluginkit -e use` 让 Tapeek 优先。
2. 如果 Bear 仍被选中，记录实际行为。
3. 不自动执行 `pluginkit -e ignore` 停用 Bear；需要用户明确同意后才能临时调整。
4. 验证结束后，如果调整过 Bear，恢复原状态。

### 6.5 缓存刷新

预览未更新时，按顺序尝试：

```sh
qlmanage -r
qlmanage -r cache
```

仍不生效时，退出并重新打开 Finder 或重启系统。不要在脚本里默认 `killall Finder`；这会打断用户工作。

## 7. 扩展冲突

本机注册了 Bear 的 Quick Look 扩展，但技术核查未见其 Info.plist 声明 `QLSupportedContentTypes`，因此不能直接断言它一定处理 `.md`。系统对同一 UTI 的多个预览扩展也没有公开的稳定优先级承诺，实际选择可能受启用状态、用户选择、安装顺序和缓存影响。

处理规则：

- 不承诺「安装 Tapeek 后一定覆盖 Bear」。
- 先用 `log show` 或 `pluginkit` 确认实际被调用的扩展，再判断是否存在冲突。
- 宿主 App 和文档提供检查步骤，不提供「强制替换」按钮。
- 验证记录必须写明当时哪个扩展被选中。
- 若系统选择 Bear，Tapeek 的验收项标记为「环境阻塞」，不能写成功能失败。
- 用户需要在系统设置中调整扩展顺序或停用另一个扩展时，由用户自己操作。

## 8. 签名与权限

### 8.1 ad-hoc

首版默认：

```sh
codesign --force --deep --sign - "$HOME/Applications/Tapeek.app"
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/Tapeek.app"
```

Xcode 构建时已经通过 `CODE_SIGN_IDENTITY="-"` 完成签名；安装后再次验证。不要用 `--deep` 作为日常签名的唯一手段，它只用于验证和本机修复。

ad-hoc 签名的 designated requirement 会随每次构建变化（TN3127）。可能出现扩展已注册、`codesign` 通过，但 Finder 仍回退到系统纯文本或其他 provider 的情况。T01 必须记录：

- 扩展是否出现在 `pluginkit`。
- 预览是否实际由 Tapeek 提供。
- 重新构建后是否仍生效。

若只有首次构建有效、重建后失效，停止并请求用户同意改用 Apple Development 证书；不要通过反复重签同一构建碰运气。

### 8.2 失败处理

如果扩展未被系统加载：

1. 检查 `.appex` 是否在 `Contents/PlugIns`。
2. 检查扩展 Info.plist 的 `NSExtensionPointIdentifier` 和 principal class。
3. 检查 `codesign --verify --deep --strict`。
4. 查看日志：

```sh
log show --last 5m --predicate 'process == "TapeekPreview"' --style compact
```

5. 仍失败：记录完整命令输出，停止。不要关闭 SIP、不要修改系统扩展数据库、不要给扩展添加全盘访问。

### 8.3 开发证书

只有在 ad-hoc 被证明不可用，且用户明确同意后，才使用 Apple Development 或 Developer ID。切换时需要：

- 设置 `DEVELOPMENT_TEAM`。
- 可能需要 provisioning profile。
- 重新验证扩展注册。
- 更新安装脚本与验收记录。

本轮不预设团队 ID，不在文档中记录证书身份。

## 9. 网络与文件访问

- 扩展不发起网络请求，不加载远程图片，不访问远程 URL。
- 扩展只读取系统交给它的文件；相对图片是否可读由沙盒决定。
- 不写入用户目录、`~/Library`、`/tmp` 或 ZIP 包内路径。
- 不创建解压目录。
- 不缓存预览内容到磁盘。

## 10. 验收用例

| ID | 前置 | 操作 | 预期 | 证据 |
| --- | --- | --- | --- | --- |
| QL-001 | 已安装 Tapeek | `pluginkit -m -p com.apple.quicklook.preview` | 输出包含 `com.local.Tapeek.Preview` | 命令输出 |
| QL-002 | 已注册 | `codesign --verify --deep --strict` | 退出码 0 | 命令输出 |
| QL-003 | 已注册 | `qlmanage -p Samples/markdown/smoke.md` | 显示 `TAPEEK-SMOKE` | 截图 |
| QL-004 | Finder 中选中 `.md` | 按空格 | 显示 Markdown 预览，不是源码或 Bear 预览 | 截图 |
| QL-005 | Finder 中选中 `.zip` | 按空格 | 显示目录树 | 截图 |
| QL-006 | 连续预览两个不同文件 | 切换 | 内容不串台 | 截图/录屏 |
| QL-007 | 扩展未启用 | 预览 `.md` | 系统回退到默认预览，Tapeek 不崩溃 | 记录 |
| QL-008 | Bear 扩展启用 | 预览 `.md` | 记录实际选中的扩展；不自动停用 Bear | 记录 |
| QL-009 | 任意样本 | 切换深色外观 | 预览跟随系统，无浅底浅字 | 截图 |
| QL-010 | 远程图片样本 | 关闭网络后预览 | 不发起网络请求，显示占位 | 截图 + 代码审查 |
| QL-011 | 任意 ZIP | 预览前后 `find` 样本目录 | 没有新增解压文件 | 命令输出 |
| QL-012 | 安装脚本 | 连续执行两次 | 第二次仍成功，不重复注册或报错 | 命令输出 |
| QL-013 | 卸载脚本 | 执行后检查 `pluginkit` | Tapeek 扩展条目消失，Bear 状态不变 | 命令输出 |
| QL-014 | 修改扩展后 | `qlmanage -r` 后预览 | 新版本生效 | 截图 |
| QL-015 | 不可读或损坏文件 | 空格预览 | 显示错误视图，Finder 不崩溃 | 截图 |
| QL-016 | 扩展视图 | 调整 Quick Look 窗口大小 | 内容自适应，无横向溢出（表格/代码块自身滚动除外） | 截图 |

## 11. 回退方案：data-based HTML

只有在 T02 决策门判定 view-based 不可用时使用。切换后：

- Info.plist 增加 `QLIsDataBasedPreview = true`。
- Principal class 改为 `$(PRODUCT_MODULE_NAME).PreviewProvider`，继承 `QLPreviewProvider`。
- 实现 `providePreview(for:)`，返回 `QLPreviewReply(dataOfContentType: .html, contentSize: ...)`。
- HTML 使用内联 CSS，不依赖 JavaScript、远程资源或 WKWebView。
- 相对图片如可读，作为 `QLPreviewReplyAttachment` 以 `cid:` 引用；不可读则输出占位。
- ZIP 仍使用同一份 Core 列表数据，生成静态 HTML 表格或嵌套列表。
- 该方案的滚动、文本选择和深色模式由系统 HTML 渲染器决定，验收标准相应调整，但「不联网、不写入、错误可见」不变。

切换方案必须更新 PRD、规格、tickets 和验收记录，不能只在代码里悄悄替换。

## 12. 已知限制

- 系统对多个预览扩展的选择没有稳定保证。
- Quick Look 扩展生命周期短，不能依赖常驻状态或跨文件缓存。
- 扩展沙盒默认只保证被预览文件的读取权限。
- 扩展内不能读取宿主 App 的 bundle 资源。
- 旧式 `.qlgenerator` 不再使用。
- 首次安装后可能需要用户手动启用扩展。
