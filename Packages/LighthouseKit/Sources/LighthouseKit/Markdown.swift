import Foundation

/// A block of Markdown, as far as the apps display it.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case tasks([MarkdownTask])
    case quote(String)
    case code(language: String?, text: String)
    case table(header: [String], rows: [[String]])
    case rule
}

public struct MarkdownTask: Equatable, Sendable {
    public let done: Bool
    public let text: String
}

/// Splits Markdown into blocks. Inline styles stay in the text.
public enum Markdown {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")[...]
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                lines.removeFirst()
            } else if trimmed.hasPrefix("```") {
                blocks.append(code(&lines))
            } else if let heading = heading(trimmed) {
                lines.removeFirst()
                blocks.append(heading)
            } else if isRule(trimmed) {
                lines.removeFirst()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                let quoted = take(&lines) { $0.hasPrefix(">") }
                blocks.append(.quote(quoted.map(unquote).joined(separator: "\n")))
            } else if task(trimmed) != nil {
                blocks.append(.tasks(take(&lines) { task($0) != nil }.compactMap(task)))
            } else if bullet(trimmed) != nil {
                blocks.append(.bullets(take(&lines) { bullet($0) != nil }.compactMap(bullet)))
            } else if number(trimmed) != nil {
                blocks.append(.numbered(take(&lines) { number($0) != nil }.compactMap(number)))
            } else if let table = table(&lines) {
                blocks.append(table)
            } else {
                blocks.append(.paragraph(paragraph(&lines)))
            }
        }
        return blocks
    }

    private static func take(
        _ lines: inout ArraySlice<String>, while matches: (String) -> Bool
    ) -> [String] {
        var taken: [String] = []
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard matches(trimmed) else { break }
            taken.append(trimmed)
            lines.removeFirst()
        }
        return taken
    }

    private static func code(_ lines: inout ArraySlice<String>) -> MarkdownBlock {
        let fence = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let language = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var body: [String] = []
        while let line = lines.first {
            lines.removeFirst()
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
            body.append(line)
        }
        return .code(
            language: language.isEmpty ? nil : language, text: body.joined(separator: "\n"))
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return .heading(
            level: level, text: line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && ["-", "*", "_"].contains { line == String(repeating: $0, count: line.count) }
    }

    private static func unquote(_ line: String) -> String {
        line.drop { $0 == ">" }.trimmingCharacters(in: .whitespaces)
    }

    private static func bullet(_ line: String) -> String? {
        ["- ", "* ", "+ "].first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
    }

    private static func task(_ line: String) -> MarkdownTask? {
        guard let item = bullet(line) else { return nil }
        if item.hasPrefix("[ ] ") { return MarkdownTask(done: false, text: String(item.dropFirst(4))) }
        if item.lowercased().hasPrefix("[x] ") {
            return MarkdownTask(done: true, text: String(item.dropFirst(4)))
        }
        return nil
    }

    private static func number(_ line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.dropFirst(digits.count + 2))
    }

    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func table(_ lines: inout ArraySlice<String>) -> MarkdownBlock? {
        guard lines.count >= 2, lines[lines.startIndex].contains("|") else { return nil }
        let divider = lines[lines.startIndex + 1].trimmingCharacters(in: .whitespaces)
        let isDivider = divider.contains("-") && divider.allSatisfy { "|-: ".contains($0) }
        guard isDivider else { return nil }
        let header = cells(lines.removeFirst())
        lines.removeFirst()
        let rows = take(&lines) { $0.contains("|") }.map(cells)
        return .table(header: header, rows: rows)
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix(">") || heading(line) != nil || isRule(line)
            || bullet(line) != nil || number(line) != nil
    }

    private static func paragraph(_ lines: inout ArraySlice<String>) -> String {
        var text = [lines.removeFirst().trimmingCharacters(in: .whitespaces)]
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsBlock(trimmed) { break }
            text.append(trimmed)
            lines.removeFirst()
        }
        return text.joined(separator: "\n")
    }
}
