import Foundation
import XCTest
@testable import TapeekCore

final class ZipEncodingTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testUTF8FlagAndUnflaggedGB18030Heuristic() throws {
        let utf8 = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("chinese-utf8.zip"))
        XCTAssertEqual(utf8.entries.first?.path, "你好/文件.txt")
        let gbk = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("chinese-gbk.zip"))
        XCTAssertEqual(gbk.entries.first?.path, "中文.txt")
        XCTAssertTrue(gbk.warnings.contains(.guessedLegacyEncoding))
    }

    func testUnflaggedUTF8AndCP437Fallback() throws {
        let utf8URL = try temporaryArchive(name: Data("你好.txt".utf8), flags: 0)
        let cp437URL = try temporaryArchive(name: Data([0x63, 0x61, 0x66, 0x82, 0x2E, 0x74, 0x78, 0x74]), flags: 0)
        defer {
            try? FileManager.default.removeItem(at: utf8URL)
            try? FileManager.default.removeItem(at: cp437URL)
        }
        XCTAssertEqual(try ZipArchiveReader.list(url: utf8URL).entries.first?.path, "你好.txt")
        let cp437 = try ZipArchiveReader.list(url: cp437URL)
        XCTAssertEqual(cp437.entries.first?.path, "café.txt")
        XCTAssertFalse(cp437.warnings.contains(.guessedLegacyEncoding))
    }

    func testInvalidFlaggedUTF8RemainsVisibleWithWarning() throws {
        let name = Data([0xFF, 0x2E, 0x74, 0x78, 0x74])
        let url = try temporaryArchive(name: name, flags: 0x0800)
        defer { try? FileManager.default.removeItem(at: url) }
        let listing = try ZipArchiveReader.list(url: url)
        XCTAssertEqual(listing.entries.count, 1)
        XCTAssertTrue(listing.warnings.contains(.invalidUTF8Name))
    }

    private func temporaryArchive(name: Data, flags: UInt16) throws -> URL {
        var archive = Data()
        archive.appendLE32(0x04034B50); archive.appendLE16(20); archive.appendLE16(flags); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE32(0); archive.appendLE32(0); archive.appendLE32(0); archive.appendLE16(UInt16(name.count)); archive.appendLE16(0); archive.append(name)
        let cd = archive.count
        archive.appendLE32(0x02014B50); archive.appendLE16(20); archive.appendLE16(20); archive.appendLE16(flags); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE32(0); archive.appendLE32(0); archive.appendLE32(0); archive.appendLE16(UInt16(name.count)); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE32(0); archive.appendLE32(0); archive.append(name)
        let cdSize = archive.count - cd
        archive.appendLE32(0x06054B50); archive.appendLE16(0); archive.appendLE16(0); archive.appendLE16(1); archive.appendLE16(1); archive.appendLE32(UInt32(cdSize)); archive.appendLE32(UInt32(cd)); archive.appendLE16(0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try archive.write(to: url)
        return url
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func appendLE32(_ value: UInt32) { appendLE16(UInt16(truncatingIfNeeded: value)); appendLE16(UInt16(truncatingIfNeeded: value >> 16)) }
}
