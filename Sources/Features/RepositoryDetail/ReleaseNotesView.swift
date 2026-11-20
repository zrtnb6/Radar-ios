import SwiftUI

/// Release Notes 折叠卡片。
/// GitHub 的说明是 Markdown，这里用 `AttributedString` 的 inline 解析保留粗体、链接与换行，
/// 不引入第三方渲染器，长文本默认折叠，避免详情页被一大段说明淹没。
struct ReleaseNotesView: View {
    let markdown: String
    var initiallyExpanded = false
    var collapsedLineLimit = 8

    @State private var isExpanded: Bool

    init(markdown: String, initiallyExpanded: Bool = false, collapsedLineLimit: Int = 8) {
        self.markdown = markdown
        self.initiallyExpanded = initiallyExpanded
        self.collapsedLineLimit = collapsedLineLimit
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "更新说明", systemImage: "text.alignleft")
                Button(isExpanded ? "收起" : "展开") {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
            }

            Text(attributed)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }
}
