import Foundation
import Testing

@testable import LighthouseKit

extension ServerTests {
    @Suite @MainActor struct TenancyModelTests {
        let server = "https://lighthouse.test"
        var home: TokenKey { TokenKey(server: server, user: UUID(uuidString: userID), tenant: UUID(uuidString: homeTenant)) }
        var team: TokenKey { TokenKey(server: server, user: UUID(uuidString: userID), tenant: UUID(uuidString: teamTenant)) }

        func model(
            _ routes: [String: (Int, String)], store: MemoryStore, signedIn: TokenKey? = nil,
            defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!
        ) -> AppModel {
            defaults.set(server, forKey: "server-address")
            defaults.set("en", forKey: "language")
            if let signedIn { defaults.set(signedIn.account, forKey: "token-key") }
            return AppModel(
                store: store, defaults: defaults, session: FakeServer.session(routes),
                deviceName: "Mac", deviceKind: "mac")
        }

        /// A token per key, answered by the fake server with the matching tenant.
        var signedInRoutes: [String: (Int, String)] {
            ["GET /me": (200, meJSON()), "GET /tenants": (200, tenantsJSON)]
        }

        @Test func signingInWithAnEmailStoresTheTokenUnderUserAndTenant() async {
            let store = MemoryStore()
            var routes = signedInRoutes
            routes["POST /auth/login"] = (200, issued("lht_home"))
            let model = model(routes, store: store)
            await model.signIn(address: "lighthouse.test", email: "alex@example.com", password: "a long password")
            #expect(model.phase == .ready)
            #expect(store.tokens == [home: "lht_home"])
            #expect(model.me?.email == "alex@example.com")
            #expect(model.tenantName == "Home")
            #expect(model.role == .owner)
            #expect(model.tenants.count == 2)
            #expect(model.currentTenant?.tenantName == "Home")
            let login = FakeServer.seen.first { $0.url?.path() == "/auth/login" }
            #expect(body(of: login)["email"] as? String == "alex@example.com")
            #expect(body(of: login)["device_name"] as? String == "Mac")
            #expect(model.lastEmail == "alex@example.com")
        }

        @Test func aMissingEmailOnAServerWithSeveralUsersSaysSo() async {
            let routes = ["POST /auth/login": (400, #"{"error":"email required"}"#)]
            let model = model(routes, store: MemoryStore())
            await model.signIn(address: "lighthouse.test", password: "a long password")
            #expect(model.phase == .signedOut)
            #expect(model.lastError == "This server has several users. Enter your email address.")
        }

        @Test func theSignInRemembersItsKeyAcrossLaunches() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home", team: "lht_team"]
            let model = model(signedInRoutes, store: store, signedIn: team)
            #expect(model.phase == .ready)
            #expect(model.webToken == "lht_team")
        }

        @Test func aTokenOfAnOlderBuildMovesUnderItsUserAndTenant() async {
            let store = MemoryStore("lht_old")
            let model = model(signedInRoutes, store: store)
            #expect(model.phase == .ready)
            #expect(store.legacy == nil)
            #expect(store.tokens == [TokenKey(server: server): "lht_old"])
            await model.refresh()
            #expect(store.tokens == [home: "lht_old"])
        }

        @Test func aServerBefore02KeepsWorkingAsTheOwner() async {
            let store = MemoryStore("lht_old")
            let model = model(["GET /me": (200, #"{"name":"Alex"}"#), "GET /tenants": (404, "{}")], store: store)
            await model.refresh()
            #expect(model.phase == .ready)
            #expect(model.tenants.isEmpty)
            #expect(model.canAdminister)
            #expect(store.tokens == [TokenKey(server: server): "lht_old"])
        }

        @Test func switchingAsksTheServerForATokenAndKeepsBoth() async throws {
            let store = MemoryStore()
            store.tokens = [home: "lht_home"]
            var routes = signedInRoutes
            routes["POST /tenants/\(teamTenant)/switch"] = (200, issued("lht_team", tenant: teamTenant))
            let model = model(routes, store: store, signedIn: home)
            await model.refresh()
            let before = model.sessionID
            FakeServer.routes["GET /me"] = (200, meJSON(tenant: teamTenant, name: "Team", role: "member"))
            await model.switchTenant(to: try #require(model.tenants.last))
            #expect(store.tokens == [home: "lht_home", team: "lht_team"])
            #expect(model.webToken == "lht_team")
            #expect(model.tenantName == "Team")
            #expect(model.role == .member)
            #expect(!model.canAdminister)
            #expect(model.sessionID != before)
            let switched = FakeServer.seen.first { $0.url?.path() == "/tenants/\(teamTenant)/switch" }
            #expect(switched?.value(forHTTPHeaderField: "Authorization") == "Bearer lht_home")
        }

        @Test func switchingBackReusesTheKeptToken() async throws {
            let store = MemoryStore()
            store.tokens = [home: "lht_home", team: "lht_team"]
            let model = model(signedInRoutes, store: store, signedIn: team)
            FakeServer.routes["GET /me"] = (200, meJSON(tenant: teamTenant, name: "Team"))
            await model.refresh()
            FakeServer.routes["GET /me"] = (200, meJSON())
            await model.switchTenant(to: try #require(model.tenants.first))
            #expect(model.webToken == "lht_home")
            #expect(!FakeServer.seen.contains { $0.url?.path().hasSuffix("/switch") == true })
        }

        @Test func aRevokedKeptTokenIsReplaced() async throws {
            let store = MemoryStore()
            store.tokens = [home: "lht_home", team: "lht_gone"]
            var routes = signedInRoutes
            routes["POST /tenants/\(teamTenant)/switch"] = (200, issued("lht_team", tenant: teamTenant))
            let model = model(routes, store: store, signedIn: home)
            await model.refresh()
            // The kept token is refused, the new one answers for the team.
            FakeServer.routes["GET /me Bearer lht_gone"] = (401, #"{"error":"sign-in required"}"#)
            FakeServer.routes["GET /me Bearer lht_team"] = (200, meJSON(tenant: teamTenant, name: "Team"))
            let target = try #require(model.tenants.last)
            await model.switchTenant(to: target)
            #expect(store.tokens[team] == "lht_team")
            #expect(model.webToken == "lht_team")
            #expect(model.tenantName == "Team")
        }

        @Test func signingOutRevokesTheTokensOfEveryTenant() async {
            let store = MemoryStore()
            let stranger = TokenKey(server: server, user: UUID(), tenant: UUID())
            store.tokens = [home: "lht_home", team: "lht_team", stranger: "lht_other"]
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let model = model(["POST /auth/logout": (204, "")], store: store, signedIn: home, defaults: defaults)
            await model.signOut()
            #expect(model.phase == .signedOut)
            #expect(store.tokens == [stranger: "lht_other"])
            let revoked = FakeServer.seen.filter { $0.url?.path() == "/auth/logout" }
                .compactMap { $0.value(forHTTPHeaderField: "Authorization") }
            #expect(Set(revoked) == ["Bearer lht_home", "Bearer lht_team"])
            #expect(defaults.string(forKey: "token-key") == nil)
            #expect(model.lastError == nil)
        }

        @Test func aRefusedTokenSignsOutAndSaysWhy() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home", team: "lht_team"]
            let model = model(["GET /approvals": (401, #"{"error":"sign-in required"}"#)], store: store, signedIn: home)
            await model.refresh()
            #expect(model.phase == .signedOut)
            #expect(model.lastError == "Your sign-in has ended. Please sign in again.")
            #expect(store.tokens == [team: "lht_team"])
        }

        @Test func aForbiddenActionShowsTheReasonAndStaysSignedIn() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home"]
            var routes = signedInRoutes
            routes["POST /agents/mailer/run"] = (403, #"{"error":"owner or admin role required"}"#)
            routes["GET /agents"] = (
                200,
                #"[{"id":"mailer","name":"Mailer","schedule":null,"next_run":null,"tools":[],"blocked":[]}]"#
            )
            let model = model(routes, store: store, signedIn: home)
            await model.refresh()
            guard let agent = model.agents.first else {
                Issue.record("the agent did not load: \(model.lastError ?? "")")
                return
            }
            await model.run(agent)
            #expect(model.phase == .ready)
            #expect(model.lastError == "owner or admin role required")
        }

        @Test func aTokenTheWebAppGotIsAdoptedOnceConfirmed() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home"]
            let model = model(signedInRoutes, store: store, signedIn: home)
            await model.refresh()
            FakeServer.routes["GET /me"] = (200, meJSON(tenant: teamTenant, name: "Team"))
            await model.adoptWebToken("lht_team")
            #expect(model.webToken == "lht_team")
            #expect(store.tokens == [home: "lht_home", team: "lht_team"])
            #expect(model.tenantName == "Team")
        }

        @Test func aRefusedTokenIsReplacedByTheOneTheWebAppSwitchedTo() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home"]
            var routes = signedInRoutes
            routes["GET /approvals Bearer lht_home"] = (401, #"{"error":"sign-in required"}"#)
            routes["GET /me Bearer lht_home"] = (401, #"{"error":"sign-in required"}"#)
            routes["GET /me Bearer lht_team"] = (200, meJSON(tenant: teamTenant, name: "Team"))
            let model = model(routes, store: store, signedIn: home)
            model.currentWebToken = { "lht_team" }
            await model.refresh()
            #expect(model.phase == .ready)
            #expect(model.webToken == "lht_team")
            #expect(model.tenantName == "Team")
            #expect(model.lastError == nil)
        }

        @Test func aTokenTheServerRefusesIsNotAdopted() async {
            let store = MemoryStore()
            store.tokens = [home: "lht_home"]
            let model = model(signedInRoutes, store: store, signedIn: home)
            await model.refresh()
            FakeServer.routes["GET /me"] = (401, #"{"error":"sign-in required"}"#)
            await model.adoptWebToken("lht_forged")
            #expect(model.webToken == "lht_home")
            #expect(store.tokens == [home: "lht_home"])
        }

        @Test func theStatusOfAServerTellsWhatTheSignInNeeds() async {
            let routes = ["GET /auth/status": (200, #"{"setup_required":false,"signup":"open","email_required":true}"#)]
            let model = model(routes, store: MemoryStore())
            let status = await model.status(of: "lighthouse.test")
            #expect(status?.emailRequired == true)
            #expect(status?.signup == .open)
            #expect(await model.status(of: "ftp://nope") == nil)
        }

        @Test func theDeviceNameCanBeChangedAndIsKept() {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let first = model([:], store: MemoryStore(), defaults: defaults)
            #expect(first.deviceName == "Mac")
            first.deviceName = "Studio"
            #expect(model([:], store: MemoryStore(), defaults: defaults).deviceName == "Studio")
        }
    }
}
