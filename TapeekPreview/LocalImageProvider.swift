import AppKit
import ImageIO
import MarkdownUI
import SwiftUI
import TapeekCore

struct LocalImageProvider: ImageProvider {
    let altIndex: ImageAltIndex

    func makeImage(url: URL?) -> some View {
        Group {
            if let image = loadImage(url: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LocalImagePlaceholder(
                    alt: altText(for: url),
                    reason: reason(for: url)
                )
            }
        }
    }

    private func loadImage(url: URL?) -> NSImage? {
        guard let url, url.isFileURL else { return nil }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= PreviewLimits.default.maxImageBytes else {
            return nil
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: PreviewLimits.default.maxImagePixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private func altText(for url: URL?) -> String? {
        guard let url else { return nil }
        return altIndex.alt(for: url)
    }

    private func reason(for url: URL?) -> String {
        guard let url else { return "图片缺失" }
        guard url.isFileURL else { return "远程图片未加载" }
        guard FileManager.default.fileExists(atPath: url.path) else { return "图片缺失" }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return "图片不可用"
        }
        if size.intValue > PreviewLimits.default.maxImageBytes {
            return "图片过大"
        }
        return "图片不可用"
    }
}

private struct LocalImagePlaceholder: View {
    let alt: String?
    let reason: String

    private var label: String {
        if let alt, !alt.isEmpty {
            return alt
        }
        return "图片不可用"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(label)
            Text(reason)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
