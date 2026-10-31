import Foundation
import XCTest
@testable import TapeekCore

final class MarkdownLoaderTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func test_load_utf8_returnsBodyEncodingAndByteCount() throws {
        let data = Data("# 标题\nBody".utf8)
        let document = try MarkdownLoader.load(data: data, baseURL: baseURL)
        XCTAssertEqual(document.body, "# 标题\nBody")
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertEqual(document.byteCount, data.count)
        XCTAssertEqual(document.baseURL, baseURL)
    }

    func test_load_utf8BOM_removesBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("# 中文标题".utf8))
        let document = try MarkdownLoader.load(data: data, baseURL: baseURL)
        XCTAssertEqual(document.body, "# 中文标题")
        XCTAssertEqual(document.encoding, .utf8)
    }

    func test_load_utf16BOM_decodesBothByteOrders() throws {
        let expected = "中文正文"
        let littleEndian = encodedUTF16(expected, littleEndian: true)
        let bigEndian = encodedUTF16(expected, littleEndian: false)
        let littleDocument = try MarkdownLoader.load(data: littleEndian, baseURL: baseURL)
        let bigDocument = try MarkdownLoader.load(data: bigEndian, baseURL: baseURL)
        XCTAssertEqual(littleDocument.body, expected)
        XCTAssertEqual(littleDocument.encoding, .utf16LittleEndian)
        XCTAssertEqual(bigDocument.body, expected)
        XCTAssertEqual(bigDocument.encoding, .utf16BigEndian)
    }

    func test_load_invalidUTF8_throwsUnsupportedTextEncoding() {
        XCTAssertThrowsError(try MarkdownLoader.load(data: Data([0x61, 0x80]), baseURL: baseURL)) { error in
            XCTAssertEqual(error as? PreviewFailure, .unsupportedTextEncoding)
        }
    }

    func test_load_nulByte_throwsUnsupportedTextEncoding() {
        XCTAssertThrowsError(try MarkdownLoader.load(data: Data([0x61, 0x00, 0x62]), baseURL: baseURL)) { error in
            XCTAssertEqual(error as? PreviewFailure, .unsupportedTextEncoding)
        }
    }

    func test_load_emptyData_returnsEmptyUTF8Document() throws {
        let document = try MarkdownLoader.load(data: Data(), baseURL: baseURL)
        XCTAssertEqual(document.body, "")
        XCTAssertEqual(document.encoding, .utf8)
    }

    func test_load_atLimit_succeeds() throws {
        let limits = PreviewLimits(maxMarkdownBytes: 4)
        let document = try MarkdownLoader.load(data: Data("1234".utf8), baseURL: baseURL, limits: limits)
        XCTAssertEqual(document.body, "1234")
    }

    func test_load_overLimit_throwsExactFileTooLargeFailure() {
        let limits = PreviewLimits(maxMarkdownBytes: 4)
        XCTAssertThrowsError(try MarkdownLoader.load(data: Data("12345".utf8), baseURL: baseURL, limits: limits)) { error in
            XCTAssertEqual(error as? PreviewFailure, .fileTooLarge(actualBytes: 5, limitBytes: 4))
        }
    }

    func test_load_missingFile_throwsUnreadableFile() {
        let url = URL(fileURLWithPath: "/tmp/tapeek-markdown-loader-file-that-does-not-exist.md")
        XCTAssertThrowsError(try MarkdownLoader.load(url: url)) { error in
            XCTAssertEqual(error as? PreviewFailure, .unreadableFile)
        }
    }

    private func encodedUTF16(_ string: String, littleEndian: Bool) -> Data {
        var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
        for unit in string.utf16 {
            let first = UInt8((unit >> 8) & 0xFF)
            let second = UInt8(unit & 0xFF)
            data.append(contentsOf: littleEndian ? [second, first] : [first, second])
        }
        return data
    }
}
