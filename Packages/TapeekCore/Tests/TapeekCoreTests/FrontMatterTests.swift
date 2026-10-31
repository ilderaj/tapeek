import Foundation
import XCTest
@testable import TapeekCore

final class FrontMatterTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func test_parse_validMetadata_removesBlockAndPreservesBody() throws {
        let source = "---\ntitle: Example\ntags: [swift, markdown]\ndate: 2026-10-31\nquoted: \"a value\"\nempty:   \n---\n# Body\n\nSecond paragraph\n"
        let document = try load(source)
        XCTAssertEqual(document.frontMatter, [
            FrontMatterEntry(key: "title", value: "Example"),
            FrontMatterEntry(key: "tags", value: "[swift, markdown]"),
            FrontMatterEntry(key: "date", value: "2026-10-31"),
            FrontMatterEntry(key: "quoted", value: "a value"),
            FrontMatterEntry(key: "empty", value: "")
        ])
        XCTAssertEqual(document.body, "# Body\n\nSecond paragraph\n")
    }

    func test_parse_duplicateKey_keepsFirstValue() throws {
        let document = try load("---\nname: first\nname: second\n---\nBody")
        XCTAssertEqual(document.frontMatter, [FrontMatterEntry(key: "name", value: "first")])
    }

    func test_parse_twentyOneEntries_keepsOnlyTwenty() throws {
        let fields = (1...21).map { "key\($0): value\($0)" }.joined(separator: "\n")
        let document = try load("---\n\(fields)\n---\nBody")
        XCTAssertEqual(document.frontMatter.count, 20)
        XCTAssertEqual(document.frontMatter.last?.key, "key20")
    }

    func test_parse_longValue_truncatesAndAddsEllipsis() throws {
        let value = String(repeating: "x", count: 513)
        let document = try load("---\nname: \(value)\n---\nBody")
        XCTAssertEqual(document.frontMatter.first?.value.count, 513)
        XCTAssertEqual(document.frontMatter.first?.value, String(repeating: "x", count: 512) + "…")
    }

    func test_parse_withoutClosingDelimiter_keepsOriginalText() throws {
        let source = "---\ntitle: Example\nBody"
        let document = try load(source)
        XCTAssertTrue(document.frontMatter.isEmpty)
        XCTAssertEqual(document.body, source)
    }

    func test_parse_delimiterNotOnFirstLine_keepsOriginalText() throws {
        let source = "\n---\ntitle: Example\n---\nBody"
        let document = try load(source)
        XCTAssertTrue(document.frontMatter.isEmpty)
        XCTAssertEqual(document.body, source)
    }

    func test_parse_crlf_preservesBodyLineEndings() throws {
        let document = try load("---\r\ntitle: Example\r\n---\r\nFirst\r\n\r\n  indented\r\n")
        XCTAssertEqual(document.frontMatter, [FrontMatterEntry(key: "title", value: "Example")])
        XCTAssertEqual(document.body, "First\r\n\r\n  indented\r\n")
    }

    func test_parse_onlyMetadata_returnsEmptyBody() throws {
        let document = try load("---\ntitle: Example\n---\n")
        XCTAssertEqual(document.frontMatter, [FrontMatterEntry(key: "title", value: "Example")])
        XCTAssertEqual(document.body, "")
    }

    func test_parse_emptyMetadataBlock_removesRecognizedBlock() throws {
        let document = try load("---\n# comment\ninvalid key: ignored\n  continuation: ignored\n---\nBody")
        XCTAssertTrue(document.frontMatter.isEmpty)
        XCTAssertEqual(document.body, "Body")
    }

    func test_parse_closingDelimiterBeyondEightKiB_keepsOriginalText() throws {
        let source = "---\n" + String(repeating: "a", count: 8 * 1024) + "\n---\nBody"
        let document = try load(source)
        XCTAssertTrue(document.frontMatter.isEmpty)
        XCTAssertEqual(document.body, source)
    }

    private func load(_ source: String) throws -> MarkdownDocument {
        try MarkdownLoader.load(data: Data(source.utf8), baseURL: baseURL)
    }
}
