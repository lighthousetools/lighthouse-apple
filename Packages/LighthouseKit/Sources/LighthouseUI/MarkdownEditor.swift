import LighthouseKit
import SwiftUI

/// The commands of the `/` menu.
enum SlashCommand: String, CaseIterable, Identifiable {
    case heading = "Heading"
    case list = "List"
    case task = "Task"
    case table = "Table"
    case code = "Code"
    case quote = "Quote"
    case link = "Link"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .heading: "textformat.size"
        case .list: "list.bullet"
        case .task: "checklist"
        case .table: "tablecells"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .quote: "text.quote"
        case .link: "link"
        }
    }

    var insertion: String {
        switch self {
        case .heading: "## "
        case .list: "- "
        case .task: "- [ ] "
        case .table: "| A | B |\n|---|---|\n|  |  |"
        case .code: "```\n\n```"
        case .quote: "> "
        case .link: "[["
        }
    }
}

#if os(macOS)
    import AppKit
    import CoreText

    /// Lets the workspace reach the text view.
    @MainActor
    final class EditorController {
        weak var textView: NSTextView?

        /// Replaces the `/` line with a command.
        func apply(_ command: SlashCommand) {
            guard let textView else { return }
            let text = textView.string as NSString
            let cursor = textView.selectedRange().location
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            let body = text.substring(with: line)
            let length = body.hasSuffix("\n") ? line.length - 1 : line.length
            let target = NSRange(location: line.location, length: length)
            textView.insertText(command.insertion, replacementRange: target)
            textView.window?.makeFirstResponder(textView)
        }
    }

    /// Markdown that formats itself while you type. The syntax stays visible
    /// but steps back, so the file on disk is exactly what you see.
    struct MarkdownEditor: NSViewRepresentable {
        @Binding var text: String
        @Binding var slashQuery: String?
        let controller: EditorController

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSTextView.scrollableTextView()
            let view = scroll.documentView as! NSTextView
            view.delegate = context.coordinator
            view.isRichText = false
            view.allowsUndo = true
            view.drawsBackground = false
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.textContainerInset = NSSize(width: 26, height: 20)
            view.string = text
            scroll.drawsBackground = false
            controller.textView = view
            MarkdownStyler.apply(to: view)
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
            view.string = text
            MarkdownStyler.apply(to: view)
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            let parent: MarkdownEditor

            init(_ parent: MarkdownEditor) {
                self.parent = parent
            }

            func textDidChange(_ notification: Notification) {
                guard let view = notification.object as? NSTextView else { return }
                parent.text = view.string
                MarkdownStyler.apply(to: view)
                let text = view.string as NSString
                let cursor = min(view.selectedRange().location, text.length)
                let line = text.substring(with: text.lineRange(for: NSRange(location: cursor, length: 0)))
                    .trimmingCharacters(in: .newlines)
                parent.slashQuery = line.hasPrefix("/") ? String(line.dropFirst()).lowercased() : nil
            }
        }
    }

    enum MarkdownStyler {
        /// Sets the weight axis directly, since the bundled fonts are variable.
        private static func font(_ name: String, _ size: CGFloat, _ weight: CGFloat = 400) -> NSFont {
            let base = NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
            let axis = kCTFontVariationAttribute as String
            let descriptor = base.fontDescriptor.addingAttributes([
                NSFontDescriptor.AttributeName(axis): [0x7767_6874: weight]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        private static let sans = "IBM Plex Sans"
        private static let display = "Schibsted Grotesk"
        private static let mono = "IBM Plex Mono"

        private static func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }

        private static let headings = regex("^(#{1,3}) (.*)$")
        private static let bold = regex("(\\*\\*)(.+?)(\\*\\*)")
        private static let italic = regex("(?<![*\\w])(\\*)([^*\\n]+)(\\*)(?!\\*)")
        private static let inlineCode = regex("(`)([^`\\n]+)(`)")
        private static let wiki = regex("(\\[\\[)([^\\]\\n]+)(\\]\\])")
        private static let quote = regex("^(> ?)(.*)$")
        private static let marker = regex("^(\\s*(?:[-*+]|\\d+\\.)(?: \\[[ xX]\\])? )")
        private static let fence = regex("^```[^\\n]*\\n(?:.*\\n)*?```$")

        @MainActor static func apply(to view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let text = storage.string as NSString
            let all = NSRange(location: 0, length: text.length)
            let ink = NSColor(Theme.ink)
            let dim = NSColor(Theme.ink3)
            let lamp = NSColor(Theme.lampInk)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 4
            storage.beginEditing()
            storage.setAttributes(
                [.font: font(sans, 16), .foregroundColor: ink, .paragraphStyle: paragraph], range: all)
            let each = { (expression: NSRegularExpression, body: (NSTextCheckingResult) -> Void) in
                expression.enumerateMatches(in: storage.string, range: all) { match, _, _ in
                    if let match { body(match) }
                }
            }
            each(headings) { match in
                let level = match.range(at: 1).length
                let size: CGFloat = level == 1 ? 28 : level == 2 ? 22 : 18
                storage.addAttribute(.font, value: font(display, size, 700), range: match.range)
                storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: 1))
            }
            each(bold) { match in
                storage.addAttribute(.font, value: font(sans, 16, 700), range: match.range(at: 2))
                for group in [1, 3] { storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: group)) }
            }
            each(italic) { match in
                let italic = NSFontManager.shared.convert(font(sans, 16), toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italic, range: match.range(at: 2))
                for group in [1, 3] { storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: group)) }
            }
            each(inlineCode) { match in
                storage.addAttribute(.font, value: font(mono, 14), range: match.range(at: 2))
                storage.addAttribute(.backgroundColor, value: NSColor(Theme.surface3), range: match.range(at: 2))
                for group in [1, 3] { storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: group)) }
            }
            each(wiki) { match in
                storage.addAttribute(.foregroundColor, value: lamp, range: match.range(at: 2))
                for group in [1, 3] { storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: group)) }
            }
            each(quote) { match in
                storage.addAttribute(.foregroundColor, value: NSColor(Theme.ink2), range: match.range(at: 2))
                storage.addAttribute(.foregroundColor, value: lamp, range: match.range(at: 1))
            }
            each(marker) { match in
                storage.addAttribute(.foregroundColor, value: lamp, range: match.range(at: 1))
            }
            each(fence) { match in
                storage.addAttribute(.font, value: font(mono, 14), range: match.range)
                storage.addAttribute(.backgroundColor, value: NSColor(Theme.surface2), range: match.range)
            }
            storage.endEditing()
            view.typingAttributes = [
                .font: font(sans, 16), .foregroundColor: ink, .paragraphStyle: paragraph,
            ]
            view.insertionPointColor = NSColor(Theme.lamp)
        }
    }
#else
    @MainActor
    final class EditorController {
        var append: ((String) -> Void)?

        func apply(_ command: SlashCommand) {
            append?(command.insertion)
        }
    }

    /// Plain Markdown on iOS.
    struct MarkdownEditor: View {
        @Binding var text: String
        @Binding var slashQuery: String?
        let controller: EditorController

        var body: some View {
            TextEditor(text: $text)
                .font(Theme.body(16))
                .scrollContentBackground(.hidden)
                .padding(14)
                .onAppear {
                    controller.append = { insertion in
                        if let slash = text.range(of: "/", options: .backwards) {
                            text.replaceSubrange(slash.lowerBound..., with: insertion)
                        } else {
                            text += insertion
                        }
                    }
                }
                .onChange(of: text) {
                    let line = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
                    slashQuery = line.hasPrefix("/") ? String(line.dropFirst()).lowercased() : nil
                }
        }
    }
#endif
