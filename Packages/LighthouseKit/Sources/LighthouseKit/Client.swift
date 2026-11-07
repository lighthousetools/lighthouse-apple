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

/// One server-sent event.
public struct ServerEvent: Sendable, Equatable {
    public let name: String
    public let data: String
}

/// A step of a streamed answer.
public enum AskEvent: Sendable, Equatable {
    case delta(String)
    case done(AskAnswer)
}

/// Collects the lines of server-sent events.
struct EventParser {
    private var name = ""
    private var data = ""

    mutating func feed(_ line: String) -> ServerEvent? {
        if line.isEmpty {
            defer {
                name = ""
                data = ""
            }
            return name.isEmpty ? nil : ServerEvent(name: name, data: data)
        }
        if line.hasPrefix("event:") {
            name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
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

    private func request(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        contentType: String = "application/json"
    ) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.unreadableAnswer }
        if http.statusCode == 401, token != nil { throw ClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? Self.decoder.decode(ServerError.self, from: data))?.error
            throw ClientError.server(
                status: http.statusCode, message: message ?? "The server answered \(http.statusCode).")
        }
    }

    private func data(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        let request = request(method, path, query: query, body: body, contentType: contentType)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    /// Reads server-sent events from a request.
    private func events(of base: URLRequest) -> AsyncThrowingStream<ServerEvent, Error> {
        var timed = base
        timed.timeoutInterval = 3600
        let request = timed
        let session = self.session
        let client = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try client.check(response, Data())
                    var parser = EventParser()
                    var line: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let text = String(decoding: line, as: UTF8.self)
                            line.removeAll(keepingCapacity: true)
                            if let event = parser.feed(text) { continuation.yield(event) }
                        } else if byte != UInt8(ascii: "\r") {
                            line.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Tells when something the apps show has changed.
    public func changes() -> AsyncThrowingStream<ServerEvent, Error> {
        events(of: request("GET", "events"))
    }

    /// Asks the Brain and delivers the answer as it arrives.
    public func askStream(_ question: String) throws -> AsyncThrowingStream<AskEvent, Error> {
        let body = try JSONEncoder().encode(Question(question: question))
        let stream = events(of: request("POST", "brain/ask/stream", body: body))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        if let parsed = try Self.askEvent(event) { continuation.yield(parsed) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Delta: Decodable {
        let text: String
    }

    static func askEvent(_ event: ServerEvent) throws -> AskEvent? {
        let data = Data(event.data.utf8)
        switch event.name {
        case "delta": return .delta(try decoder.decode(Delta.self, from: data).text)
        case "done": return .done(try decoder.decode(AskAnswer.self, from: data))
        case "failed":
            let failure = try decoder.decode(ServerError.self, from: data)
            throw ClientError.server(status: 502, message: failure.error)
        default: return nil
        }
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

    public func me() async throws -> Me { try await get("me") }
    public func ready() async throws -> ReadyFeed { try await get("ready") }
    public func organizations() async throws -> [Organization] { try await get("organizations") }
    public func alertCounts() async throws -> AlertCounts { try await get("alerts/counts") }

    /// Unresolved alerts, worst first.
    public func activeAlerts(limit: Int = 20) async throws -> [Alert] {
        try await get(
            "alerts",
            query: [URLQueryItem(name: "view", value: "active"), URLQueryItem(name: "limit", value: String(limit))])
    }

    private struct NewTask: Encodable {
        let title: String
        let notes: String?
    }

    /// Puts a task at the top of the owner's list.
    public func createTask(title: String, notes: String? = nil) async throws -> TaskItem {
        try await post("tasks", NewTask(title: title, notes: notes?.isEmpty == true ? nil : notes))
    }
    public func connectors() async throws -> [Connector] { try await get("connectors") }
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

    /// Decides many proposals at once.
    public func decide(approvals ids: [UUID], approve: Bool) async throws {
        struct Batch: Encodable {
            let ids: [UUID]
            let approve: Bool
        }
        _ = try await data(
            "POST", "approvals/decisions",
            body: try JSONEncoder().encode(Batch(ids: ids, approve: approve)))
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

    public func resolve(title: String) async throws -> UUID {
        struct Resolved: Decodable {
            let id: UUID
        }
        let resolved: Resolved = try await get(
            "brain/resolve", query: [URLQueryItem(name: "title", value: title)])
        return resolved.id
    }

    public func entry(_ id: UUID) async throws -> EntryDetail {
        try await get("brain/entries/\(id.uuidString.lowercased())")
    }

    public func ask(_ question: String) async throws -> AskAnswer {
        try await post("brain/ask", Question(question: question))
    }

    private struct NewNote: Encodable {
        let type: String
        let title: String
        let body: String
    }

    private struct EntryChange: Encodable {
        let title: String
        let body: String
    }

    /// Stores a new note and returns it.
    public func createNote(title: String, body: String) async throws -> EntryDetail {
        try await post("brain/entries", NewNote(type: "note", title: title, body: body))
    }

    public func update(entry id: UUID, title: String, body: String) async throws {
        _ = try await data(
            "PATCH", "brain/entries/\(id.uuidString.lowercased())",
            body: try JSONEncoder().encode(EntryChange(title: title, body: body)))
    }

    public func delete(entry id: UUID) async throws {
        _ = try await data("DELETE", "brain/entries/\(id.uuidString.lowercased())")
    }

    /// Uploads a file and returns its entry.
    public func upload(name: String, contentType: String, bytes: Data) async throws -> EntryDetail {
        let data = try await data(
            "POST", "brain/files", query: [URLQueryItem(name: "name", value: name)], body: bytes,
            contentType: contentType)
        do {
            return try Self.decoder.decode(EntryDetail.self, from: data)
        } catch {
            throw ClientError.unreadableAnswer
        }
    }

    /// Downloads the original of a file.
    public func original(of id: UUID) async throws -> Data {
        try await data("GET", "brain/files/\(id.uuidString.lowercased())")
    }
}
