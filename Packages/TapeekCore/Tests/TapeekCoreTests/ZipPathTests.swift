import Foundation
import XCTest
@testable import TapeekCore

final class ZipPathTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testUnsafeAndDuplicatePathsAreSkipped() throws {
        let unsafe = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("unsafe-paths.zip"))
        XCTAssertEqual(Set(unsafe.entries.map(\.path)), Set(["abs.txt", "safe.txt"]))
        XCTAssertEqual(unsafe.skippedEntryCount, 2)
        XCTAssertTrue(unsafe.warnings.contains { if case .unsafePath = $0 { true } else { false } })
        let duplicates = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("duplicates.zip"))
        XCTAssertEqual(duplicates.entries.count, 1)
        XCTAssertEqual(duplicates.entries[0].uncompressedSize, 5)
        XCTAssertTrue(duplicates.warnings.contains(.duplicatePath("same.txt")))
    }

    func testNFCBackslashesLeadingSlashAndPathLimits() throws {
        let data = makeArchive(names: ["a\\b.txt", "/root.txt", "./dot.txt", "e\u{301}.txt"])
        let url = try writeTemporary(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let listing = try ZipArchiveReader.list(url: url)
        XCTAssertEqual(Set(listing.entries.map(\.path)), Set(["a/b.txt", "root.txt", "dot.txt", "é.txt"]))
        let limited = try ZipArchiveReader.list(url: url, limits: PreviewLimits(maxZipPathBytes: 5))
        XCTAssertTrue(limited.skippedEntryCount > 0)
        let tooDeep = makeArchive(names: [(0...256).map { "d\($0)" }.joined(separator: "/") + "/x"])
        let deepURL = try writeTemporary(tooDeep)
        defer { try? FileManager.default.removeItem(at: deepURL) }
        let deepListing = try ZipArchiveReader.list(url: deepURL)
        XCTAssertEqual(deepListing.entries, [])
        XCTAssertEqual(deepListing.skippedEntryCount, 1)
    }

    func testDirectoryWinsOverFileWithSamePath() throws {
        let url = try writeTemporary(makeArchive(names: ["x", "x/"]))
        defer { try? FileManager.default.removeItem(at: url) }
        let listing = try ZipArchiveReader.list(url: url)
        XCTAssertEqual(listing.entries.count, 1)
        XCTAssertEqual(listing.entries.first?.kind, .directory)
        XCTAssertEqual(listing.skippedEntryCount, 1)
        XCTAssertTrue(listing.warnings.contains(.duplicatePath("x")))
    }

    private func writeTemporary(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: url); return url
    }

    private func makeArchive(names: [String]) -> Data {
        var local = Data(), central = Data()
        for name in names {
            let n = Data(name.utf8), off = UInt32(local.count)
            local.appendLE32(0x04034B50); local.appendLE16(20); local.appendLE16(0x0800); local.appendLE16(0); local.appendLE16(0); local.appendLE16(0); local.appendLE32(0); local.appendLE32(0); local.appendLE32(0); local.appendLE16(UInt16(n.count)); local.appendLE16(0); local.append(n)
            central.appendLE32(0x02014B50); central.appendLE16(20); central.appendLE16(20); central.appendLE16(0x0800); central.appendLE16(0); central.appendLE16(0); central.appendLE16(0); central.appendLE32(0); central.appendLE32(0); central.appendLE32(0); central.appendLE16(UInt16(n.count)); central.appendLE16(0); central.appendLE16(0); central.appendLE16(0); central.appendLE16(0); central.appendLE32(0); central.appendLE32(off); central.append(n)
        }
        var data = local + central
        data.appendLE32(0x06054B50); data.appendLE16(0); data.appendLE16(0); data.appendLE16(UInt16(names.count)); data.appendLE16(UInt16(names.count)); data.appendLE32(UInt32(central.count)); data.appendLE32(UInt32(local.count)); data.appendLE16(0)
        return data
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func appendLE32(_ value: UInt32) { appendLE16(UInt16(truncatingIfNeeded: value)); appendLE16(UInt16(truncatingIfNeeded: value >> 16)) }
}
