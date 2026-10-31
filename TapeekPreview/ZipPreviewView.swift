import AppKit
import SwiftUI
import TapeekCore

struct ZipPreviewView: View {
    let tree: ZipTree
    let fileURL: URL

    @State private var expanded: Set<String>

    init(tree: ZipTree, fileURL: URL) {
        self.tree = tree
        self.fileURL = fileURL
        _expanded = State(initialValue: tree.defaultExpandedIDs())
    }

    var body: some View {
        VStack(spacing: 0) {
            ZipHeader(tree: tree, fileURL: fileURL)
            ZipNoticeBar(listing: tree.listing)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tree.rows(expanded: expanded)) { row in
                        ZipTreeRow(row: row) {
                            toggle(row.node.id)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}

private struct ZipHeader: View {
    let tree: ZipTree
    let fileURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fileURL.path)

            HStack(spacing: 8) {
                Text(countText)
                if tree.listing.hasEncryptedEntries {
                    Text("含加密条目")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("未压缩 \(ByteFormat.string(tree.listing.totalUncompressedBytes)) · 压缩包 \(ByteFormat.string(tree.listing.archiveBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countText: String {
        let listing = tree.listing
        if listing.isTruncated {
            if let total = listing.totalEntryCount {
                return "已显示 \(listing.shownEntryCount) 项，共 \(total) 项"
            }
            return "已显示 \(listing.shownEntryCount) 项，总数未知"
        }
        if listing.skippedEntryCount > 0, let total = listing.totalEntryCount {
            return "已显示 \(listing.shownEntryCount) 项，共 \(total) 项（\(listing.skippedEntryCount) 项被跳过）"
        }
        return "\(tree.fileCount) 个文件，\(tree.directoryCount) 个文件夹"
    }
}

private struct ZipNoticeBar: View {
    let listing: ZipListing

    private var messages: [String] {
        var result: [String] = []

        if listing.isTruncated {
            if let total = listing.totalEntryCount {
                result.append("条目过多，仅显示前 \(listing.shownEntryCount) 项，共 \(total) 项。")
            } else {
                result.append("条目过多，仅显示前 \(listing.shownEntryCount) 项。")
            }
        }

        for warning in listing.warnings {
            switch warning {
            case let .timedOut(shown, _):
                result.append("读取超时，仅显示已读取的 \(shown) 项。")
            case let .encryptedEntries(count):
                result.append("压缩包包含 \(count) 个加密条目；首版只显示目录。")
            case .guessedLegacyEncoding:
                result.append("部分文件名使用旧式编码，显示可能有误。")
            case .duplicatePath:
                result.append("存在重复路径，已保留第一条。")
            case .unsafePath, .invalidUTF8Name, .malformedEntry:
                break
            case .multiDiskUnsupported:
                result.append("分卷压缩包暂不支持。")
            case .truncated:
                break
            }
        }

        if listing.skippedEntryCount > 0, !listing.isTruncated {
            result.append("\(listing.skippedEntryCount) 项因路径或编码问题被跳过。")
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
        }
    }
}

private struct ZipTreeRow: View {
    let row: ZipRow
    let onToggle: () -> Void

    private var node: ZipNode { row.node }
    private var isDirectory: Bool { node.kind == .directory }

    var body: some View {
        if isDirectory && !node.children.isEmpty {
            Button(action: onToggle) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("文件夹，\(node.name)，\(node.children.count) 项")
            .accessibilityValue(row.isExpanded ? "已展开" : "已折叠")
        } else {
            rowContent
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 16, height: 1)

            Image(systemName: chevronName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)

            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundStyle(isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(trailingText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .contentShape(Rectangle())
        .help(tooltip)
    }

    private var chevronName: String {
        guard isDirectory, !node.children.isEmpty else { return " " }
        return row.isExpanded ? "chevron.down" : "chevron.right"
    }

    private var iconName: String {
        switch node.kind {
        case .directory: return "folder"
        case .symlink: return "link"
        case .file: return "doc"
        }
    }

    private var trailingText: String {
        if isDirectory {
            return "\(node.children.count) 项"
        }
        return ByteFormat.string(node.uncompressedSize)
    }

    private var accessibilityLabel: String {
        switch node.kind {
        case .directory:
            return "文件夹，\(node.name)，\(node.children.count) 项"
        case .symlink:
            return "符号链接，\(node.name)，\(ByteFormat.string(node.uncompressedSize))"
        case .file:
            return "文件，\(node.name)，\(ByteFormat.string(node.uncompressedSize))"
        }
    }

    private var tooltip: String {
        let date = node.modificationDate.map(ZipDateFormatter.string) ?? "—"
        return "\(node.path)\n修改时间：\(date)"
    }
}

private enum ZipDateFormatter {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
