import Foundation
import XCTest
@testable import TapeekCore

final class ZipTreeTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testTypicalAndExplicitEmptyDirectoriesAndStableSort() throws {
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("typical.zip"))
        let tree = ZipTree(listing: listing, archiveName: "archive.zip")
        XCTAssertEqual(tree.root.name, "archive")
        XCTAssertEqual(tree.fileCount, 3)
        XCTAssertTrue(tree.root.children.contains { $0.kind == .directory })
        XCTAssertTrue(tree.root.children.flatMap(\.children).contains { $0.name == "readme.txt" })
        let sortListing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("sort.zip"))
        let sortTree = ZipTree(listing: sortListing, archiveName: "sort.zip")
        XCTAssertEqual(sortTree.root.children.map(\.name), ["a", "b", "a.txt", "z.txt"])
    }

    func testMissingParentsAreSynthesizedAndCounted() throws {
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("missing-dirs.zip"))
        let tree = ZipTree(listing: listing, archiveName: "missing-dirs.zip")
        XCTAssertEqual(listing.directoryCount, 0)
        XCTAssertEqual(tree.directoryCount, 2)
        XCTAssertEqual(tree.root.children[0].children[0].children[0].path, "a/b/c.txt")
    }

    func testExplicitEmptyDirectoriesRemainVisible() throws {
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("empty-dirs.zip"))
        let tree = ZipTree(listing: listing, archiveName: "empty-dirs.zip")
        XCTAssertEqual(tree.fileCount, 0)
        XCTAssertEqual(tree.directoryCount, 3)
        let rows = tree.rows(expanded: tree.defaultExpandedIDs())
        XCTAssertTrue(rows.contains { $0.node.path == "empty" && $0.node.children.isEmpty })
        XCTAssertTrue(rows.contains { $0.node.path == "nested/empty" })
    }

    func testLongDepthAndEmptyListing() throws {
        let path = (0..<200).map { "d\($0)" }.joined(separator: "/") + "/leaf.txt"
        let entry = ZipEntry(id: path, path: path, name: "leaf.txt", kind: .file, uncompressedSize: 1, modificationDate: nil, isEncrypted: false)
        let listing = ZipListing(entries: [entry], shownEntryCount: 1, totalEntryCount: 1, skippedEntryCount: 0, isTruncated: false, fileCount: 1, directoryCount: 0, totalUncompressedBytes: 1, archiveBytes: 0, hasEncryptedEntries: false, warnings: [])
        let tree = ZipTree(listing: listing, archiveName: "deep.zip")
        let rows = tree.rows(expanded: Set((0..<200).map { (0...$0).map { "d\($0)" }.joined(separator: "/") }))
        XCTAssertEqual(rows.last?.depth, 200)
        let empty = ZipTree(listing: ZipListing(entries: [], shownEntryCount: 0, totalEntryCount: 0, skippedEntryCount: 0, isTruncated: false, fileCount: 0, directoryCount: 0, totalUncompressedBytes: 0, archiveBytes: 0, hasEncryptedEntries: false, warnings: []), archiveName: "empty.zip")
        XCTAssertTrue(empty.rows(expanded: []).isEmpty)
    }
}
