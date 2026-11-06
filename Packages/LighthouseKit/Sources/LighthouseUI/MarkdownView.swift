import LighthouseKit
import SwiftUI

/// Renders Markdown with the typography of Lighthouse.
struct MarkdownView: View {
    let source: String
    var size: CGFloat = 15
    /// Follows a `[[Title]]` link.
    var onLink: ((String) -> Void)?

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let linked = Self.linkingWikiTitles(text)
        let styled = (try? AttributedString(markdown: linked, options: options)) ?? AttributedString(text)
        return Text(styled)
    }

    /// Turns `[[Title]]` into a link the view can intercept.
    static func linkingWikiTitles(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            result += rest[..<open.lowerBound]
            let title = rest[open.upperBound..<close.lowerBound]
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            result += "[\(title)](lighthouse-entry:\(encoded))"
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    private func headingFont(_ level: Int) -> Font {
        Theme.display(level == 1 ? size + 11 : level == 2 ? size + 6 : size + 2)
    }

    private func bullet(_ marker: some View, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            inline(text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .foregroundStyle(Theme.ink)
                .padding(.top, level == 1 ? 6 : 10)
        case .paragraph(let text):
            inline(text).lineSpacing(5)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items, id: \.self) { item in
                    bullet(Text("•").foregroundStyle(Theme.lamp), item)
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    bullet(
                        Text("\(index + 1).").font(Theme.mono(size - 2)).foregroundStyle(Theme.lampInk),
                        item)
                }
            }
        case .tasks(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items, id: \.text) { item in
                    bullet(
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? Theme.ok : Theme.ink3),
                        item.text)
                }
            }
        case .quote(let text):
            inline(text)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink2)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.lamp).frame(width: 3)
                }
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 6) {
                if let language { Tag(text: language) }
                Text(text).font(Theme.mono(size - 2)).foregroundStyle(Theme.ink)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(Theme.body(size - 1, weight: .semibold))
                    }
                }
                Divider().overlay(Theme.line)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).font(Theme.body(size - 1))
                        }
                    }
                }
            }
        case .rule:
            Divider().overlay(Theme.line).padding(.vertical, 4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Markdown.parse(source).enumerated()), id: \.offset) { _, item in
                block(item)
            }
        }
        .font(Theme.body(size))
        .foregroundStyle(Theme.ink)
        .tint(Theme.lamp)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard url.scheme == "lighthouse-entry" else { return .systemAction }
                let title = String(url.absoluteString.dropFirst("lighthouse-entry:".count))
                onLink?(title.removingPercentEncoding ?? title)
                return .handled
            })
    }
}
