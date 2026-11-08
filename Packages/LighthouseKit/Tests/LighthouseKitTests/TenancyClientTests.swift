import Foundation
import Testing

@testable import LighthouseKit

let userID = "019a0000-0000-7000-8000-0000000000a1"
let homeTenant = "019a0000-0000-7000-8000-0000000000b1"
let teamTenant = "019a0000-0000-7000-8000-0000000000b2"

func issued(_ token: String, tenant: String = homeTenant) -> String {
    #"{"id":"019a0000-0000-7000-8000-000000000001","token":"\#(token)","tenant_id":"\#(tenant)","user_id":"\#(userID)"}"#
}

func meJSON(tenant: String = homeTenant, name: String = "Home", role: String = "owner") -> String {
    """
    {"name":"Alex","timezone":"Europe/Berlin","user_id":"\(userID)","email":"alex@example.com",
    "email_verified":true,"tenant_id":"\(tenant)","tenant_name":"\(name)","role":"\(role)"}
    """
}

let tenantsJSON = """
    [{"tenant_id":"\(homeTenant)","tenant_name":"Home","role":"owner","joined_at":"2026-11-01T10:00:00Z"},
    {"tenant_id":"\(teamTenant)","tenant_name":"Team","role":"member","joined_at":"2026-11-02T10:00:00Z"}]
    """

func body(of request: URLRequest?) -> [String: Any] {
    guard let request else { return [:] }
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            bytes.append(buffer, count: count)
        }
        data = bytes
    }
    guard let data else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

extension ServerTests {
    @Suite struct TenancyClientTests {
        let url = URL(string: "https://lighthouse.test")!

        @Test func authStatusOfAnOlderServerMeansASingleUser() async throws {
            let session = FakeServer.session(["GET /auth/status": (200, #"{"setup_required":false}"#)])
            let status = try await Client(baseURL: url, token: nil, session: session).authStatus()
            #expect(status == AuthStatus(setupRequired: false, signup: .closed, emailRequired: false))
        }

        @Test func authStatusTellsTheSignupModeAndWhetherAnEmailIsNeeded() async throws {
            let session = FakeServer.session([
                "GET /auth/status": (200, #"{"setup_required":false,"signup":"invite","email_required":true}"#)
            ])
            let status = try await Client(baseURL: url, token: nil, session: session).authStatus()
            #expect(status.signup == .invite)
            #expect(status.emailRequired)
        }

        @Test func loginSendsTheEmailAndTenantOnlyWhenGiven() async throws {
            let session = FakeServer.session(["POST /auth/login": (200, issued("lht_a"))])
            let client = Client(baseURL: url, token: nil, session: session)
            let first = try await client.login(password: "secret", device: "Mac", kind: "mac")
            #expect(first.tenantId == UUID(uuidString: homeTenant))
            #expect(first.userId == UUID(uuidString: userID))
            let plain = body(of: FakeServer.seen.last)
            #expect(plain["email"] == nil)
            #expect(plain["tenant_id"] == nil)
            #expect(plain["device_kind"] as? String == "mac")

            let tenant = try #require(UUID(uuidString: teamTenant))
            _ = try await client.login(
                email: " alex@example.com ", password: "secret", device: "Mac", kind: "mac", tenant: tenant)
            let full = body(of: FakeServer.seen.last)
            #expect(full["email"] as? String == "alex@example.com")
            #expect(full["tenant_id"] as? String == teamTenant)
        }

        @Test func anOlderTokenAnswerStillDecodes() async throws {
            let session = FakeServer.session([
                "POST /auth/login": (200, #"{"id":"019a0000-0000-7000-8000-000000000001","token":"lht_x"}"#)
            ])
            let issued = try await Client(baseURL: url, token: nil, session: session)
                .login(password: "x", device: "d", kind: "ios")
            #expect(issued.token == "lht_x")
            #expect(issued.tenantId == nil)
        }

        @Test func meCarriesTheUserTenantAndRole() async throws {
            let session = FakeServer.session(["GET /me": (200, meJSON(role: "member"))])
            let me = try await Client(baseURL: url, token: "t", session: session).me()
            #expect(me.email == "alex@example.com")
            #expect(me.tenantName == "Home")
            #expect(me.role == .member)
            #expect(me.role?.canAdminister == false)
        }

        @Test func unknownRolesDoNotBreakTheAnswer() async throws {
            let session = FakeServer.session(["GET /me": (200, meJSON(role: "auditor"))])
            let me = try await Client(baseURL: url, token: "t", session: session).me()
            #expect(me.role == nil)
            #expect(me.tenantId == UUID(uuidString: homeTenant))
        }

        @Test func tenantsListTheMemberships() async throws {
            let session = FakeServer.session(["GET /tenants": (200, tenantsJSON)])
            let tenants = try await Client(baseURL: url, token: "t", session: session).tenants()
            #expect(tenants.map(\.tenantName) == ["Home", "Team"])
            #expect(tenants.map(\.role) == [.owner, .member])
        }

        @Test func switchingAsksForATokenOfTheOtherTenant() async throws {
            let session = FakeServer.session(["POST /tenants/\(teamTenant)/switch": (200, issued("lht_b", tenant: teamTenant))])
            let client = Client(baseURL: url, token: "lht_a", session: session)
            let tenant = try #require(UUID(uuidString: teamTenant))
            let answer = try await client.switchTenant(to: tenant, device: "Mac", kind: "mac")
            #expect(answer.token == "lht_b")
            #expect(answer.tenantId == tenant)
            let request = FakeServer.seen.last
            #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer lht_a")
            #expect(body(of: request)["device_name"] as? String == "Mac")
        }

        @Test func aRefusedRoleIsForbiddenWithTheServersReason() async {
            let session = FakeServer.session([
                "POST /tasks": (403, #"{"error":"owner or admin role required"}"#)
            ])
            let client = Client(baseURL: url, token: "t", session: session)
            await #expect(throws: ClientError.forbidden("owner or admin role required")) {
                _ = try await client.createTask(title: "x")
            }
        }

        @Test func a403WithoutATokenStaysAServerError() async {
            let session = FakeServer.session(["POST /auth/login": (403, #"{"error":"held"}"#)])
            let client = Client(baseURL: url, token: nil, session: session)
            await #expect(throws: ClientError.server(status: 403, message: "held")) {
                _ = try await client.login(password: "x", device: "d", kind: "mac")
            }
        }
    }
}
