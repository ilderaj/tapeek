import XCTest
@testable import TapeekCore

final class MarkdownChunkerTests: XCTestCase {
    func testSmallDocumentStaysSingleChunk() {
        let text = "# Title\n\nA short paragraph.\n"
        XCTAssertEqual(MarkdownChunker.chunks(text), [text])
    }

    func testLargeDocumentSplitsAtHeadingsWithoutChangingContent() {
        let section = "## Section\n\nParagraph with some text.\n\n- a\n- b\n\n"
        let text = String(repeating: section, count: 1_000)
        let chunks = MarkdownChunker.chunks(text, targetBytes: 500)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertFalse(chunks.contains(where: \.isEmpty))
    }

    func testFencedCodeIsNotSplitAtHeadingLikeLine() {
        let text = """
        ## Intro

        ```markdown
        ## not a heading
        text
        ```

        ## Outro

        Tail.
        """
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertTrue(chunks.contains { $0.contains("## not a heading") })
        XCTAssertFalse(chunks.contains { $0.hasSuffix("```markdown") && !$0.contains("text") })
    }

    func testEmptyDocument() {
        XCTAssertEqual(MarkdownChunker.chunks(""), [])
    }
}
