import Foundation
import XCTest
@testable import TapeekCore

final class ZipListingTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testSummaryEncryptionTypesAndZip64Listing() throws {
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("typical.zip"))
        XCTAssertEqual(listing.shownEntryCount, listing.entries.count)
        XCTAssertEqual(listing.fileCount, 3)
        XCTAssertEqual(listing.directoryCount, 2)
        XCTAssertEqual(listing.totalUncompressedBytes, 25)
        let encrypted = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("encrypted.zip"))
        XCTAssertTrue(encrypted.hasEncryptedEntries)
        XCTAssertTrue(encrypted.entries.allSatisfy(\.isEncrypted))
        let symlink = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("symlink.zip"))
        XCTAssertEqual(symlink.entries.first?.kind, .symlink)
    }

    func testEntryAndDirectoryLimitsReturnPartialListing() throws {
        let limits = PreviewLimits(maxZipEntries: 2)
        let limited = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("flat.zip"), limits: limits)
        XCTAssertEqual(limited.entries.count, 2)
        XCTAssertTrue(limited.isTruncated)
        XCTAssertTrue(limited.warnings.contains { if case .truncated = $0 { true } else { false } })
    }

    func testCentralDirectoryByteLimitMarksListingTruncated() throws {
        let limits = PreviewLimits(maxZipCentralDirectoryBytes: 46)
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("flat.zip"), limits: limits)
        XCTAssertTrue(listing.isTruncated)
        XCTAssertTrue(listing.warnings.contains { if case .truncated = $0 { true } else { false } })
    }

    func testFixtureManifestMatchesStandardSamples() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        for name in ["typical.zip", "flat.zip", "chinese-utf8.zip"] {
            let expected = try XCTUnwrap(manifest[name])
            let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent(name))
            let expectedNames = try XCTUnwrap(expected["names"] as? [String]).map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }.sorted()
            XCTAssertEqual(listing.entries.map(\.path).sorted(), expectedNames)
            XCTAssertEqual(listing.fileCount, expected["fileCount"] as? Int)
            XCTAssertEqual(listing.directoryCount, expected["directoryCount"] as? Int)
            XCTAssertEqual(listing.totalUncompressedBytes, UInt64(expected["totalUncompressedBytes"] as? Int ?? -1))
        }
    }

    func testTimeoutReturnsPartialListingWithWarning() throws {
        let limits = PreviewLimits(maxZipListingDuration: 0.000000001)
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("flat.zip"), limits: limits)
        XCTAssertTrue(listing.isTruncated)
        XCTAssertTrue(listing.warnings.contains { if case .timedOut = $0 { true } else { false } })
    }

    func testListingDoesNotWriteBesideArchive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = dir.appendingPathComponent("input.zip")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("typical.zip"), to: archive)
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        _ = try ZipArchiveReader.list(url: archive)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), before)
    }
}
