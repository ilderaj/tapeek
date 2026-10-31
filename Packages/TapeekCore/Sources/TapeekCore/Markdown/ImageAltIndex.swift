import Foundation

public struct ImageAltIndex: Sendable {
    private let alts: [String: String]

    public init(markdown: String, baseURL: URL) {
        var result: [String: String] = [:]
        let pattern = #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            self.alts = result
            return
        }

        var inFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges >= 3,
                      let altRange = Range(match.range(at: 1), in: text),
                      let destinationRange = Range(match.range(at: 2), in: text) else {
                    continue
                }
                let alt = String(text[altRange])
                let destination = String(text[destinationRange])
                guard let url = URL(string: destination, relativeTo: baseURL) else {
                    continue
                }
                let key = url.absoluteString
                if result[key] == nil {
                    result[key] = alt
                }
            }
        }

        self.alts = result
    }

    public func alt(for url: URL) -> String? {
        alts[url.absoluteString]
    }
}
