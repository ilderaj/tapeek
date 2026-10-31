import Foundation

public enum PreviewFailure: Error, Equatable, Sendable {
    case unreadableFile
    case unsupportedTextEncoding
    case fileTooLarge(actualBytes: Int, limitBytes: Int)
    case archiveUnreadable
    case archiveEncrypted
    case archiveUnsupported(message: String)
    case listingTimedOut
}
