import Foundation
import UniformTypeIdentifiers

public enum PreviewKind: Equatable, Sendable {
    case markdown
    case zip
    case unsupported
}

public enum PreviewKindResolver {
    public static func resolve(pathExtension: String) -> PreviewKind {
        let value = pathExtension
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch value {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        case "zip":
            return .zip
        default:
            return .unsupported
        }
    }

    public static func resolve(fileURL: URL) -> PreviewKind {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType {
            if contentType.conforms(to: .zip) {
                return .zip
            }
            if let markdownType = UTType("net.daringfireball.markdown"),
               contentType.conforms(to: markdownType) {
                return .markdown
            }
        }

        return resolve(pathExtension: fileURL.pathExtension)
    }
}
