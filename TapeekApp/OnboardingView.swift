import AppKit
import SwiftUI

struct OnboardingView: View {
    @State private var settingsHint: String?
    @State private var sampleHint: String?

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                steps
                statusBlock
                actions
                footer
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Tapeek")
                .font(.largeTitle.bold())

            Text("在 Finder 中按空格，直接阅读 Markdown 和 ZIP。")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepRow(number: 1, text: "打开「系统设置」→「通用」→「登录项与扩展」→「Quick Look」。")
            StepRow(number: 2, text: "启用 Tapeek。")
            StepRow(number: 3, text: "回到 Finder，选中 .md 或 .zip 文件，按空格。")
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("扩展状态由系统管理，App 无法可靠读取。")
            Text("如果预览没有出现，请确认 Tapeek 扩展已启用，并尝试重新打开 Finder。")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("打开扩展设置") {
                    openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("查看示例文件") {
                    showSampleFiles()
                }
                .buttonStyle(.bordered)
            }

            if let settingsHint {
                Text(settingsHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sampleHint {
                Text(sampleHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("本地处理 · 只读预览 · 不联网")
                Spacer()
                Text("版本 \(version)")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private func openExtensionSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPoint=com.apple.quicklook.preview",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                settingsHint = nil
                return
            }
        }

        let systemSettings = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(systemSettings) {
            settingsHint = "请手动进入「系统设置」→「通用」→「登录项与扩展」。"
        } else {
            settingsHint = "无法打开系统设置。请手动进入「系统设置」→「通用」→「登录项与扩展」。"
        }
    }

    private func showSampleFiles() {
        guard let markdown = sampleURL(name: "gfm", extension: "md"),
              let zip = sampleURL(name: "typical", extension: "zip") else {
            sampleHint = "示例文件缺失，请重新安装 Tapeek。"
            return
        }

        sampleHint = nil
        NSWorkspace.shared.activateFileViewerSelecting([markdown, zip])
    }

    private func sampleURL(name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Samples")
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                )

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
