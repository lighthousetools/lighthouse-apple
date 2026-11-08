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

    /// The fields of an object as readable pairs, for a proposal in plain words.
    /// Nested values stay JSON. Anything but an object has no fields.
    public var fields: [(name: String, value: String)] {
        guard case .object(let values) = self else { return [] }
        return values.sorted { $0.key < $1.key }.map { key, value in
            let name = key.replacingOccurrences(of: "_", with: " ")
            return (name.prefix(1).uppercased() + name.dropFirst(), value.text)
        }
    }

    /// The value as text.
    public var text: String {
        switch self {
        case .null: ""
        case .bool(let value): value ? "true" : "false"
        case .number(let value):
            value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .string(let value): value
        case .array, .object: pretty
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

/// Who may create an account on a server.
public enum SignupMode: String, Sendable, Equatable {
    /// Nobody signs up and nobody is invited, as in a single-user install.
    case closed
    /// Owners and admins invite people by email.
    case invite
    /// Anyone signs up and owns a new tenant.
    case open
}

/// What a server needs for a sign-in. Servers before 0.2 only send
/// `setup_required`, so the rest falls back to a single-user install.
public struct AuthStatus: Sendable, Decodable, Equatable {
    public let setupRequired: Bool
    public let signup: SignupMode
    /// Whether the sign-in needs an email address: once the server has more than one user.
    public let emailRequired: Bool

    public init(setupRequired: Bool = false, signup: SignupMode = .closed, emailRequired: Bool = false) {
        self.setupRequired = setupRequired
        self.signup = signup
        self.emailRequired = emailRequired
    }

    private enum CodingKeys: String, CodingKey {
        case setupRequired, signup, emailRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setupRequired = try container.decodeIfPresent(Bool.self, forKey: .setupRequired) ?? false
        let mode = try container.decodeIfPresent(String.self, forKey: .signup)
        signup = mode.flatMap(SignupMode.init(rawValue:)) ?? .closed
        emailRequired = try container.decodeIfPresent(Bool.self, forKey: .emailRequired) ?? false
    }
}

/// A new device token. `tenantId` and `userId` come from servers since 0.2.
public struct TokenIssued: Sendable, Decodable {
    public let id: UUID
    public let token: String
    public let tenantId: UUID?
    public let userId: UUID?
}

/// The role of a user in a tenant.
public enum Role: String, Sendable, Equatable, Decodable {
    case owner, admin, member

    /// Owners and admins change credentials, connections and the budget.
    public var canAdminister: Bool { self != .member }
}

/// A tenant the user belongs to.
public struct Membership: Sendable, Decodable, Equatable, Identifiable {
    public let tenantId: UUID
    public let tenantName: String
    public let role: Role?
    public var id: UUID { tenantId }

    private enum CodingKeys: String, CodingKey {
        case tenantId, tenantName, role
    }

    public init(tenantId: UUID, tenantName: String, role: Role?) {
        self.tenantId = tenantId
        self.tenantName = tenantName
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tenantId = try container.decode(UUID.self, forKey: .tenantId)
        tenantName = try container.decode(String.self, forKey: .tenantName)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)).flatMap { $0.flatMap(Role.init) }
    }
}

public struct Approval: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let agentId: String
    public let tool: String
    public let input: JSONValue
    public let quotesExternal: Bool
    public let reason: String?
    public let consulted: [String]
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
    public let activity: String?
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
    public let original: String?
    public let updatedAt: Date
}

public struct SearchHit: Sendable, Decodable, Equatable {
    public let entry: EntrySummary
}

public struct EntrySource: Sendable, Decodable, Equatable {
    public let kind: String
    public let ref: String
}

public struct EntryDetail: Sendable, Decodable, Equatable, Identifiable {
    public let id: UUID
    public let type: String
    public let title: String
    public let body: String
    public let status: String
    public let sources: [EntrySource]
    public let links: [String]
    public let original: String?
    public let updated: Date
    public let backlinks: [EntrySummary]?
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

/// The signed-in user in the tenant of the token. Servers before 0.2 only send the name.
public struct Me: Sendable, Decodable, Equatable {
    public let name: String
    public let email: String?
    public let emailVerified: Bool?
    public let userId: UUID?
    public let tenantId: UUID?
    public let tenantName: String?
    /// Nil on servers before 0.2, where the only person is the owner.
    public let role: Role?

    private enum CodingKeys: String, CodingKey {
        case name, email, emailVerified, userId, tenantId, tenantName, role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        tenantId = try container.decodeIfPresent(UUID.self, forKey: .tenantId)
        tenantName = try container.decodeIfPresent(String.self, forKey: .tenantName)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)).flatMap { $0.flatMap(Role.init) }
    }
}

public struct Connector: Sendable, Decodable, Identifiable, Equatable {
    public let name: String
    public let auth: String
    public let connected: Bool
    public var id: String { name }
}

/// One thing that waits for the owner in the ready feed.
public struct ReadyItem: Sendable, Decodable, Identifiable, Equatable {
    public let kind: String
    public let group: String
    public let id: String
    public let title: String
    public let summary: String?
    public let agentId: String?
    public let createdAt: Date

    /// The key the web app uses for the item, `kind:id`.
    public var key: String { "\(kind):\(id)" }
    public var route: WebRoute { .readyItem(kind: kind, id: id) }
}

/// Unresolved alerts per severity.
public struct AlertCounts: Sendable, Decodable, Equatable {
    public let critical: Int
    public let warning: Int
    public let info: Int

    public init(critical: Int = 0, warning: Int = 0, info: Int = 0) {
        self.critical = critical
        self.warning = warning
        self.info = info
    }

    public var total: Int { critical + warning + info }
}

/// Everything that waits for the owner, in one answer.
public struct ReadyFeed: Sendable, Decodable, Equatable {
    public let total: Int
    public let alerts: AlertCounts
    public let items: [ReadyItem]
}

/// Something that broke.
public struct Alert: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let kind: String
    public let severity: String
    public let title: String
    public let status: String
    public let count: Int
    public let lastSeenAt: Date

    public var isCritical: Bool { severity == "critical" }
    public var route: WebRoute { .alert(id) }
}

/// A task of the owner's list.
public struct TaskItem: Sendable, Decodable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let status: String
}

/// A company or other organization the owner works for. Lists and numbers
/// in the web app can show one of them.
public struct Organization: Sendable, Decodable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let color: String?
}
