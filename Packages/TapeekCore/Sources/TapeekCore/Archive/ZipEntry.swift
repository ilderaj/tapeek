import Foundation

public enum ZipEntryKind: String, Equatable, Sendable {
    case file, directory, symlink
}

public struct ZipEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let path: String
    public let name: String
    public let kind: ZipEntryKind
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let isEncrypted: Bool

    public init(id: String, path: String, name: String, kind: ZipEntryKind, uncompressedSize: UInt64, modificationDate: Date?, isEncrypted: Bool) {
        self.id = id
        self.path = path
        self.name = name
        self.kind = kind
        self.uncompressedSize = uncompressedSize
        self.modificationDate = modificationDate
        self.isEncrypted = isEncrypted
    }
}
