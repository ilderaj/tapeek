import Foundation

public enum ZipWarning: Equatable, Sendable {
    case duplicatePath(String)
    case unsafePath(String)
    case invalidUTF8Name
    case guessedLegacyEncoding
    case truncated(shown: Int, total: Int?)
    case timedOut(shown: Int, total: Int?)
    case encryptedEntries(count: Int)
    case multiDiskUnsupported
    case malformedEntry(offset: Int)
}

public struct ZipListing: Equatable, Sendable {
    public let entries: [ZipEntry]
    public let shownEntryCount: Int
    public let totalEntryCount: Int?
    public let skippedEntryCount: Int
    public let isTruncated: Bool
    public let fileCount: Int
    public let directoryCount: Int
    public let totalUncompressedBytes: UInt64
    public let archiveBytes: UInt64
    public let hasEncryptedEntries: Bool
    public let warnings: [ZipWarning]

    public init(entries: [ZipEntry], shownEntryCount: Int, totalEntryCount: Int?, skippedEntryCount: Int, isTruncated: Bool, fileCount: Int, directoryCount: Int, totalUncompressedBytes: UInt64, archiveBytes: UInt64, hasEncryptedEntries: Bool, warnings: [ZipWarning]) {
        self.entries = entries
        self.shownEntryCount = shownEntryCount
        self.totalEntryCount = totalEntryCount
        self.skippedEntryCount = skippedEntryCount
        self.isTruncated = isTruncated
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalUncompressedBytes = totalUncompressedBytes
        self.archiveBytes = archiveBytes
        self.hasEncryptedEntries = hasEncryptedEntries
        self.warnings = warnings
    }
}
