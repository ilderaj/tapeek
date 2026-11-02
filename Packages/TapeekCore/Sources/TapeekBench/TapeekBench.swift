import Darwin
import Foundation
import TapeekCore

@main
struct TapeekBench {
    private static let runCount = 3

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            fail("usage: TapeekBench markdown|zip <path>")
        }
        let kind = arguments[0]
        let url = URL(fileURLWithPath: arguments[1])
        do {
            switch kind {
            case "markdown":
                try benchmarkMarkdown(url: url)
            case "zip":
                try benchmarkZip(url: url)
            default:
                fail("unknown benchmark kind: \(kind) (expected markdown or zip)")
            }
        } catch {
            fail("\(kind) benchmark failed for \(url.path): \(error)")
        }
    }

    private static func benchmarkMarkdown(url: URL) throws {
        var byteCount = 0
        let warmup = try MarkdownLoader.load(url: url)
        byteCount = warmup.byteCount
        blackHole(warmup.body.utf8.count)

        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<runCount {
            let start = clock.now
            let document = try MarkdownLoader.load(url: url)
            let elapsed = clock.now - start
            byteCount = document.byteCount
            blackHole(document.body.utf8.count)
            samples.append(milliseconds(elapsed))
        }
        print("kind=markdown bytes=\(byteCount) median_ms=\(format(median(samples))) runs=\(runCount)")
    }

    private static func benchmarkZip(url: URL) throws {
        var shownEntries = 0
        var checksum = 0

        func runOnce() throws {
            let listing = try ZipArchiveReader.list(url: url)
            let tree = ZipTree(listing: listing, archiveName: url.lastPathComponent)
            shownEntries = listing.shownEntryCount
            checksum = tree.root.children.count &+ tree.fileCount &+ tree.directoryCount &+ listing.entries.count
        }

        try runOnce()
        blackHole(checksum)

        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<runCount {
            let start = clock.now
            try runOnce()
            let elapsed = clock.now - start
            blackHole(checksum)
            samples.append(milliseconds(elapsed))
        }
        print("kind=zip entries=\(shownEntries) median_ms=\(format(median(samples))) runs=\(runCount)")
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    @inline(never)
    private static func blackHole(_ value: Int) {
        if value == Int.min {
            FileHandle.standardError.write(Data())
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
