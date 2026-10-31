import Foundation

enum ByteReaderError: Error, Equatable {
    case outOfBounds(offset: Int, count: Int, available: Int)
}

struct ByteReader {
    let data: Data

    func readUInt16LE(at offset: Int) throws -> UInt16 {
        let bytes = try readBytes(at: offset, count: 2)
        return UInt16(bytes[bytes.startIndex])
            | (UInt16(bytes[bytes.startIndex + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) throws -> UInt32 {
        let bytes = try readBytes(at: offset, count: 4)
        return UInt32(bytes[bytes.startIndex])
            | (UInt32(bytes[bytes.startIndex + 1]) << 8)
            | (UInt32(bytes[bytes.startIndex + 2]) << 16)
            | (UInt32(bytes[bytes.startIndex + 3]) << 24)
    }

    func readUInt64LE(at offset: Int) throws -> UInt64 {
        let bytes = try readBytes(at: offset, count: 8)
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[bytes.startIndex + index]) << UInt64(index * 8)
        }
        return value
    }

    func readBytes(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw ByteReaderError.outOfBounds(offset: offset, count: count, available: data.count)
        }
        let start = data.startIndex + offset
        let end = start + count
        return Data(data[start..<end])
    }
}
