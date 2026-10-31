import Foundation
import XCTest
@testable import TapeekCore

final class Zip64Tests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip/zip64-entry.zip") }

    func testZIP64EndRecordsAndEntryExtra() throws {
        let listing = try ZipArchiveReader.list(url: fixture)
        XCTAssertEqual(listing.totalEntryCount, 1)
        XCTAssertEqual(listing.entries.map(\.path), ["zip64.txt"])
        XCTAssertEqual(listing.entries.first?.uncompressedSize, 5)
    }

    func testZIP64EntryWithMissingExtraIsSkippedWithWarning() throws {
        var archive = Data()
        let name = Data("n.txt".utf8)
        archive.zipAppend32(0x04034B50); archive.zipAppend16(20); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend32(0); archive.zipAppend32(0); archive.zipAppend32(0); archive.zipAppend16(UInt16(name.count)); archive.zipAppend16(0); archive.append(name)
        let cd = archive.count
        archive.zipAppend32(0x02014B50); archive.zipAppend16(20); archive.zipAppend16(20); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend32(0); archive.zipAppend32(0xFFFFFFFF); archive.zipAppend32(0xFFFFFFFF); archive.zipAppend16(UInt16(name.count)); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend32(0); archive.zipAppend32(0); archive.append(name)
        let cdSize = archive.count - cd
        archive.zipAppend32(0x06054B50); archive.zipAppend16(0); archive.zipAppend16(0); archive.zipAppend16(1); archive.zipAppend16(1); archive.zipAppend32(UInt32(cdSize)); archive.zipAppend32(UInt32(cd)); archive.zipAppend16(0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.write(to: url)
        let listing = try ZipArchiveReader.list(url: url)
        XCTAssertTrue(listing.entries.isEmpty)
        XCTAssertEqual(listing.skippedEntryCount, 1)
        XCTAssertTrue(listing.warnings.contains { if case .malformedEntry = $0 { true } else { false } })
    }

    func testSFXZIP64IsExplicitlyUnsupported() throws {
        var data = try Data(contentsOf: fixture)
        data.insert(contentsOf: Data(repeating: 0x41, count: 16), at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertThrowsError(try ZipArchiveReader.list(url: url)) { error in
            guard case PreviewFailure.archiveUnsupported(message: "自解压 ZIP64 暂不支持") = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}

private extension Data {
    mutating func zipAppend16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func zipAppend32(_ value: UInt32) { zipAppend16(UInt16(truncatingIfNeeded: value)); zipAppend16(UInt16(truncatingIfNeeded: value >> 16)) }
}
