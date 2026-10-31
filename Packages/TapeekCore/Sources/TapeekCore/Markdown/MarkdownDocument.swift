import Foundation

public struct FrontMatterEntry: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct MarkdownDocument: Equatable, Sendable {
    public let body: String
    public let frontMatter: [FrontMatterEntry]
    public let byteCount: Int
    public let encoding: MarkdownTextEncoding
    public let baseURL: URL

    public init(
        body: String,
        frontMatter: [FrontMatterEntry],
        byteCount: Int,
        encoding: MarkdownTextEncoding,
        baseURL: URL
    ) {
        self.body = body
        self.frontMatter = frontMatter
        self.byteCount = byteCount
        self.encoding = encoding
        self.baseURL = baseURL
    }
}

public enum MarkdownTextEncoding: String, Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}
