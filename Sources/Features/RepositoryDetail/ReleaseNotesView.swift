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
        Self.render(markdown: markdown)
    }

    /// GitHub 的 Release Notes 是完整 Markdown。`Text` 只吃 inline 语法，
    /// 所以先把块级标记（标题、列表、引用、代码围栏）拍平成可读文本，
    /// 再交给 `AttributedString` 处理粗体、斜体、行内代码与链接。
    static func render(markdown: String) -> AttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []

        for rawLine in normalized.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }

            var line = rawLine
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                line = String(trimmed[match.upperBound...])
            } else if let match = trimmed.range(of: "^[-*+]\\s+", options: .regularExpression) {
                line = "• " + trimmed[match.upperBound...]
            } else if trimmed.hasPrefix(">") {
                line = "▎" + String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if let match = trimmed.range(of: "^\\[[ xX]\\]\\s*", options: .regularExpression) {
                let checked = trimmed.lowercased().hasPrefix("[x]")
                line = (checked ? "☑ " : "☐ ") + String(trimmed[match.upperBound...])
            }
            lines.append(line)
        }

        // 合并多余空行，避免说明里的大段空白把卡片撑得很高。
        let flattened = lines.reduce(into: [String]()) { result, line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty,
               result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                return
            }
            result.append(line)
        }

        let text = flattened.joined(separator: "\n")
        return (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var plainText: String {
        String(attributed.characters)
    }

    /// 说明本身很短时不必提供「展开」，否则按钮点了没有变化，反而像坏掉。
    private var needsDisclosure: Bool {
        plainText.count > 420 || plainText.components(separatedBy: "\n").count > collapsedLineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "更新说明", systemImage: "text.alignleft")
                if needsDisclosure {
                    Button(isExpanded ? "收起" : "展开") {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                }
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
