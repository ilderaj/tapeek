import AppKit
import QuickLookUI
import SwiftUI
import TapeekCore

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSView?

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        hostingView?.removeFromSuperview()

        let host = NSHostingView(
            rootView: content(for: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        hostingView = host
        handler(nil)
    }

    private func content(for url: URL) -> AnyView {
        switch PreviewKindResolver.resolve(fileURL: url) {
        case .markdown:
            return markdownContent(for: url)
        case .zip:
            return AnyView(
                Text("ZIP-TODO")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            )
        case .unsupported:
            return AnyView(
                Text("无法预览此文件类型")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            )
        }
    }

    private func markdownContent(for url: URL) -> AnyView {
        do {
            let document = try MarkdownLoader.load(url: url)
            if document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               document.frontMatter.isEmpty {
                return AnyView(MarkdownEmptyView())
            }
            return AnyView(MarkdownPreviewView(document: document, fileURL: url))
        } catch let failure as PreviewFailure {
            return AnyView(MarkdownFailureView(failure: failure, fileURL: url))
        } catch {
            return AnyView(MarkdownFailureView(failure: .unreadableFile, fileURL: url))
        }
    }
}
