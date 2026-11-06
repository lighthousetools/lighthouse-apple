import Foundation

/// Any JSON value, for tool arguments.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Readable, stable text for an approval.
    public var pretty: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct AuthStatus: Sendable, Decodable {
    public let setupRequired: Bool
}

public struct TokenIssued: Sendable, Decodable {
    public let id: UUID
    public let token: String
}

public struct Approval: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let agentId: String
    public let tool: String
    public let input: JSONValue
    public let quotesExternal: Bool
    public let status: String
    public let expiresAt: Date
}

public struct Permission: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let project: String
    public let tool: String
    public let input: JSONValue
    public let status: String
}

public struct Session: Sendable, Decodable, Identifiable, Equatable {
    public let id: String
    public let nodeId: UUID
    public let nodeName: String
    public let project: String
    public let branch: String?
    public let status: String
    public let summary: String?
    public let costEur: Double
    public let updatedAt: Date
}

public struct Node: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let paused: Bool
    public let online: Bool
}

public struct Run: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let agentId: String
    public let status: String
    public let reason: String?
    public let report: String?
    public let costEur: Double
    public let startedAt: Date
}

public struct AgentTool: Sendable, Decodable, Equatable {
    public let name: String
    public let level: String
}

public struct Agent: Sendable, Decodable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let schedule: String?
    public let nextRun: Date?
    public let tools: [AgentTool]
    public let blocked: [String]
}

public struct EntrySummary: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let type: String
    public let title: String
    public let snippet: String
    public let updatedAt: Date
}

public struct SearchHit: Sendable, Decodable, Equatable {
    public let entry: EntrySummary
}

public struct EntryDetail: Sendable, Decodable, Equatable {
    public let id: UUID
    public let title: String
    public let body: String
}

public struct AskAnswer: Sendable, Decodable, Equatable {
    public let answer: String
    public let sources: [EntrySummary]
}

public struct DailyCost: Sendable, Decodable, Equatable {
    public let day: String
    public let provider: String
    public let costEur: Double
}
