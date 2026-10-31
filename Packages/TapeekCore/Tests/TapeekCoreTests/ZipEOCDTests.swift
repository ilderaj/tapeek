import Foundation
import XCTest
@testable import TapeekCore

final class ZipEOCDTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testTypicalEmptyCommentSFXAndCorruptArchives() throws {
        XCTAssertEqual(try ZipArchiveReader.list(url: fixtures.appendingPathComponent("typical.zip")).totalEntryCount, 5)
        let empty = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("empty.zip"))
        XCTAssertEqual(empty.entries, [])
        XCTAssertFalse(empty.isTruncated)
        XCTAssertTrue(empty.warnings.isEmpty)
        XCTAssertEqual(try ZipArchiveReader.list(url: fixtures.appendingPathComponent("sfx.zip")).entries.count, 5)
        XCTAssertThrowsError(try ZipArchiveReader.list(url: fixtures.appendingPathComponent("corrupt.zip")))
    }

    func testCommentAndTrailingBytesAreAccepted() throws {
        let original = try Data(contentsOf: fixtures.appendingPathComponent("empty.zip"))
        var commented = original
        commented[original.count - 2] = 3
        commented.append(contentsOf: [0x61, 0x62, 0x63])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try commented.write(to: url)
        XCTAssertEqual(try ZipArchiveReader.list(url: url).entries, [])
    }

    func testMultiDiskIsRejected() throws {
        var data = try Data(contentsOf: fixtures.appendingPathComponent("empty.zip"))
        data[data.count - 18] = 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertThrowsError(try ZipArchiveReader.list(url: url)) { error in
            guard case PreviewFailure.archiveUnsupported = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}
