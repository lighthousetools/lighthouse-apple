import Foundation

/// What can go wrong when talking to the server.
public enum ClientError: Error, Equatable, LocalizedError {
    case invalidAddress
    case unauthorized
    case server(status: Int, message: String)
    case unreadableAnswer

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "That is not a valid server address."
        case .unauthorized: "Please sign in again."
        case .server(_, let message): message
        case .unreadableAnswer: "The server sent an unexpected answer."
        }
    }
}

private struct ServerError: Decodable {
    let error: String
}

/// Parses the server's dates, which carry up to nine fractional digits.
enum ServerDate {
    static func parse(_ text: String) -> Date? {
        var trimmed = text
        if let dot = text.firstIndex(of: "."), let end = text.lastIndex(of: "Z") {
            let digits = text[text.index(after: dot)..<end].prefix(3)
            trimmed = text[..<dot] + "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0) + "Z"
            return try? Date(trimmed, strategy: .iso8601.year().month().day()
                .time(includingFractionalSeconds: true))
        }
        return try? Date(trimmed, strategy: .iso8601)
    }
}

/// Calls the Lighthouse API.
public struct Client: Sendable {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Normalizes what a person types as a server address.
    public static func serverURL(from text: String) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), let scheme = url.scheme, url.host() != nil,
            ["http", "https"].contains(scheme)
        else { throw ClientError.invalidAddress }
        return url
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ServerDate.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Bad date: \(text)")
            }
            return date
        }
        return decoder
    }

    private func data(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil
    ) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.unreadableAnswer }
        if http.statusCode == 401, token != nil { throw ClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? Self.decoder.decode(ServerError.self, from: data))?.error
            throw ClientError.server(
                status: http.statusCode, message: message ?? "The server answered \(http.statusCode).")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await data("GET", path, query: query)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ClientError.unreadableAnswer
        }
    }

    private func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        let data = try await data("POST", path, body: try JSONEncoder().encode(body))
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ClientError.unreadableAnswer
        }
    }

    private struct Login: Encodable {
        let password: String
        let device_name: String
        let device_kind: String
    }

    public func authStatus() async throws -> AuthStatus { try await get("auth/status") }

    public func login(password: String, device: String, kind: String) async throws -> TokenIssued {
        try await post(
            "auth/login", Login(password: password, device_name: device, device_kind: kind))
    }

    public func logout() async throws { _ = try await data("POST", "auth/logout") }

    private static let pending = [URLQueryItem(name: "status", value: "pending")]

    public func approvals() async throws -> [Approval] {
        try await get("approvals", query: Self.pending)
    }

    public func permissions() async throws -> [Permission] {
        try await get("permissions", query: Self.pending)
    }

    public func sessions() async throws -> [Session] { try await get("sessions") }
    public func nodes() async throws -> [Node] { try await get("nodes") }
    public func agents() async throws -> [Agent] { try await get("agents") }

    public func runs(limit: Int = 20) async throws -> [Run] {
        try await get("runs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    public func costs(days: Int = 7) async throws -> [DailyCost] {
        try await get("costs", query: [URLQueryItem(name: "days", value: String(days))])
    }

    private struct ApprovalDecision: Encodable {
        let approve: Bool
    }

    private struct PermissionDecision: Encodable {
        let allow: Bool
    }

    private struct NodeChange: Encodable {
        let paused: Bool
    }

    private struct Question: Encodable {
        let question: String
    }

    private struct RunStarted: Decodable {
        let id: UUID
    }

    public func decide(approval id: UUID, approve: Bool) async throws {
        _ = try await data(
            "POST", "approvals/\(id.uuidString.lowercased())/decision",
            body: try JSONEncoder().encode(ApprovalDecision(approve: approve)))
    }

    public func decide(permission id: UUID, allow: Bool) async throws {
        _ = try await data(
            "POST", "permissions/\(id.uuidString.lowercased())/decision",
            body: try JSONEncoder().encode(PermissionDecision(allow: allow)))
    }

    public func setPaused(node id: UUID, paused: Bool) async throws {
        _ = try await data(
            "PATCH", "nodes/\(id.uuidString.lowercased())",
            body: try JSONEncoder().encode(NodeChange(paused: paused)))
    }

    public func run(agent id: String) async throws {
        let _: RunStarted = try await post("agents/\(id)/run", [String: String]())
    }

    public func recentEntries() async throws -> [EntrySummary] {
        try await get("brain/entries", query: [URLQueryItem(name: "limit", value: "30")])
    }

    public func search(_ text: String) async throws -> [EntrySummary] {
        let hits: [SearchHit] = try await get(
            "brain/search", query: [URLQueryItem(name: "q", value: text)])
        return hits.map(\.entry)
    }

    public func entry(_ id: UUID) async throws -> EntryDetail {
        try await get("brain/entries/\(id.uuidString.lowercased())")
    }

    public func ask(_ question: String) async throws -> AskAnswer {
        try await post("brain/ask", Question(question: question))
    }

    public func saveNote(title: String, body: String) async throws {
        struct Note: Encodable {
            let type: String
            let title: String
            let body: String
        }
        let _: EntryDetail = try await post(
            "brain/entries", Note(type: "note", title: title, body: body))
    }
}
