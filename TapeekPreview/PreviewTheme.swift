import MarkdownUI
import SwiftUI

extension View {
    func tapeekMarkdownStyle() -> some View {
        self
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(15)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                BackgroundColor(Color.secondary.opacity(0.12))
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                }
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 3)
                    }
            }
    }
}
