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

    func testLongerFencePreservesShorterAndMismatchedMarkersAsContent() {
        let block = "````swift\n```\n## still code\n\n~~~\nlet done = true\n````"
        assertFenceStaysInOneChunk(block)
    }

    func testLongerMatchingCloserEndsFence() {
        let block = "```swift\nlet value = 1\n````"
        let text = "## Before\n\n\(block)\n\n## After\n\nTail."
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertTrue(chunks.contains { $0.contains(block) })
    }

    func testFenceCloserWithTrailingTextDoesNotClose() {
        let block = "```swift\n``` not a closer\n## still code\n\nlet done = true\n```"
        assertFenceStaysInOneChunk(block)
    }

    func testUnclosedFenceStaysInOneChunkThroughEndOfInput() {
        let block = "~~~text\n## still code\n\ncontent through EOF"
        assertFenceStaysInOneChunk(block)
    }

    func testFenceAllowsUpToThreeLeadingSpaces() {
        let block = "   ```text\n## still code\n\ncontent\n   ```"
        assertFenceStaysInOneChunk(block)
    }

    func testFourSpaceIndentedMarkerDoesNotOpenFence() {
        let text = "    ```text\n## heading\n\ncontent"
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testCRLFFenceStaysTogetherAndPreservesOriginalLineEndings() {
        let block = "```text\r\n## still code\r\n\r\ncontent\r\n```"
        let text = "## Before\r\n\r\n\(block)\r\n\r\n## After\r\n\r\nTail."
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertTrue(chunks.contains { $0.contains(block) })
    }

    func testBacktickInInfoStringDoesNotOpenFence() {
        let text = "```bad`\n## heading\n\ncontent"
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testEmptyDocument() {
        XCTAssertEqual(MarkdownChunker.chunks(""), [])
    }

    private func assertFenceStaysInOneChunk(_ block: String, file: StaticString = #filePath, line: UInt = #line) {
        let text = "## Before\n\n\(block)\n\n## After\n\nTail."
        let chunks = MarkdownChunker.chunks(text, targetBytes: 10)

        XCTAssertEqual(chunks.joined(separator: "\n"), text, file: file, line: line)
        XCTAssertTrue(chunks.contains { $0.contains(block) }, "Expected complete fenced block in one chunk", file: file, line: line)
    }
}
