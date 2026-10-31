import SwiftUI
import TapeekCore

struct MarkdownEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("空文档")
                .font(.title3.bold())
            Text("这个文件没有可显示的内容。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MarkdownFailureView: View {
    let failure: PreviewFailure
    let fileURL: URL

    private var presentation: PreviewErrorPresentation {
        PreviewErrorPresentation(failure: failure, fileName: fileURL.lastPathComponent)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(presentation.title)
                .font(.title3.bold())
            Text(presentation.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(fileURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
