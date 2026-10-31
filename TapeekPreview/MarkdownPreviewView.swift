import AppKit
import MarkdownUI
import SwiftUI
import TapeekCore

struct MarkdownPreviewView: View {
    let document: MarkdownDocument
    let fileURL: URL
    private let altIndex: ImageAltIndex

    init(document: MarkdownDocument, fileURL: URL) {
        self.document = document
        self.fileURL = fileURL
        self.altIndex = ImageAltIndex(
            markdown: document.body,
            baseURL: document.baseURL
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !document.frontMatter.isEmpty {
                    FrontMatterCard(entries: document.frontMatter)
                }

                if document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("正文为空")
                        .foregroundStyle(.secondary)
                } else {
                    Markdown(
                        document.body,
                        baseURL: document.baseURL,
                        imageBaseURL: document.baseURL
                    )
                    .markdownImageProvider(
                        LocalImageProvider(altIndex: altIndex)
                    )
                    .tapeekMarkdownStyle()
                    .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                return .handled
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}

private struct FrontMatterCard: View {
    let entries: [FrontMatterEntry]

    private var visibleEntries: [FrontMatterEntry] {
        Array(entries.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文档信息")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(visibleEntries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.key)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)

                    Text(entry.value.isEmpty ? "—" : entry.value)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .font(.callout)
            }

            if entries.count > visibleEntries.count {
                Text("还有 \(entries.count - visibleEntries.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
