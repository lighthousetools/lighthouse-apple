import Foundation
import Testing

@testable import LighthouseKit

/// Answers requests from a table and records them.
final class FakeServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var seen: [URLRequest] = []
    private static let lock = NSLock()

    static func session(_ routes: [String: (Int, String)]) -> URLSession {
        lock.withLock {
            self.routes = routes
            seen = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let key = "\(request.httpMethod ?? "") \(request.url?.path() ?? "")"
        let (status, body) = Self.lock.withLock {
            Self.seen.append(request)
            if key == "GET /me", Self.routes[key] == nil { return (200, #"{"name":"Alex"}"#) }
            return Self.routes[key] ?? (200, "[]")
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class MemoryStore: TokenStore, @unchecked Sendable {
    var token: String?
    init(_ token: String? = nil) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func clear() { token = nil }
}

let approvalJSON = """
    [{"id":"019a0000-0000-7000-8000-000000000001","run_id":"019a0000-0000-7000-8000-000000000002",
    "agent_id":"mailer","tool":"mail.send","input":{"to":"a","n":1,"ok":true,"list":[null]},
    "quotes_external":true,"status":"pending","created_at":"2026-11-06T10:00:00.409874Z",
    "expires_at":"2026-11-09T10:00:00Z","decided_at":null}]
    """

/// One shared fake server, so these suites must not overlap.
@Suite(.serialized) struct ServerTests {
@Suite struct ClientTests {
    let url = URL(string: "https://lighthouse.test")!

    @Test func addressesAreNormalized() throws {
        #expect(try Client.serverURL(from: " lighthouse.test/ ").absoluteString == "https://lighthouse.test")
        #expect(try Client.serverURL(from: "http://192.168.1.2:8080").absoluteString == "http://192.168.1.2:8080")
        #expect(throws: ClientError.invalidAddress) { try Client.serverURL(from: "ftp://x") }
        #expect(throws: ClientError.invalidAddress) { try Client.serverURL(from: "") }
    }

    @Test func serverDatesParseWithAnyPrecision() {
        #expect(ServerDate.parse("2026-11-06T10:00:00Z") != nil)
        #expect(ServerDate.parse("2026-11-06T10:00:00.5Z") != nil)
        #expect(ServerDate.parse("2026-11-06T10:00:00.409874123Z") != nil)
        #expect(ServerDate.parse("nonsense") == nil)
    }

    @Test func approvalsDecodeAndSendTheToken() async throws {
        let session = FakeServer.session(["GET /approvals": (200, approvalJSON)])
        let client = Client(baseURL: url, token: "lht_x", session: session)
        let list = try await client.approvals()
        #expect(list.first?.tool == "mail.send")
        #expect(list.first?.quotesExternal == true)
        #expect(list.first?.input.pretty.contains("\"to\" : \"a\"") == true)
        let request = FakeServer.seen.first
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer lht_x")
        #expect(request?.url?.query() == "status=pending")
    }

    @Test func serverErrorsKeepTheirMessage() async {
        let session = FakeServer.session(["POST /auth/login": (401, #"{"error":"wrong password"}"#)])
        let client = Client(baseURL: url, token: nil, session: session)
        await #expect(throws: ClientError.server(status: 401, message: "wrong password")) {
            _ = try await client.login(password: "x", device: "d", kind: "ios")
        }
    }

    @Test func unreadableAnswersAreReported() async {
        let session = FakeServer.session(["GET /approvals": (200, "{}")])
        let client = Client(baseURL: url, token: "t", session: session)
        await #expect(throws: ClientError.unreadableAnswer) { _ = try await client.approvals() }
    }
}

@Suite @MainActor struct AppModelTests {
    func model(_ routes: [String: (Int, String)], store: MemoryStore) -> AppModel {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://lighthouse.test", forKey: "server-address")
        return AppModel(
            store: store, defaults: defaults, session: FakeServer.session(routes),
            deviceName: "test", deviceKind: "ios")
    }

    @Test func withoutATokenTheAppAsksForASignIn() {
        #expect(model([:], store: MemoryStore()).phase == .signedOut)
        #expect(model([:], store: MemoryStore("t")).phase == .ready)
    }

    @Test func signingInStoresTheTokenAndLoads() async {
        let store = MemoryStore()
        let routes = [
            "POST /auth/login": (200, #"{"id":"019a0000-0000-7000-8000-000000000001","token":"lht_x"}"#),
            "GET /approvals": (200, approvalJSON),
        ]
        let model = model(routes, store: store)
        await model.signIn(address: "lighthouse.test", password: "secret")
        #expect(model.phase == .ready)
        #expect(store.token == "lht_x")
        #expect(model.pendingCount == 1)
    }

    @Test func aFailedSignInShowsTheReason() async {
        let store = MemoryStore()
        let routes = ["POST /auth/login": (401, #"{"error":"wrong password"}"#)]
        let model = model(routes, store: store)
        await model.signIn(address: "lighthouse.test", password: "x")
        #expect(model.phase == .signedOut)
        #expect(model.lastError == "wrong password")
        #expect(store.token == nil)
    }

    @Test func aRevokedTokenSignsOut() async {
        let store = MemoryStore("old")
        let model = model(["GET /approvals": (401, #"{"error":"sign-in required"}"#)], store: store)
        await model.refresh()
        #expect(model.phase == .signedOut)
        #expect(store.token == nil)
    }

    @Test func aDecisionLeavesTheList() async {
        let id = "019a0000-0000-7000-8000-000000000001"
        var routes = ["GET /approvals": (200, approvalJSON)]
        let model = model(routes, store: MemoryStore("t"))
        await model.refresh()
        let approval = model.approvals[0]
        routes["GET /approvals"] = (200, "[]")
        routes["POST /approvals/\(id)/decision"] = (200, "{}")
        FakeServer.routes = routes
        await model.decide(approval, approve: true)
        #expect(model.approvals.isEmpty)
        #expect(FakeServer.seen.contains { $0.url?.path() == "/approvals/\(id)/decision" })
    }

    @Test func aConflictKeepsTheErrorVisible() async {
        let id = "019a0000-0000-7000-8000-000000000001"
        let routes = [
            "GET /approvals": (200, approvalJSON),
            "POST /approvals/\(id)/decision": (409, #"{"error":"the proposal is no longer open"}"#),
        ]
        let model = model(routes, store: MemoryStore("t"))
        await model.refresh()
        await model.decide(model.approvals[0], approve: true)
        #expect(model.approvals.count == 1)
        #expect(model.lastError == "the proposal is no longer open")
    }

    @Test func aRecoveredConnectionClearsItsError() async {
        var routes = ["GET /approvals": (500, #"{"error":"internal error"}"#)]
        let model = model(routes, store: MemoryStore("t"))
        await model.refresh()
        #expect(model.lastError == "internal error")
        routes["GET /approvals"] = (200, "[]")
        FakeServer.routes = routes
        await model.refresh()
        #expect(model.lastError == nil)
    }
}
}
