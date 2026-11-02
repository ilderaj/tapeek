import Foundation

public enum MarkdownChunker {
    /// Splits large Markdown into safe chunks at top-level headings or blank
    /// lines, never inside a fenced code block. Joining the result reproduces
    /// the input exactly.
    public static func chunks(_ text: String, targetBytes: Int = 12_000) -> [String] {
        guard targetBytes > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
        guard text.utf8.count > targetBytes else { return [text] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var current: [Substring] = []
        var currentBytes = 0
        var inFence = false

        func flush() {
            guard !current.isEmpty else { return }
            result.append(current.joined(separator: "\n"))
            current.removeAll(keepingCapacity: true)
            currentBytes = 0
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            let isHeading = !inFence && isMarkdownHeading(line)
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            if !inFence, currentBytes >= targetBytes, isHeading || isBlank {
                flush()
            } else if !inFence, currentBytes >= targetBytes * 2 {
                flush()
            }

            current.append(line)
            currentBytes += line.utf8.count + 1

            if isFence {
                inFence.toggle()
            }
        }

        flush()
        return result
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
