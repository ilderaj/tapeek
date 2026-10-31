import Foundation

public enum MarkdownLoader {
    public static func load(
        url: URL,
        limits: PreviewLimits = .default
    ) throws -> MarkdownDocument {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw PreviewFailure.unreadableFile
        }
        guard let size = attributes[.size] as? NSNumber else {
            throw PreviewFailure.unreadableFile
        }
        let reportedSize = size.intValue
        guard reportedSize <= limits.maxMarkdownBytes else {
            throw PreviewFailure.fileTooLarge(actualBytes: reportedSize, limitBytes: limits.maxMarkdownBytes)
        }

        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: limits.maxMarkdownBytes + 1) ?? Data()
        } catch {
            throw PreviewFailure.unreadableFile
        }
        guard data.count <= limits.maxMarkdownBytes else {
            throw PreviewFailure.fileTooLarge(actualBytes: data.count, limitBytes: limits.maxMarkdownBytes)
        }
        return try load(data: data, baseURL: url.deletingLastPathComponent(), limits: limits)
    }

    public static func load(
        data: Data,
        baseURL: URL,
        limits: PreviewLimits = .default
    ) throws -> MarkdownDocument {
        guard data.count <= limits.maxMarkdownBytes else {
            throw PreviewFailure.fileTooLarge(actualBytes: data.count, limitBytes: limits.maxMarkdownBytes)
        }
        let (text, encoding) = try decode(data)
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw PreviewFailure.unsupportedTextEncoding
        }
        let frontMatter = FrontMatter.parse(text)
        return MarkdownDocument(
            body: frontMatter.body,
            frontMatter: frontMatter.entries,
            byteCount: data.count,
            encoding: encoding,
            baseURL: baseURL
        )
    }

    private static func decode(_ data: Data) throws -> (String, MarkdownTextEncoding) {
        if data.isEmpty { return ("", .utf8) }
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw PreviewFailure.unsupportedTextEncoding
            }
            return (text, .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw PreviewFailure.unsupportedTextEncoding
            }
            return (text, .utf16LittleEndian)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw PreviewFailure.unsupportedTextEncoding
            }
            return (text, .utf16BigEndian)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PreviewFailure.unsupportedTextEncoding
        }
        return (text, .utf8)
    }
}
