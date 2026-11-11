import Foundation

public enum MarkdownChunker {
    /// Splits large Markdown into safe chunks at top-level headings or blank
    /// lines, never inside a fenced code block. Joining the result with a newline
    /// reproduces the input exactly.
    public static func chunks(_ text: String, targetBytes: Int = 12_000) -> [String] {
        guard targetBytes > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
        guard text.utf8.count > targetBytes else { return [text] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var current: [Substring] = []
        var currentBytes = 0
        var activeFence: Fence?

        func flush() {
            guard !current.isEmpty else { return }
            result.append(current.joined(separator: "\n"))
            current.removeAll(keepingCapacity: true)
            currentBytes = 0
        }

        for line in lines {
            let fenceBeforeLine = activeFence
            let isHeading = fenceBeforeLine == nil && isMarkdownHeading(line)
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            if fenceBeforeLine == nil, currentBytes >= targetBytes, isHeading || isBlank {
                flush()
            } else if fenceBeforeLine == nil, currentBytes >= targetBytes * 2 {
                flush()
            }

            current.append(line)
            currentBytes += line.utf8.count + 1
            activeFence = updatedFence(activeFence, for: line)
        }

        flush()
        return result
    }

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private struct FenceMarker {
        let character: Character
        let length: Int
        let remainder: Substring
    }

    private static func updatedFence(_ activeFence: Fence?, for line: Substring) -> Fence? {
        guard let marker = fenceMarker(in: line) else { return activeFence }

        if let activeFence {
            let isWhitespaceOnlyTail = marker.remainder.allSatisfy { $0 == " " || $0 == "\t" }
            guard marker.character == activeFence.marker,
                  marker.length >= activeFence.length,
                  isWhitespaceOnlyTail else { return activeFence }
            return nil
        }

        guard marker.length >= 3,
              marker.character != "`" || !marker.remainder.contains("`") else { return nil }
        return Fence(marker: marker.character, length: marker.length)
    }

    private static func fenceMarker(in line: Substring) -> FenceMarker? {
        let markerLine = line.last == Character(UnicodeScalar(13)) ? line.dropLast() : line
        var index = markerLine.startIndex
        var indentation = 0
        while index < markerLine.endIndex, markerLine[index] == " " {
            indentation += 1
            index = markerLine.index(after: index)
        }
        guard indentation <= 3, index < markerLine.endIndex else { return nil }

        let character = markerLine[index]
        guard character == "`" || character == "~" else { return nil }

        let markerStart = index
        while index < markerLine.endIndex, markerLine[index] == character {
            index = markerLine.index(after: index)
        }
        let length = markerLine.distance(from: markerStart, to: index)
        return FenceMarker(character: character, length: length, remainder: markerLine[index...])
    }

    private static func isMarkdownHeading(_ line: Substring) -> Bool {
        guard let first = line.first, first == "#" else { return false }
        var count = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", count < 7 {
            count += 1
            index = line.index(after: index)
        }
        guard (1...6).contains(count), index < line.endIndex else { return false }
        return line[index] == " "
    }
}
