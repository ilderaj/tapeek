import SwiftUI
import TapeekCore

struct ZipEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("压缩包为空")
                .font(.title3.bold())
            Text("这个 ZIP 没有可显示的条目。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct ZipAllSkippedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("无法显示压缩包目录")
                .font(.title3.bold())
            Text("所有条目路径均无效或无法解码。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct ZipFailureView: View {
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
