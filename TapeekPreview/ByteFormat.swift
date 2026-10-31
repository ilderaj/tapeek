import Foundation

enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 字节" }

        let units = ["字节", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }

        if index == 0 {
            return "\(bytes) 字节"
        }

        let formatted = value >= 10
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(units[index])"
    }
}
