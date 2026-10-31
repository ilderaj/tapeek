import Foundation
import TapeekCore

struct PreviewErrorPresentation {
    let title: String
    let detail: String
    let symbolName: String

    init(failure: PreviewFailure, fileName: String) {
        switch failure {
        case .unreadableFile:
            title = "无法读取文件"
            detail = "文件可能已被移动，或当前没有读取权限。"
            symbolName = "doc.questionmark"
        case .unsupportedTextEncoding:
            title = "无法识别文本编码"
            detail = "请将文件转换为 UTF-8 后重试。"
            symbolName = "textformat.abc"
        case let .fileTooLarge(actualBytes, limitBytes):
            title = "文档过大"
            let actual = ByteCountFormatter.string(fromByteCount: Int64(actualBytes), countStyle: .file)
            let limit = ByteCountFormatter.string(fromByteCount: Int64(limitBytes), countStyle: .file)
            detail = "文件为 \(actual)，超过 \(limit) 的预览上限。"
            symbolName = "doc.questionmark"
        case .archiveUnreadable:
            title = "无法读取压缩包"
            detail = "文件可能已损坏，或不是标准 ZIP。"
            symbolName = "doc.questionmark"
        case .archiveEncrypted:
            title = "压缩包已加密"
            detail = "无法读取加密的目录信息。首版不支持输入密码。"
            symbolName = "lock"
        case let .archiveUnsupported(message):
            title = "暂不支持此压缩包"
            detail = message
            symbolName = "archivebox"
        case .listingTimedOut:
            title = "读取超时"
            detail = "压缩包较大或结构异常，未能读取目录。"
            symbolName = "clock"
        }
    }
}
