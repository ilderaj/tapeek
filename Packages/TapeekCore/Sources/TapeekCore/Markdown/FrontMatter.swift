import Foundation

struct FrontMatterResult {
    let entries: [FrontMatterEntry]
    let body: String
}

enum FrontMatter {
    private static let scanLimit = 8 * 1024
    private static let maximumEntries = 20
    private static let maximumValueLength = 512

    static func parse(_ text: String) -> FrontMatterResult {
        let utf8 = text.utf8
        guard let firstNewlineIndex = utf8.firstIndex(of: 0x0A) else { return unchanged(text) }
        let firstLine = String(decoding: utf8[..<firstNewlineIndex], as: UTF8.self)
        guard normalizedLine(firstLine) == "---" else { return unchanged(text) }

        var lineStartOffset = utf8.distance(from: utf8.startIndex, to: firstNewlineIndex) + 1
        var parsedEntries: [FrontMatterEntry] = []
        var seenKeys = Set<String>()
        var closingBodyOffset: Int?
        var hasContentLine = false

        while lineStartOffset <= utf8.count {
            let lineStartUTF8 = utf8.index(utf8.startIndex, offsetBy: lineStartOffset)
            let newlineIndex = utf8[lineStartUTF8...].firstIndex(of: 0x0A)
            let hasNewline = newlineIndex != nil
            let lineEndUTF8 = newlineIndex ?? utf8.endIndex
            let lineEndOffset = utf8.distance(from: utf8.startIndex, to: lineEndUTF8)
            let endOffset = lineEndOffset + (hasNewline ? 1 : 0)
            guard endOffset <= scanLimit else { break }

            let line = String(decoding: utf8[lineStartUTF8..<lineEndUTF8], as: UTF8.self)
            let normalized = normalizedLine(line)
            if normalized == "---" || normalized == "..." {
                guard hasContentLine else { return unchanged(text) }
                closingBodyOffset = endOffset
                break
            }

            hasContentLine = true
            if let entry = parseEntry(line), seenKeys.insert(entry.key).inserted,
               parsedEntries.count < maximumEntries {
                parsedEntries.append(entry)
            }

            guard hasNewline else { break }
            lineStartOffset = endOffset
        }

        guard let bodyOffset = closingBodyOffset else { return unchanged(text) }
        let bodyUTF8 = utf8.index(utf8.startIndex, offsetBy: bodyOffset)
        let bodyStart = String.Index(bodyUTF8, within: text) ?? text.endIndex
        return FrontMatterResult(entries: parsedEntries, body: String(text[bodyStart...]))
    }

    private static func unchanged(_ text: String) -> FrontMatterResult {
        FrontMatterResult(entries: [], body: text)
    }

    private static func normalizedLine(_ line: String) -> String {
        var value = line
        if value.unicodeScalars.last?.value == 0x0D {
            value.unicodeScalars.removeLast()
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func parseEntry(_ line: String) -> FrontMatterEntry? {
        guard line.first != " ", line.first != "\t" else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
              let colon = trimmed.firstIndex(of: ":") else { return nil }

        let key = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(key.count),
              key.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return (65...90).contains(value) || (97...122).contains(value)
                      || (48...57).contains(value) || value == 95 || value == 46 || value == 45
              }) else { return nil }

        if value.count >= 2,
           let first = value.first, let last = value.last,
           (first == "'" && last == "'") || (first == "\"" && last == "\"") {
            value.removeFirst()
            value.removeLast()
        }
        if value.count > maximumValueLength {
            value = String(value.prefix(maximumValueLength)) + "…"
        }
        return FrontMatterEntry(key: key, value: value)
    }
}
