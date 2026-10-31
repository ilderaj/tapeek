import XCTest
@testable import TapeekCore

final class ByteReaderTests: XCTestCase {
    func testReadsLittleEndianIntegers() throws {
        let reader = ByteReader(data: Data([0x34, 0x12, 0x78, 0x56, 0x34, 0x12, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]))

        XCTAssertEqual(try reader.readUInt16LE(at: 0), 0x1234)
        XCTAssertEqual(try reader.readUInt32LE(at: 2), 0x12345678)
        XCTAssertEqual(try reader.readUInt64LE(at: 6), 0x0123456789ABCDEF)
    }

    func testReadsAtLastValidOffset() throws {
        let reader = ByteReader(data: Data([0xAA, 0xBB]))
        XCTAssertEqual(try reader.readUInt16LE(at: 0), 0xBBAA)
    }

    func testOutOfBoundsThrows() {
        let reader = ByteReader(data: Data([0x01, 0x02, 0x03]))

        XCTAssertThrowsError(try reader.readUInt32LE(at: 0)) { error in
            XCTAssertEqual(
                error as? ByteReaderError,
                .outOfBounds(offset: 0, count: 4, available: 3)
            )
        }
        XCTAssertThrowsError(try reader.readUInt16LE(at: -1))
        XCTAssertThrowsError(try reader.readUInt16LE(at: 2))
        XCTAssertThrowsError(try reader.readBytes(at: 0, count: -1))
    }

    func testReadBytesReturnsCopy() throws {
        let reader = ByteReader(data: Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(try reader.readBytes(at: 1, count: 2), Data([0x02, 0x03]))
        XCTAssertEqual(try reader.readBytes(at: 3, count: 0), Data())
    }
}
