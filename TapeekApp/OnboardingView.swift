import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Tapeek")
                .font(.largeTitle.bold())

            Text("在 Finder 中按空格，直接阅读 Markdown 和 ZIP。")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("TAPEEK-SMOKE 宿主占位页")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
