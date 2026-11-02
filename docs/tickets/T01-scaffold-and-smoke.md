# T01 骨架、签名与最小预览

| 项 | 内容 |
| --- | --- |
| ID | T01 |
| 状态 | 完成 |
| 依赖 | 无 |
| 执行角色 | executor；接口与失败判断可由 thinker 复核 |
| 预计产物 | 可构建、可注册、可显示静态内容的宿主 App 与预览扩展 |

## 必读

- [PRD](../PRD.md) §3.1、§7。
- [实施计划](../impl-plan.md) §6、§7、§8 的 P0-1。
- [Quick Look 集成规格](../specs/quicklook-integration.md) §2 至 §6。

## 目标

在 Finder 或 `qlmanage` 中触发 Tapeek 的 Quick Look 扩展，看到一个包含 `TAPEEK-SMOKE` 的预览窗口。此 ticket 不实现 Markdown 或 ZIP 的真实渲染。

## 允许改动

- `project.yml`
- `.gitignore`
- `README.md`
- `TapeekApp/TapeekApp.swift`
- `TapeekApp/OnboardingView.swift`（可以只是占位视图）
- `TapeekApp/Info.plist`
- `TapeekApp/TapeekApp.entitlements`
- `TapeekPreview/PreviewViewController.swift`
- `TapeekPreview/Info.plist`
- `TapeekPreview/TapeekPreview.entitlements`
- `Samples/markdown/smoke.md`
- `scripts/generate.sh`
- `scripts/build.sh`
- `scripts/install-local.sh`
- `scripts/uninstall-local.sh`
- `scripts/verify-extension.sh`
- `docs/verification/T01.md`
- `docs/verification/T01-*.png`

## 禁止改动

- 不创建 `Packages/TapeekCore`；T03 才创建。
- 不添加 MarkdownUI 或其他第三方依赖；T02 才添加。
- 不实现真实的 Markdown/ZIP 解析。
- 不修改 Bear 或其他 App 的扩展状态。
- 不使用 `sudo`、不关闭 SIP、不添加全盘访问权限。

## 前置检查

执行前确认：

```sh
xcodegen --version
xcodebuild -version
sw_vers
uname -m
```

预期：XcodeGen 2.45.3 或兼容版本；Xcode 27.x；macOS 27.x；arm64。若版本不同，记录实际值，不擅自改部署目标。

## 步骤

### 1. 创建目录与忽略文件

创建：

```
TapeekApp/
TapeekPreview/
Samples/markdown/
scripts/
docs/verification/
```

`.gitignore` 至少包含：

```
.build/
DerivedData/
*.xcuserstate
xcuserdata/
.DS_Store
```

### 2. 创建宿主 App

`TapeekApp/TapeekApp.swift`：

- 使用 SwiftUI `@main`。
- 单窗口，标题 `Tapeek`。
- 内容调用 `OnboardingView`。
- 关闭最后一个窗口后退出 App（`NSApplicationDelegateAdaptor` 或 `applicationShouldTerminateAfterLastWindowClosed`）。

`OnboardingView` 暂时显示：

```
Tapeek
在 Finder 中按空格，直接阅读 Markdown 和 ZIP。
```

T10 会替换为正式页面。

### 3. 创建最小预览扩展

`TapeekPreview/PreviewViewController.swift`：

- `final class PreviewViewController: NSViewController, QLPreviewingController`。
- `loadView()` 设置空 `NSView`。
- `preparePreviewOfFile(at:completionHandler:)`：
  1. 移除旧子视图。
  2. 创建 `NSHostingView`，根视图显示 `TAPEEK-SMOKE`。
  3. 添加 Auto Layout 约束到四边。
  4. 调用 `handler(nil)`。
- 不读取文件内容，不启动后台任务。

示意：

```swift
import AppKit
import QuickLookUI
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        view.subviews.forEach { $0.removeFromSuperview() }
        let host = NSHostingView(
            rootView: Text("TAPEEK-SMOKE")
                .font(.system(size: 32, weight: .semibold))
                .padding(40)
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        handler(nil)
    }
}
```

### 4. 配置 project.yml

使用 [实施计划](../impl-plan.md) §6.2 的参考片段，但删除 `TapeekCore` 和 `MarkdownUI` 依赖。至少包含：

- 宿主 target `Tapeek`，类型 `application`，平台 macOS。
- 扩展 target `TapeekPreview`，类型 `app-extension`，平台 macOS。
- 扩展作为宿主依赖，`embed: true`、`codeSign: true`。
- 扩展设置 `APPLICATION_EXTENSION_API_ONLY: YES`。
- 扩展显式设置 `PRODUCT_BUNDLE_IDENTIFIER: com.local.Tapeek.Preview`，不要依赖 target 名推导出 `com.local.TapeekPreview`。
- 共享设置：`SWIFT_VERSION: "5.0"`、`MACOSX_DEPLOYMENT_TARGET: "27.0"`、`CODE_SIGN_STYLE: Manual`、`CODE_SIGN_IDENTITY: "-"`、`DEVELOPMENT_TEAM: ""`、`PROVISIONING_PROFILE_SPECIFIER: ""`、`ENABLE_HARDENED_RUNTIME: NO`。
- Bundle ID：`com.local.Tapeek` 与 `com.local.Tapeek.Preview`。
- 显式声明 `schemes.Tapeek`，避免 `xcodebuild -scheme Tapeek` 找不到 scheme：

```yaml
schemes:
  Tapeek:
    build:
      targets:
        Tapeek: all
    run:
      config: Debug
```

扩展 Info.plist 的 `NSExtension`：

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

Entitlements 只包含 `com.apple.security.app-sandbox` 为 `true`。

### 5. 创建烟雾样本

`Samples/markdown/smoke.md`：

```markdown
# Tapeek smoke test

TAPEEK-SMOKE
```

### 6. 创建脚本

所有脚本放在 `scripts/`，`chmod +x`，使用绝对路径推导仓库根目录。

`generate.sh`：

```sh
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --spec project.yml
```

`build.sh`：

```sh
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodebuild \
  -project Tapeek.xcodeproj \
  -scheme Tapeek \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
```

`install-local.sh` 按 [实施计划](../impl-plan.md) §7.3 实现，包含 `codesign --verify --deep --strict`、`lsregister`、`pluginkit -a`、`open`、`qlmanage -r`。每一步失败要打印命令并退出非零。

若 `~/Applications` 中的扩展始终不被系统发现，先记录 `pluginkit` 和日志，再请求用户同意后改安装到 `/Applications/Tapeek.app`；不要自行使用 `sudo` 或修改系统扩展数据库。

`uninstall-local.sh` 按 §7.6 实现，不删除用户文件。

`verify-extension.sh`：

```sh
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/Tapeek.app"
codesign --verify --deep --strict --verbose=2 "$APP"
pluginkit -m -p com.apple.quicklook.preview | grep -F "com.local.Tapeek.Preview"
```

### 7. 构建与安装

依次执行：

```sh
cd "/Users/jared/Personal Projects/Tapeek"
./scripts/generate.sh
./scripts/build.sh
./scripts/install-local.sh
./scripts/verify-extension.sh
```

记录每条命令的退出码和关键输出。

### 8. 触发预览

```sh
qlmanage -p Samples/markdown/smoke.md
```

若窗口没有出现 `TAPEEK-SMOKE`：

1. 执行 `pluginkit -e use -i com.local.Tapeek.Preview`。
2. 再执行 `qlmanage -r`。
3. 再次触发。
4. 若仍失败，记录 `pluginkit -m -v -i com.local.Tapeek.Preview`、`codesign` 和 `log show --last 5m --predicate 'process == "TapeekPreview"'` 的输出，停止。

### 9. 截图与记录

- 截取 Quick Look 窗口，保存为 `docs/verification/T01-01-smoke.png`。
- 按 [TEMPLATE](../verification/TEMPLATE.md) 写 `docs/verification/T01.md`。

## 验收

| 项 | 命令或操作 | 预期 |
| --- | --- | --- |
| 构建 | `./scripts/build.sh` | 退出码 0；产物含 `.appex` |
| 签名 | `codesign --verify --deep --strict` | 退出码 0 |
| 注册 | `pluginkit -m -p com.apple.quicklook.preview` | 包含 `com.local.Tapeek.Preview` |
| 预览 | `qlmanage -p Samples/markdown/smoke.md` | 窗口显示 `TAPEEK-SMOKE` |
| 冲突 | 查看实际选中的扩展 | 记录 Tapeek 或 Bear；若为 Bear，标记环境阻塞 |

对应规格用例：QL-001、QL-002、QL-003。

## 证据

- `docs/verification/T01.md`：命令、退出码、关键输出。
- `docs/verification/T01-01-smoke.png`：Quick Look 窗口。

## 停止条件

出现以下任一情况，停止并报告，不继续 T02：

- `codesign` 连续两次失败。
- `.appex` 不在 `Contents/PlugIns`，且一次修正后仍不在。
- `pluginkit` 看不到扩展，且一次修正后仍看不到。
- Quick Look 始终选择 Bear，且 `pluginkit -e use` 无效。
- 需要 `sudo`、关闭 SIP 或放宽沙盒才能继续。

## 交接

下一个 ticket 可以复用的内容：

- `project.yml` 的宿主/扩展结构。
- `scripts/` 的生成、构建、安装、卸载、验证命令。
- Bundle ID 与扩展 Info.plist 声明。
- 已确认的签名方式和扩展选择行为。
