import Foundation
import Testing

@testable import LighthouseKit

struct BridgeTests {
    @Test func notificationsAreReadAndTrimmed() throws {
        let message = try BridgeMessage.parse([
            "type": "notify", "title": "  Approval needed ", "body": "Send the mail?",
            "route": "#approvals/abc", "id": "a1",
        ])
        #expect(
            message
                == .notify(
                    title: "Approval needed", body: "Send the mail?",
                    route: WebRoute(.ready, param: "abc"), id: "a1"))
        let long = try BridgeMessage.parse(["type": "notify", "title": String(repeating: "x", count: 500)])
        guard case .notify(let title, let body, let route, let id) = long else {
            Issue.record("not a notification")
            return
        }
        #expect(title.count == 200)
        #expect(body.isEmpty && route == nil && id == nil)
    }

    @Test func notificationsNeedATitle() {
        #expect(throws: BridgeError.missing("title")) { try BridgeMessage.parse(["type": "notify"]) }
        #expect(throws: BridgeError.missing("title")) {
            try BridgeMessage.parse(["type": "notify", "title": "   "])
        }
    }

    @Test func badgesAcceptWholeNumbersOnly() throws {
        #expect(try BridgeMessage.parse(["type": "badge", "count": 3]) == .badge(3))
        #expect(try BridgeMessage.parse(["type": "badge", "count": 4.0]) == .badge(4))
        #expect(try BridgeMessage.parse(["type": "badge", "count": -2]) == .badge(0))
        #expect(try BridgeMessage.parse(["type": "badge", "count": 1_000_000]) == .badge(9999))
        #expect(throws: BridgeError.invalid("count")) {
            try BridgeMessage.parse(["type": "badge", "count": 1.5])
        }
        #expect(throws: BridgeError.invalid("count")) {
            try BridgeMessage.parse(["type": "badge", "count": "3"])
        }
        #expect(throws: BridgeError.invalid("count")) {
            try BridgeMessage.parse(["type": "badge", "count": true])
        }
        #expect(throws: BridgeError.missing("count")) { try BridgeMessage.parse(["type": "badge"]) }
    }

    @Test func externalLinksAreLimitedToTheWebAndMail() throws {
        #expect(
            try BridgeMessage.parse(["type": "openExternal", "url": "https://example.com/a?b=1"])
                == .openExternal(URL(string: "https://example.com/a?b=1")!))
        #expect(
            try BridgeMessage.parse(["type": "openExternal", "url": "mailto:someone@example.com"])
                == .openExternal(URL(string: "mailto:someone@example.com")!))
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "https://", "nonsense"] {
            #expect(throws: BridgeError.invalid("url"), "\(bad)") {
                try BridgeMessage.parse(["type": "openExternal", "url": bad])
            }
        }
    }

    @Test func unknownAndMalformedMessagesAreRefused() {
        #expect(throws: BridgeError.notAnObject) { try BridgeMessage.parse("notify") }
        #expect(throws: BridgeError.missing("type")) { try BridgeMessage.parse(["title": "x"]) }
        #expect(throws: BridgeError.unknownType("navigate")) {
            try BridgeMessage.parse(["type": "navigate", "url": "https://example.com"])
        }
        #expect(throws: BridgeError.unsupportedVersion(2)) {
            try BridgeMessage.parse(["type": "badge", "count": 1, "v": 2])
        }
    }

    @Test func readyTellsTheVersion() throws {
        #expect(try BridgeMessage.parse(["type": "ready"]) == .ready(version: 1))
        #expect(try BridgeMessage.parse(["type": "ready", "v": 1]) == .ready(version: 1))
    }

    @Test func shellMessagesAreRead() throws {
        #expect(
            try ShellMessage.parse(["type": "route", "hash": "#brain/42"])
                == .route(WebRoute(.brain, param: "42")))
        #expect(try ShellMessage.parse(["type": "dragZone", "active": true]) == .dragZone(true))
        #expect(try ShellMessage.parse(["type": "signedOut"]) == .signedOut)
        #expect(try ShellMessage.parse(["type": "language", "value": "de"]) == .language(.german))
        #expect(throws: BridgeError.invalid("value")) {
            try ShellMessage.parse(["type": "language", "value": "fr"])
        }
    }

    @Test func theWebViewStaysOnTheServer() {
        let server = URL(string: "https://lighthouse.example.com")!
        let decide = { (text: String, main: Bool) in
            NavigationPolicy.decide(URL(string: text)!, server: server, isMainFrame: main)
        }
        #expect(decide("https://lighthouse.example.com/#approvals", true) == .allow)
        #expect(decide("https://lighthouse.example.com:443/", true) == .allow)
        #expect(decide("http://lighthouse.example.com/", true) == .openExternally)
        #expect(decide("https://lighthouse.example.com:8443/", true) == .openExternally)
        #expect(decide("https://evil.example.com/", true) == .openExternally)
        #expect(decide("https://lighthouse.example.com.evil.com/", true) == .openExternally)
        #expect(decide("mailto:a@example.com", true) == .openExternally)
        #expect(decide("about:blank", true) == .allow)
        #expect(decide("blob:https://lighthouse.example.com/1234", false) == .allow)
        #expect(decide("blob:https://lighthouse.example.com/1234", true) == .cancel)
        #expect(decide("data:text/html,hi", true) == .cancel)
        #expect(decide("file:///etc/hosts", true) == .cancel)
        #expect(decide("javascript:alert(1)", false) == .cancel)
    }

    @Test func originsMatchWhatThePageShows() {
        #expect(NavigationPolicy.origin(of: URL(string: "https://Example.com/x")!) == "https://example.com")
        #expect(NavigationPolicy.origin(of: URL(string: "http://127.0.0.1:8080")!) == "http://127.0.0.1:8080")
        #expect(NavigationPolicy.origin(of: URL(string: "http://host:80/")!) == "http://host")
    }
}

struct WebRouteTests {
    @Test func hashesAreReadLikeTheWebApp() {
        #expect(WebRoute(hash: "#tasks/123") == WebRoute(.tasks, param: "123"))
        #expect(WebRoute(hash: "brain") == WebRoute(.brain))
        #expect(WebRoute(hash: "#/alerts") == WebRoute(.alerts))
        #expect(WebRoute(hash: "") == WebRoute(.ready))
        #expect(WebRoute(hash: "#nothing/1") == WebRoute(.ready))
        #expect(WebRoute(hash: "#brain/") == WebRoute(.brain))
        #expect(WebRoute(hash: "#brain/a/b") == WebRoute(.brain, param: "a/b"))
        #expect(WebRoute(hash: "#ready/approval%3Aabc") == WebRoute(.ready, param: "approval:abc"))
    }

    @Test func oldNamesLeadToTheirNewPlace() {
        #expect(WebRoute(hash: "#today") == WebRoute(.ready))
        #expect(WebRoute(hash: "#approvals/abc") == WebRoute(.ready, param: "abc"))
        #expect(WebRoute(hash: "#weekly") == WebRoute(.recap))
        #expect(WebRoute(hash: "#claude") == WebRoute(.sessions))
    }

    @Test func routesWriteHashesLikeEncodeURIComponent() {
        #expect(WebRoute(.settings).hash == "#settings")
        #expect(WebRoute(.brain, param: "a b/c").hash == "#brain/a%20b%2Fc")
        #expect(WebRoute(hash: WebRoute(.brain, param: "a b/c").hash) == WebRoute(.brain, param: "a b/c"))
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(WebRoute.approval(id).hash == "#ready/approval%3A6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(WebRoute.permission(id) == WebRoute(.ready, param: "permission:6f9619ff-8b86-d011-b42d-00c04fc964ff"))
        #expect(WebRoute.alert(id).hash == "#alerts/6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(WebRoute.task(id).hash == "#tasks/6f9619ff-8b86-d011-b42d-00c04fc964ff")
    }

    @Test func shortcutsFollowTheFirstNineNavigationEntries() {
        let expected: [WebArea] = [.ready, .tasks, .brief, .recap, .sessions, .alerts, .brain, .automations, .agents]
        #expect((1...9).compactMap { WebRoute.shortcut($0)?.area } == expected)
        #expect(WebRoute.shortcut(10) == nil)
        #expect(WebRoute.shortcut(0) == nil)
    }

    @Test func routesBecomeAddresses() {
        let server = URL(string: "https://lighthouse.example.com")!
        #expect(WebRoute(.agents).url(on: server).absoluteString == "https://lighthouse.example.com/#agents")
        let local = URL(string: "http://127.0.0.1:8080/")!
        #expect(WebRoute(.ready).url(on: local).absoluteString == "http://127.0.0.1:8080/#ready")
    }
}

struct ShellScriptTests {
    @Test func theTokenIsEmbeddedAsAStringLiteral() {
        let script = ShellScript.documentStart(
            origin: "https://lighthouse.example.com", token: #"a"b\c</script>"#, language: .german)
        #expect(script.contains(#"const token = "a\"b\\c<\/script>";"#))
        #expect(script.contains(#"const origin = "https:\/\/lighthouse.example.com";"#))
        #expect(script.contains(#"if (location.origin !== origin) return;"#))
        #expect(script.contains(#"const language = "de";"#))
    }

    @Test func aMissingTokenStaysNull() {
        let script = ShellScript.documentStart(origin: "http://h", token: nil, language: .english)
        #expect(script.contains("const token = null;"))
    }

    @Test func commandsFallBackToWhatTheWebAppKnows() {
        let palette = ShellScript.command(.palette)
        #expect(palette.contains(#""lighthouse:command""#))
        #expect(palette.contains(#"metaKey: true"#))
        #expect(ShellScript.navigate(WebRoute(.log)) == ##"location.hash = "#log";"##)
    }
}

struct RequestTrackerTests {
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func approval(_ id: UUID) throws -> Approval {
        let json = """
            {"id":"\(id.uuidString)","agent_id":"mail-triage","tool":"send_mail","input":{},
             "quotes_external":false,"reason":null,"consulted":[],"status":"pending",
             "expires_at":"2026-01-01T00:00:00Z"}
            """
        return try Self.decoder.decode(Approval.self, from: Data(json.utf8))
    }

    private func feed(_ items: [(String, String)]) throws -> ReadyFeed {
        let list = items.map { kind, id in
            """
            {"kind":"\(kind)","group":"decisions","id":"\(id)","title":"Send the report","summary":null,
             "agent_id":"mail","created_at":"2026-01-01T00:00:00Z","detail":{}}
            """
        }
        let json = """
            {"total":\(items.count),"counts":{},"groups":{},"alerts":{"critical":0,"warning":0,"info":0},
             "items":[\(list.joined(separator: ","))]}
            """
        return try Self.decoder.decode(ReadyFeed.self, from: Data(json.utf8))
    }

    private func alert(_ id: UUID, severity: String) throws -> Alert {
        let json = """
            {"id":"\(id.uuidString)","kind":"connector","key":"connector:linear","severity":"\(severity)",
             "title":"Linear is not authorized","status":"open","count":1,
             "first_seen_at":"2026-01-01T00:00:00Z","last_seen_at":"2026-01-01T00:00:00Z"}
            """
        return try Self.decoder.decode(Alert.self, from: Data(json.utf8))
    }

    @Test func onlyNewItemsAreAnnounced() throws {
        var tracker = RequestTracker()
        let first = try feed([("approval", "a1")])
        let candidates = { (ready: ReadyFeed) in
            RequestNotice.candidates(ready: ready, approvals: [], permissions: [], alerts: [])
        }
        #expect(tracker.fresh(candidates(first)).isEmpty)
        #expect(tracker.fresh(candidates(first)).isEmpty)
        let notices = tracker.fresh(candidates(try feed([("approval", "a1"), ("task", "t1")])))
        #expect(notices.map(\.key) == ["task:t1"])
        #expect(notices.first?.route == WebRoute(.ready, param: "task:t1"))
        #expect(notices.first?.webAnnounces == true)
        #expect(tracker.fresh(candidates(try feed([]))).isEmpty)
        #expect(tracker.fresh(candidates(first)).count == 1)
    }

    @Test func olderServersAnnounceApprovals() throws {
        let item = try approval(UUID())
        let notices = RequestNotice.candidates(ready: nil, approvals: [item], permissions: [], alerts: [])
        #expect(notices.first?.key == "approval:\(item.id.uuidString.lowercased())")
        #expect(notices.first?.route == .approval(item.id))
        #expect(notices.first?.body.contains("Mail triage") == true)
    }

    @Test func onlyCriticalAlertsAreAnnounced() throws {
        let critical = try alert(UUID(), severity: "critical")
        let warning = try alert(UUID(), severity: "warning")
        let notices = RequestNotice.candidates(
            ready: try feed([]), approvals: [], permissions: [], alerts: [critical, warning])
        #expect(notices.count == 1)
        #expect(notices.first?.route == .alert(critical.id))
        #expect(notices.first?.body == "Linear is not authorized")
        #expect(notices.first?.webAnnounces == false)
    }

    @Test func onlyEventsTheAppsKeepCauseARefresh() {
        for event in ["changed", "ready.changed", "alert.raised", "alerts.changed", "tasks.changed"] {
            #expect(AppModel.refreshes(on: event), "\(event)")
        }
        for event in ["rules.changed", "memory.changed", "automations.changed", "document.created"] {
            #expect(!AppModel.refreshes(on: event), "\(event)")
        }
    }
}

struct QuickEntryTests {
    @Test func theFirstLineIsTheTitle() {
        let entry = QuickEntry(text: "  Call the bank \nabout the card\nsoon  ")
        #expect(entry.title == "Call the bank")
        #expect(entry.body == "about the card\nsoon")
        #expect(QuickEntry(text: "Only a title").body.isEmpty)
        #expect(QuickEntry(text: " \n ").isEmpty)
        #expect(QuickEntry(text: String(repeating: "x", count: 100)).title.count == 80)
    }
}
