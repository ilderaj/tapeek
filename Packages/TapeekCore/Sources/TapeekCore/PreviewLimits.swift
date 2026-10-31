import Foundation

public struct PreviewLimits: Equatable, Sendable {
    public var maxMarkdownBytes: Int
    public var maxZipEntries: Int
    public var maxZipPathBytes: Int
    public var maxZipPathDepth: Int
    public var maxZipCentralDirectoryBytes: Int
    public var maxZipListingDuration: TimeInterval
    public var maxImageBytes: Int
    public var maxImagePixelSize: Int

    public init(
        maxMarkdownBytes: Int = 2 * 1024 * 1024,
        maxZipEntries: Int = 20_000,
        maxZipPathBytes: Int = 4_096,
        maxZipPathDepth: Int = 256,
        maxZipCentralDirectoryBytes: Int = 16 * 1024 * 1024,
        maxZipListingDuration: TimeInterval = 2.0,
        maxImageBytes: Int = 20 * 1024 * 1024,
        maxImagePixelSize: Int = 4_096
    ) {
        precondition(maxMarkdownBytes > 0, "maxMarkdownBytes must be positive")
        precondition(maxZipEntries > 0, "maxZipEntries must be positive")
        precondition(maxZipPathBytes > 0, "maxZipPathBytes must be positive")
        precondition(maxZipPathDepth > 0, "maxZipPathDepth must be positive")
        precondition(maxZipCentralDirectoryBytes > 0, "maxZipCentralDirectoryBytes must be positive")
        precondition(maxZipListingDuration > 0, "maxZipListingDuration must be positive")
        precondition(maxImageBytes > 0, "maxImageBytes must be positive")
        precondition(maxImagePixelSize > 0, "maxImagePixelSize must be positive")

        self.maxMarkdownBytes = maxMarkdownBytes
        self.maxZipEntries = maxZipEntries
        self.maxZipPathBytes = maxZipPathBytes
        self.maxZipPathDepth = maxZipPathDepth
        self.maxZipCentralDirectoryBytes = maxZipCentralDirectoryBytes
        self.maxZipListingDuration = maxZipListingDuration
        self.maxImageBytes = maxImageBytes
        self.maxImagePixelSize = maxImagePixelSize
    }

    public var isValid: Bool {
        maxMarkdownBytes > 0
            && maxZipEntries > 0
            && maxZipPathBytes > 0
            && maxZipPathDepth > 0
            && maxZipCentralDirectoryBytes > 0
            && maxZipListingDuration > 0
            && maxImageBytes > 0
            && maxImagePixelSize > 0
    }

    public static let `default` = PreviewLimits()
}
