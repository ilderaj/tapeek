import Foundation
import XCTest
@testable import TapeekCore

final class ManifestTests: XCTestCase {
    private struct Override {
        var names: [String]? = nil
        var fileCount: Int? = nil
        var directoryCount: Int? = nil
        var totalUncompressedBytes: UInt64? = nil
    }

    private struct NameFacts {
        let names: [String]
        let fileCount: Int
        let directoryCount: Int
    }

    private struct ExpectedListing {
        let totalEntries: Int?
        let fileCount: Int
        let directoryCount: Int
        let totalUncompressedBytes: UInt64
        let hasEncryptedEntries: Bool
        let names: [String]
        let isTruncated: Bool?
    }

    private enum ManifestError: Error {
        case invalidFormat
    }

    /// Fixtures whose raw central-directory names need documented parser semantics.
    private let overrides: [String: Override] = [
        // GBK bytes are decoded through the GB18030 heuristic by the reader.
        "chinese-gbk.zip": Override(names: ["中文.txt"]),
        // The first duplicate wins (5 bytes); the second is skipped.
        "duplicates.zip": Override(fileCount: 1, totalUncompressedBytes: 5),
        // The listing counts symlinks among files; the raw manifest excludes them.
        "symlink.zip": Override(fileCount: 1),
        // Leading slash is stripped; paths containing ".." are skipped.
        "unsafe-paths.zip": Override(fileCount: 2),
    ]

    func test_committedManifestMatchesReaderListing() throws {
        let manifestURL = TestPaths.zip.appendingPathComponent("manifest.json")
        let manifest = try loadManifest(manifestURL)
        XCTAssertFalse(manifest.isEmpty, "Samples/zip/manifest.json is empty")

        for name in manifest.keys.sorted() {
            let url = TestPaths.zip.appendingPathComponent(name)
            let payload = try XCTUnwrap(manifest[name])
            if isCorrupt(payload) {
                XCTAssertThrowsError(try ZipArchiveReader.list(url: url), name) { error in
                    XCTAssertEqual(
                        error as? PreviewFailure,
                        .archiveUnreadable,
                        "\(name): corrupt fixture should map to archiveUnreadable"
                    )
                }
                continue
            }
            let expected = try expectedListing(name: name, payload: payload)
            let listing = try ZipArchiveReader.list(url: url)
            assertListing(name: name, listing: listing, expected: expected)
        }
    }

    func test_largeManifestMatchesReaderWhenPresent() throws {
        let requireLarge = ProcessInfo.processInfo.environment["TAPEEK_REQUIRE_LARGE"] == "1"
        let manifestURL = TestPaths.largeManifest
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            if requireLarge {
                XCTFail("large manifest is required but missing: \(manifestURL.path)")
                return
            }
            throw XCTSkip("large manifest not generated; run scripts/make-fixtures.py")
        }
        let manifest = try loadManifest(manifestURL)
        var checked = 0
        for name in manifest.keys.sorted() {
            let url = TestPaths.buildFixtures.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                if requireLarge {
                    XCTFail("required large sample is missing: \(url.path)")
                } else {
                    print("skip performance sample not generated: \(name)")
                }
                continue
            }
            let payload = try XCTUnwrap(manifest[name])
            if isCorrupt(payload) {
                XCTAssertThrowsError(try ZipArchiveReader.list(url: url), name)
                continue
            }
            let expected = try expectedLargeListing(name: name, payload: payload)
            let listing = try ZipArchiveReader.list(url: url)
            assertListing(name: name, listing: listing, expected: expected)
            if let isTruncated = expected.isTruncated {
                XCTAssertEqual(
                    listing.isTruncated,
                    isTruncated,
                    "\(name): isTruncated expected \(isTruncated), actual \(listing.isTruncated)"
                )
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "large manifest exists but no generated sample was checked")
    }

    private func expectedListing(name: String, payload: [String: Any]) throws -> ExpectedListing {
        guard let rawNames = payload["names"] as? [String] else {
            XCTFail("\(name): manifest is missing a string names array")
            throw ManifestError.invalidFormat
        }
        let total = intValue(payload["totalEntries"]) ?? intValue(payload["entryCount"])
        let encrypted = boolValue(payload["hasEncryptedEntries"]) ?? false
        let facts = normalize(rawNames)
        let override = overrides[name]
        return ExpectedListing(
            totalEntries: total,
            fileCount: override?.fileCount ?? facts.fileCount,
            directoryCount: override?.directoryCount ?? facts.directoryCount,
            totalUncompressedBytes: override?.totalUncompressedBytes ?? uint64Value(payload["totalUncompressedBytes"]) ?? 0,
            hasEncryptedEntries: encrypted,
            names: (override?.names ?? facts.names).sorted(),
            isTruncated: nil
        )
    }

    private func expectedLargeListing(name: String, payload: [String: Any]) throws -> ExpectedListing {
        guard let rawNames = payload["names"] as? [String],
              let fileCount = intValue(payload["fileCount"]),
              let directoryCount = intValue(payload["directoryCount"]) else {
            XCTFail("\(name): large manifest is missing required fields")
            throw ManifestError.invalidFormat
        }
        return ExpectedListing(
            totalEntries: intValue(payload["totalEntries"]),
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalUncompressedBytes: uint64Value(payload["totalUncompressedBytes"]) ?? 0,
            hasEncryptedEntries: boolValue(payload["hasEncryptedEntries"]) ?? false,
            names: normalize(rawNames).names,
            isTruncated: boolValue(payload["isTruncated"])
        )
    }

    private func assertListing(name: String, listing: ZipListing, expected: ExpectedListing) {
        if let totalEntries = expected.totalEntries {
            XCTAssertEqual(
                listing.totalEntryCount,
                Int?(totalEntries),
                "\(name): totalEntryCount expected \(totalEntries), actual \(String(describing: listing.totalEntryCount))"
            )
        }
        XCTAssertEqual(
            listing.fileCount,
            expected.fileCount,
            "\(name): fileCount expected \(expected.fileCount), actual \(listing.fileCount)"
        )
        XCTAssertEqual(
            listing.directoryCount,
            expected.directoryCount,
            "\(name): directoryCount expected \(expected.directoryCount), actual \(listing.directoryCount)"
        )
        XCTAssertEqual(
            listing.totalUncompressedBytes,
            expected.totalUncompressedBytes,
            "\(name): totalUncompressedBytes expected \(expected.totalUncompressedBytes), actual \(listing.totalUncompressedBytes)"
        )
        XCTAssertEqual(
            listing.hasEncryptedEntries,
            expected.hasEncryptedEntries,
            "\(name): hasEncryptedEntries expected \(expected.hasEncryptedEntries), actual \(listing.hasEncryptedEntries)"
        )

        let actualNames = listing.entries.map(\.path).sorted()
        let expectedNames = expected.names.sorted()
        if actualNames != expectedNames {
            let expectedSet = Set(expectedNames)
            let actualSet = Set(actualNames)
            let missing = expectedSet.subtracting(actualSet).sorted()
            let extra = actualSet.subtracting(expectedSet).sorted()
            XCTFail(
                "\(name): names differ; missing=\(missing.prefix(5)) (\(missing.count)), "
                    + "extra=\(extra.prefix(5)) (\(extra.count))"
            )
        }
    }

    /// Mirrors the documented path normalization used by ZipArchiveReader without
    /// calling into it: NFC, backslashes, leading slash, ".", "..", trailing slash,
    /// and first-occurrence duplicate wins.
    private func normalize(_ rawNames: [String]) -> NameFacts {
        var seen = Set<String>()
        var names: [String] = []
        var fileCount = 0
        var directoryCount = 0
        for raw in rawNames {
            let slashed = raw
                .replacingOccurrences(of: "\\", with: "/")
                .precomposedStringWithCanonicalMapping
            let isDirectory = slashed.hasSuffix("/")
            let withoutLeading = String(slashed.drop(while: { $0 == "/" }))
            var parts = withoutLeading
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            parts.removeAll { $0 == "." }
            guard !parts.contains(".."), !parts.isEmpty else { continue }
            let path = parts.joined(separator: "/")
            guard seen.insert(path).inserted else { continue }
            names.append(path)
            if isDirectory {
                directoryCount += 1
            } else {
                fileCount += 1
            }
        }
        return NameFacts(names: names.sorted(), fileCount: fileCount, directoryCount: directoryCount)
    }

    private func loadManifest(_ url: URL) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let manifest = object as? [String: [String: Any]] else {
            XCTFail("\(url.path): expected a JSON object of fixture objects")
            throw ManifestError.invalidFormat
        }
        return manifest
    }

    private func isCorrupt(_ payload: [String: Any]) -> Bool {
        boolValue(payload["corrupt"]) ?? false
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private func uint64Value(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        return value as? UInt64
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }
}
