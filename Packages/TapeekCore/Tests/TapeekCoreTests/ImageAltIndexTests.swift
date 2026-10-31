import XCTest
@testable import TapeekCore

final class ImageAltIndexTests: XCTestCase {
    func testRelativeAndRemoteImageAlts() {
        let baseURL = URL(fileURLWithPath: "/tmp/notes/", isDirectory: true)
        let markdown = """
        ![pixel](assets/pixel.png)
        ![remote](https://example.com/x.png)
        """
        let index = ImageAltIndex(markdown: markdown, baseURL: baseURL)

        XCTAssertEqual(
            index.alt(for: URL(fileURLWithPath: "/tmp/notes/assets/pixel.png")),
            "pixel"
        )
        XCTAssertEqual(
            index.alt(for: URL(string: "https://example.com/x.png")!),
            "remote"
        )
    }

    func testTitleAndEmptyAlt() {
        let baseURL = URL(fileURLWithPath: "/tmp/notes/", isDirectory: true)
        let markdown = """
        ![diagram](assets/diagram.png "Diagram title")
        ![](assets/empty.png)
        """
        let index = ImageAltIndex(markdown: markdown, baseURL: baseURL)

        XCTAssertEqual(
            index.alt(for: URL(fileURLWithPath: "/tmp/notes/assets/diagram.png")),
            "diagram"
        )
        XCTAssertEqual(
            index.alt(for: URL(fileURLWithPath: "/tmp/notes/assets/empty.png")),
            ""
        )
    }

    func testFirstAltWinsAndFencedCodeIsIgnored() {
        let baseURL = URL(fileURLWithPath: "/tmp/notes/", isDirectory: true)
        let markdown = """
        ![first](assets/a.png)
        ![second](assets/a.png)

        ```markdown
        ![inside](assets/inside.png)
        ```
        """
        let index = ImageAltIndex(markdown: markdown, baseURL: baseURL)

        XCTAssertEqual(
            index.alt(for: URL(fileURLWithPath: "/tmp/notes/assets/a.png")),
            "first"
        )
        XCTAssertNil(index.alt(for: URL(fileURLWithPath: "/tmp/notes/assets/inside.png")))
    }
}
