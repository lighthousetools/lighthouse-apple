import Testing

@testable import LighthouseKit

@Suite struct MarkdownTests {
    @Test func blocksAreRecognized() {
        let source = """
            # Title

            First line
            second line

            - one
            - two

            1. first
            2. second

            - [ ] open
            - [x] done

            > quoted
            > text

            ---

            | A | B |
            |---|---|
            | 1 | 2 |

            ```swift
            let a = 1

            let b = 2
            ```
            """
        #expect(
            Markdown.parse(source) == [
                .heading(level: 1, text: "Title"),
                .paragraph("First line\nsecond line"),
                .bullets(["one", "two"]),
                .numbered(["first", "second"]),
                .tasks([
                    MarkdownTask(done: false, text: "open"),
                    MarkdownTask(done: true, text: "done"),
                ]),
                .quote("quoted\ntext"),
                .rule,
                .table(header: ["A", "B"], rows: [["1", "2"]]),
                .code(language: "swift", text: "let a = 1\n\nlet b = 2"),
            ])
    }

    @Test func oddInputStaysText() {
        #expect(Markdown.parse("#nospace") == [.paragraph("#nospace")])
        #expect(Markdown.parse("a | b") == [.paragraph("a | b")])
        #expect(Markdown.parse("") == [])
        #expect(Markdown.parse("```\nunclosed") == [.code(language: nil, text: "unclosed")])
    }
}
