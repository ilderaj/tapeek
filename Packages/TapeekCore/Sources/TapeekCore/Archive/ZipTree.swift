import Foundation

public struct ZipNode: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let path: String
    public let kind: ZipEntryKind
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let isEncrypted: Bool
    public let children: [ZipNode]
}

public struct ZipRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let node: ZipNode
    public let depth: Int
    public let isExpanded: Bool
}

public struct ZipTree: Equatable, Sendable {
    public let root: ZipNode
    public let listing: ZipListing
    public let fileCount: Int
    public let directoryCount: Int

    private final class Builder {
        let id: String
        let name: String
        let path: String
        var kind: ZipEntryKind?
        var size: UInt64 = 0
        var date: Date?
        var encrypted = false
        var children: [String: Builder] = [:]
        init(id: String, name: String, path: String) { self.id = id; self.name = name; self.path = path }
    }

    public init(listing: ZipListing, archiveName: String) {
        self.listing = listing
        let root = Builder(id: "", name: URL(fileURLWithPath: archiveName).deletingPathExtension().lastPathComponent, path: "")
        for entry in listing.entries {
            let parts = entry.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty, parts.count <= 256 else { continue }
            var current = root
            for (index, part) in parts.enumerated() {
                let path = current.path.isEmpty ? part : current.path + "/" + part
                let child = current.children[part] ?? Builder(id: path, name: part, path: path)
                current.children[part] = child
                if index == parts.count - 1 {
                    if entry.kind == .directory || child.kind == .directory || index < parts.count - 1 {
                        child.kind = .directory
                        child.size = 0
                        if entry.kind == .directory { child.date = entry.modificationDate; child.encrypted = entry.isEncrypted }
                    } else {
                        child.kind = entry.kind
                        child.size = entry.uncompressedSize
                        child.date = entry.modificationDate
                        child.encrypted = entry.isEncrypted
                    }
                }
                current = child
            }
        }
        func freeze(_ builder: Builder) -> ZipNode {
            let children = builder.children.values.map(freeze).sorted { lhs, rhs in
                if lhs.kind == .directory && rhs.kind != .directory { return true }
                if lhs.kind != .directory && rhs.kind == .directory { return false }
                let compare = lhs.name.localizedStandardCompare(rhs.name)
                return compare == .orderedSame ? lhs.path < rhs.path : compare == .orderedAscending
            }
            return ZipNode(id: builder.id, name: builder.name, path: builder.path, kind: builder.kind ?? .directory, uncompressedSize: builder.kind == .directory ? 0 : builder.size, modificationDate: builder.date, isEncrypted: builder.encrypted, children: children)
        }
        self.root = freeze(root)
        func counts(_ node: ZipNode) -> (Int, Int) {
            node.children.reduce(into: (0, 0)) { result, child in
                let nested = counts(child)
                result.0 += child.kind == .directory ? 0 : 1
                result.1 += child.kind == .directory ? 1 : 0
                result.0 += nested.0
                result.1 += nested.1
            }
        }
        let count = counts(self.root)
        self.fileCount = count.0
        self.directoryCount = count.1
    }

    public func rows(expanded: Set<String>) -> [ZipRow] {
        var result: [ZipRow] = []
        var stack: [(ZipNode, Int)] = root.children.reversed().map { ($0, 0) }
        while let (node, depth) = stack.popLast() {
            let isExpanded = node.kind == .directory && expanded.contains(node.id)
            result.append(ZipRow(id: node.id, node: node, depth: depth, isExpanded: isExpanded))
            if isExpanded { for child in node.children.reversed() { stack.append((child, depth + 1)) } }
        }
        return result
    }

    public func defaultExpandedIDs() -> Set<String> {
        var result = Set(root.children.filter { $0.kind == .directory }.map(\.id))
        if root.children.count == 1, let only = root.children.first, only.kind == .directory {
            result.formUnion(only.children.filter { $0.kind == .directory }.map(\.id))
        }
        return result
    }
}
