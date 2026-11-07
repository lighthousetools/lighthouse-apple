import Foundation

/// What the quick panel saves: a note for the Brain or a task for the list.
public enum QuickEntryKind: String, CaseIterable, Identifiable, Sendable {
    case note, task

    public var id: String { rawValue }
}

/// Text from the quick panel, split into a first line and the rest.
public struct QuickEntry: Equatable, Sendable {
    public let title: String
    public let body: String

    /// The first line becomes the title, at most `limit` characters; the rest
    /// becomes the body or the notes.
    public init(text: String, limit: Int = 80) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        title = String((lines.first ?? "").trimmingCharacters(in: .whitespaces).prefix(limit))
        body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    public var isEmpty: Bool { title.isEmpty }
}
