import XCTest
@testable import TapeekCore

final class PreviewKindTests: XCTestCase {
    func testExtensionResolution_isCaseInsensitive() {
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: "MD"), .markdown)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: ".markdown"), .markdown)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: "mdown"), .markdown)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: "mkd"), .markdown)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: "ZIP"), .zip)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: "txt"), .unsupported)
        XCTAssertEqual(PreviewKindResolver.resolve(pathExtension: ""), .unsupported)
    }

    func testFileURLResolution_usesContentTypeAndFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdownURL = directory.appendingPathComponent("note.md")
        let zipURL = directory.appendingPathComponent("archive.zip")
        let textURL = directory.appendingPathComponent("note.txt")

        try Data("# note".utf8).write(to: markdownURL)
        try Data().write(to: zipURL)
        try Data("text".utf8).write(to: textURL)

        XCTAssertEqual(PreviewKindResolver.resolve(fileURL: markdownURL), .markdown)
        XCTAssertEqual(PreviewKindResolver.resolve(fileURL: zipURL), .zip)
        XCTAssertEqual(PreviewKindResolver.resolve(fileURL: textURL), .unsupported)
    }
}
