import AppKit
import os
import QuickLookUI
import SwiftUI
import TapeekCore

private let logger = Logger(
    subsystem: "com.local.Tapeek.Preview",
    category: "preview"
)

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSView?

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        let started = Date()
        hostingView?.removeFromSuperview()

        let kind = PreviewKindResolver.resolve(fileURL: url)
        let host = NSHostingView(
            rootView: content(for: url, kind: kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        hostingView = host

        let duration = Int(Date().timeIntervalSince(started) * 1_000)
        logger.info(
            "preview kind=\(String(describing: kind), privacy: .public) duration_ms=\(duration, privacy: .public) result=success"
        )
        handler(nil)
    }

    private func content(for url: URL, kind: PreviewKind) -> AnyView {
        switch kind {
        case .markdown:
            return markdownContent(for: url)
        case .zip:
            return zipContent(for: url)
        case .unsupported:
            return AnyView(UnsupportedPreviewView())
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

    private func zipContent(for url: URL) -> AnyView {
        do {
            let listing = try ZipArchiveReader.list(url: url)

            if listing.entries.isEmpty && listing.totalEntryCount == 0 {
                return AnyView(ZipEmptyView())
            }
            if listing.entries.isEmpty && listing.skippedEntryCount > 0 {
                return AnyView(ZipAllSkippedView())
            }

            let tree = ZipTree(
                listing: listing,
                archiveName: url.deletingPathExtension().lastPathComponent
            )
            return AnyView(ZipPreviewView(tree: tree, fileURL: url))
        } catch let failure as PreviewFailure {
            return AnyView(ZipFailureView(failure: failure, fileURL: url))
        } catch {
            return AnyView(ZipFailureView(failure: .archiveUnreadable, fileURL: url))
        }
    }
}

private struct UnsupportedPreviewView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("无法预览此文件类型")
                .font(.title3.bold())
            Text("Tapeek 首版只支持 Markdown（.md、.markdown）和 ZIP（.zip）。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
