import XCTest
@testable import TapeekCore

final class PreviewLimitsTests: XCTestCase {
    func testDefaults_matchSpecification() {
        let limits = PreviewLimits.default

        XCTAssertEqual(limits.maxMarkdownBytes, 2 * 1024 * 1024)
        XCTAssertEqual(limits.maxZipEntries, 20_000)
        XCTAssertEqual(limits.maxZipPathBytes, 4_096)
        XCTAssertEqual(limits.maxZipPathDepth, 256)
        XCTAssertEqual(limits.maxZipCentralDirectoryBytes, 16 * 1024 * 1024)
        XCTAssertEqual(limits.maxZipListingDuration, 2.0)
        XCTAssertEqual(limits.maxImageBytes, 20 * 1024 * 1024)
        XCTAssertEqual(limits.maxImagePixelSize, 4_096)
        XCTAssertTrue(limits.isValid)
    }

    func testCustomLimits_areValid() {
        let limits = PreviewLimits(
            maxMarkdownBytes: 1,
            maxZipEntries: 2,
            maxZipPathBytes: 3,
            maxZipPathDepth: 4,
            maxZipCentralDirectoryBytes: 5,
            maxZipListingDuration: 6,
            maxImageBytes: 7,
            maxImagePixelSize: 8
        )

        XCTAssertTrue(limits.isValid)
        XCTAssertEqual(limits.maxZipPathDepth, 4)
    }
}
