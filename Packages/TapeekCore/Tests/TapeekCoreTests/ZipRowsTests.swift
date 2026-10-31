import Foundation
import XCTest
@testable import TapeekCore

final class ZipRowsTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Samples/zip") }

    func testRowsExpandCollapseDepthAndStableOrder() throws {
        let listing = try ZipArchiveReader.list(url: fixtures.appendingPathComponent("missing-dirs.zip"))
        let tree = ZipTree(listing: listing, archiveName: "x.zip")
        XCTAssertEqual(tree.rows(expanded: []).map(\.depth), [0])
        let expanded = tree.rows(expanded: ["a", "a/b"])
        XCTAssertEqual(expanded.map(\.depth), [0, 1, 2])
        XCTAssertEqual(expanded, tree.rows(expanded: ["a", "a/b"]))
    }

    func testDefaultExpansionForOrdinaryAndSingleRootArchives() throws {
        let ordinary = ZipTree(listing: try ZipArchiveReader.list(url: fixtures.appendingPathComponent("typical.zip")), archiveName: "typical.zip")
        XCTAssertEqual(ordinary.defaultExpandedIDs(), Set(["docs", "src", "空目录"]))
        let single = ZipTree(listing: try ZipArchiveReader.list(url: fixtures.appendingPathComponent("single-root.zip")), archiveName: "single-root.zip")
        XCTAssertEqual(single.defaultExpandedIDs(), ["Project", "Project/docs"])
        XCTAssertEqual(single.rows(expanded: single.defaultExpandedIDs()).map(\.depth), [0, 1, 2, 1])
    }
}
