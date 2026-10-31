import CoreFoundation
import Foundation

public enum ZipArchiveReader {
    private struct DirectoryInfo {
        let end: UInt64
        let count: UInt64
        let size: UInt64
        let offset: UInt64
        let zip64: Bool
    }

    public static func list(url: URL, limits: PreviewLimits = .default) throws -> ZipListing {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw PreviewFailure.unreadableFile }
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw PreviewFailure.archiveUnreadable }
        let started = Date()
        let tailLength = Int(min(fileSize, 22 + 65_535))
        try handle.seek(toOffset: fileSize - UInt64(tailLength))
        let tail = try handle.read(upToCount: tailLength) ?? Data()
        guard let directoryInfo = try findDirectory(tail: tail, absoluteStart: fileSize - UInt64(tailLength), fileSize: fileSize) else { throw PreviewFailure.archiveUnreadable }
        let info = directoryInfo.1
        let directoryEnd = info.end
        let (start, overflow1) = directoryEnd.subtractingReportingOverflow(info.size)
        let (archiveStart, overflow2) = start.subtractingReportingOverflow(info.offset)
        if info.zip64 && !overflow1 && !overflow2 && archiveStart > 0 { throw PreviewFailure.archiveUnsupported(message: "自解压 ZIP64 暂不支持") }
        guard !overflow1, !overflow2, archiveStart <= info.end else {
            if info.zip64 { throw PreviewFailure.archiveUnsupported(message: "自解压 ZIP64 暂不支持") }
            throw PreviewFailure.archiveUnreadable
        }
        guard info.size <= fileSize, info.offset <= UInt64.max - archiveStart else { throw PreviewFailure.archiveUnreadable }
        let cdStart = archiveStart + info.offset
        let readLengthU = min(info.size, UInt64(limits.maxZipCentralDirectoryBytes))
        guard cdStart <= fileSize, readLengthU <= fileSize - cdStart, readLengthU <= UInt64(Int.max) else { throw PreviewFailure.archiveUnreadable }
        try handle.seek(toOffset: cdStart)
        let directory = try handle.read(upToCount: Int(readLengthU)) ?? Data()
        let reader = ByteReader(data: directory)
        var cursor = 0
        var entries: [ZipEntry] = []
        var seen: [String: ZipEntryKind] = [:]
        var warnings: [ZipWarning] = []
        var skipped = 0
        var truncated = readLengthU < info.size
        var timedOut = false
        var malformedStopped = false
        var sawInvalidUTF8 = false
        var sawGuessedEncoding = false
        let total = info.count <= UInt64(Int.max) ? Int(info.count) : nil
        let targetCount = min(info.count, UInt64(limits.maxZipEntries))

        var parsedCount: UInt64 = 0
        while parsedCount < targetCount, UInt64(cursor) < readLengthU {
            if Date().timeIntervalSince(started) > limits.maxZipListingDuration { timedOut = true; break }
            guard cursor <= directory.count, directory.count - cursor >= 46 else { truncated = true; break }
            let entryOffset = cursor
            guard try reader.readUInt32LE(at: cursor) == 0x02014B50 else {
                if parsedCount == 0 { throw PreviewFailure.archiveUnreadable }
                warnings.append(.malformedEntry(offset: entryOffset)); malformedStopped = true; break
            }
            let flags = try reader.readUInt16LE(at: cursor + 8)
            let dosTime = try reader.readUInt16LE(at: cursor + 12)
            let dosDate = try reader.readUInt16LE(at: cursor + 14)
            let size32 = try reader.readUInt32LE(at: cursor + 24)
            let nameLength = Int(try reader.readUInt16LE(at: cursor + 28))
            let extraLength = Int(try reader.readUInt16LE(at: cursor + 30))
            let commentLength = Int(try reader.readUInt16LE(at: cursor + 32))
            let disk16 = try reader.readUInt16LE(at: cursor + 34)
            let compressed32 = try reader.readUInt32LE(at: cursor + 20)
            let offset32 = try reader.readUInt32LE(at: cursor + 42)
            let external = try reader.readUInt32LE(at: cursor + 38)
            let componentLength = nameLength.addingReportingOverflow(extraLength)
            guard !componentLength.overflow else { truncated = true; break }
            let allLength = componentLength.partialValue.addingReportingOverflow(commentLength)
            guard !allLength.overflow, allLength.partialValue <= directory.count - cursor - 46 else { truncated = true; break }
            let nameStart = cursor + 46
            let rawName = try reader.readBytes(at: nameStart, count: nameLength)
            let extra = try reader.readBytes(at: nameStart + nameLength, count: extraLength)
            let next = cursor + 46 + allLength.partialValue
            cursor = next
            parsedCount += 1
            guard nameLength > 0 else { skipped += 1; warnings.append(.unsafePath("空文件名")); continue }
            var size = UInt64(size32)
            var entryDisk = UInt32(disk16)
            if size32 == UInt32.max || compressed32 == UInt32.max || offset32 == UInt32.max || disk16 == UInt16.max {
                guard let expanded = try zip64Values(extra, needUncompressed: size32 == UInt32.max, needCompressed: compressed32 == UInt32.max, needOffset: offset32 == UInt32.max, needDisk: disk16 == UInt16.max), (size32 != UInt32.max || expanded.uncompressed != nil), (compressed32 != UInt32.max || expanded.compressed != nil), (offset32 != UInt32.max || expanded.offset != nil), (disk16 != UInt16.max || expanded.disk != nil) else {
                    skipped += 1; warnings.append(.malformedEntry(offset: entryOffset)); continue
                }
                size = expanded.uncompressed ?? size
                entryDisk = expanded.disk ?? UInt32(disk16)
                guard entryDisk == 0 else { throw PreviewFailure.archiveUnsupported(message: "分卷压缩包") }
            }
            guard entryDisk == 0 else { throw PreviewFailure.archiveUnsupported(message: "分卷压缩包") }
            let decoded = decodeName(rawName, utf8Flag: flags & (1 << 11) != 0)
            if decoded.invalidUTF8 { sawInvalidUTF8 = true }
            if decoded.guessed { sawGuessedEncoding = true }
            guard let (path, trailingDirectory) = normalize(decoded.value, directory: decoded.value.replacingOccurrences(of: "\\", with: "/").hasSuffix("/"), limit: limits) else {
                skipped += 1; warnings.append(.unsafePath(decoded.value)); continue
            }
            let unixMode = (external >> 16) & 0xF000
            let kind: ZipEntryKind = trailingDirectory || unixMode == 0x4000 ? .directory : (unixMode == 0xA000 ? .symlink : .file)
            let existing = seen[path]
            if let existing {
                warnings.append(.duplicatePath(path)); skipped += 1
                if existing != .directory && kind == .directory {
                    if let index = entries.firstIndex(where: { $0.path == path }) { entries.remove(at: index) }
                    seen[path] = kind
                } else { continue }
            } else { seen[path] = kind }
            let name = path.split(separator: "/").last.map(String.init) ?? path
            let encrypted = flags & 1 != 0
            entries.append(ZipEntry(id: path, path: path, name: name, kind: kind, uncompressedSize: size, modificationDate: dosDateTime(date: dosDate, time: dosTime), isEncrypted: encrypted))
        }
        if sawInvalidUTF8 { warnings.append(.invalidUTF8Name) }
        if sawGuessedEncoding { warnings.append(.guessedLegacyEncoding) }
        if parsedCount < targetCount && !timedOut && !truncated && !malformedStopped { truncated = true }
        if info.count > UInt64(limits.maxZipEntries) { truncated = true }
        let encryptedCount = entries.filter(\.isEncrypted).count
        if encryptedCount > 0 { warnings.append(.encryptedEntries(count: encryptedCount)) }
        if timedOut { warnings.append(.timedOut(shown: entries.count, total: total)) }
        if truncated { warnings.append(.truncated(shown: entries.count, total: total)) }
        let files = entries.filter { $0.kind != .directory }
        return ZipListing(entries: entries, shownEntryCount: entries.count, totalEntryCount: total, skippedEntryCount: skipped, isTruncated: truncated || timedOut, fileCount: files.count, directoryCount: entries.count - files.count, totalUncompressedBytes: files.reduce(UInt64(0)) { saturatingAdd($0, $1.uncompressedSize) }, archiveBytes: fileSize, hasEncryptedEntries: encryptedCount > 0, warnings: warnings)
    }

    private static func findDirectory(tail: Data, absoluteStart: UInt64, fileSize: UInt64) throws -> (UInt64, DirectoryInfo)? {
        guard tail.count >= 22 else { return nil }
        let reader = ByteReader(data: tail)
        var candidates: [(Int, UInt16)] = []
        for pos in stride(from: tail.count - 22, through: 0, by: -1) {
            guard try reader.readUInt32LE(at: pos) == 0x06054B50 else { continue }
            let comment = try reader.readUInt16LE(at: pos + 20)
            let end = UInt64(pos) + 22 + UInt64(comment)
            if end <= UInt64(tail.count) { candidates.append((pos, comment)) }
        }
        guard let candidate = candidates.first(where: { UInt64($0.0) + 22 + UInt64($0.1) == UInt64(tail.count) }) ?? candidates.first else { return nil }
        let pos = candidate.0
        let absEOCD = absoluteStart + UInt64(pos)
        let disk = try reader.readUInt16LE(at: pos + 4)
        let cdDisk = try reader.readUInt16LE(at: pos + 6)
        guard disk == 0, cdDisk == 0 else { throw PreviewFailure.archiveUnsupported(message: "分卷压缩包") }
        let count = UInt64(try reader.readUInt16LE(at: pos + 10))
        let size = UInt64(try reader.readUInt32LE(at: pos + 12))
        let offset = UInt64(try reader.readUInt32LE(at: pos + 16))
        let locatorPos = pos >= 20 ? pos - 20 : -1
        let hasLocator: Bool
        if locatorPos >= 0 { hasLocator = try reader.readUInt32LE(at: locatorPos) == 0x07064B50 } else { hasLocator = false }
        let needs64 = count == 0xFFFF || size == UInt32.max || offset == UInt32.max || hasLocator
        if needs64 {
            guard hasLocator else { throw PreviewFailure.archiveUnreadable }
            let locatorDisk = try reader.readUInt32LE(at: locatorPos + 4)
            let recordOffset = try reader.readUInt64LE(at: locatorPos + 8)
            let disks = try reader.readUInt32LE(at: locatorPos + 16)
            guard locatorDisk == 0, disks == 1 else { throw PreviewFailure.archiveUnsupported(message: "分卷压缩包") }
            guard recordOffset <= fileSize - min(fileSize, 56) else { throw PreviewFailure.archiveUnreadable }
            // The locator offset is absolute. A shifted record indicates a prefixed ZIP64 archive.
            let zip64TailOffset = absoluteStart + UInt64(locatorPos)
            guard zip64TailOffset >= 56 else { throw PreviewFailure.archiveUnreadable }
            guard recordOffset >= absoluteStart, recordOffset - absoluteStart <= UInt64(Int.max) else { throw PreviewFailure.archiveUnreadable }
            let recordPos = Int(recordOffset - absoluteStart)
            guard recordPos <= tail.count - 56 else { throw PreviewFailure.archiveUnreadable }
            if try reader.readUInt32LE(at: recordPos) != 0x06064B50 {
                var scan = recordPos
                var foundShiftedRecord = false
                while scan <= locatorPos - 4 {
                    if try reader.readUInt32LE(at: scan) == 0x06064B50 { foundShiftedRecord = true; break }
                    scan += 1
                }
                if foundShiftedRecord { throw PreviewFailure.archiveUnsupported(message: "自解压 ZIP64 暂不支持") }
                throw PreviewFailure.archiveUnreadable
            }
            let recordSize = try reader.readUInt64LE(at: recordPos + 4)
            guard recordSize >= 44, recordSize <= UInt64(tail.count - recordPos - 12) else { throw PreviewFailure.archiveUnreadable }
            let zDisk = try reader.readUInt32LE(at: recordPos + 16)
            let zCDDisk = try reader.readUInt32LE(at: recordPos + 20)
            guard zDisk == 0, zCDDisk == 0 else { throw PreviewFailure.archiveUnsupported(message: "分卷压缩包") }
            let zipEnd = UInt64(recordPos) + UInt64(12) + recordSize
            guard absoluteStart + zipEnd == zip64TailOffset else { throw PreviewFailure.archiveUnsupported(message: "自解压 ZIP64 暂不支持") }
            return (absEOCD, DirectoryInfo(end: recordOffset, count: try reader.readUInt64LE(at: recordPos + 32), size: try reader.readUInt64LE(at: recordPos + 40), offset: try reader.readUInt64LE(at: recordPos + 48), zip64: true))
        }
        return (absEOCD, DirectoryInfo(end: absEOCD, count: count, size: size, offset: offset, zip64: false))
    }

    private struct ZIP64Values { var uncompressed: UInt64?; var compressed: UInt64?; var offset: UInt64?; var disk: UInt32? }
    private static func zip64Values(_ extra: Data, needUncompressed: Bool, needCompressed: Bool, needOffset: Bool, needDisk: Bool) throws -> ZIP64Values? {
        let reader = ByteReader(data: extra); var cursor = 0
        while cursor + 4 <= extra.count {
            let id = try reader.readUInt16LE(at: cursor), length = Int(try reader.readUInt16LE(at: cursor + 2)); cursor += 4
            guard length <= extra.count - cursor else { return nil }
            if id == 1 {
                let data = try reader.readBytes(at: cursor, count: length); let r = ByteReader(data: data); var i = 0; var values = ZIP64Values()
                func read64(_ needed: Bool) throws -> UInt64? { guard needed else { return nil }; defer { i += 8 }; guard i <= data.count - 8 else { return nil }; return try r.readUInt64LE(at: i) }
                values.uncompressed = try read64(needUncompressed); values.compressed = try read64(needCompressed); values.offset = try read64(needOffset)
                if needDisk { guard i <= data.count - 4 else { return nil }; values.disk = try r.readUInt32LE(at: i) }
                return values
            }
            cursor += length
        }
        return nil
    }

    private static func decodeName(_ data: Data, utf8Flag: Bool) -> (value: String, invalidUTF8: Bool, guessed: Bool) {
        if let text = String(data: data, encoding: .utf8) { return (text.precomposedStringWithCanonicalMapping, false, false) }
        if utf8Flag { return (String(decoding: data, as: UTF8.self).precomposedStringWithCanonicalMapping, true, false) }
        let cf = CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        let cp = String(data: data, encoding: String.Encoding(rawValue: ns)) ?? String(decoding: data, as: UTF8.self)
        let gb18030Encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)))
        if let gb = String(data: data, encoding: gb18030Encoding), countLikelyMojibake(cp) >= 2, countCJK(gb) >= 2, !gb.contains("�") { return (gb.precomposedStringWithCanonicalMapping, false, true) }
        return (cp.precomposedStringWithCanonicalMapping, false, false)
    }
    private static func countLikelyMojibake(_ string: String) -> Int { string.unicodeScalars.filter { (0x00A0...0x00FF).contains(Int($0.value)) || (0x2500...0x257F).contains(Int($0.value)) }.count }
    private static func countCJK(_ string: String) -> Int { string.unicodeScalars.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count }

    private static func normalize(_ raw: String, directory: Bool, limit: PreviewLimits) -> (String, Bool)? {
        guard !raw.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        
        let slashed = raw.replacingOccurrences(of: "\\", with: "/").precomposedStringWithCanonicalMapping
        let wasDirectory = directory || slashed.hasSuffix("/")
        let replaced = String(slashed.drop(while: { $0 == "/" }))
        var parts = replaced.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        parts.removeAll { $0 == "." }
        guard !parts.contains(".."), !parts.isEmpty else { return nil }
        let path = parts.joined(separator: "/")
        guard path.utf8.count <= limit.maxZipPathBytes, parts.count <= limit.maxZipPathDepth else { return nil }
        return (path, wasDirectory)
    }
    private static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        var c = DateComponents(); c.year = 1980 + Int((date >> 9) & 0x7F); c.month = Int((date >> 5) & 0x0F); c.day = Int(date & 0x1F); c.hour = Int((time >> 11) & 0x1F); c.minute = Int((time >> 5) & 0x3F); c.second = Int(time & 0x1F) * 2; c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)
    }
    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 { let (sum, overflow) = lhs.addingReportingOverflow(rhs); return overflow ? UInt64.max : sum }
}
