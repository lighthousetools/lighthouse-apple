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
                    route: WebRoute(.approvals, param: "abc"), id: "a1"))
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
        #expect(WebRoute(hash: "#approvals/123") == WebRoute(.approvals, param: "123"))
        #expect(WebRoute(hash: "brain") == WebRoute(.brain))
        #expect(WebRoute(hash: "") == WebRoute(.today))
        #expect(WebRoute(hash: "#nothing/1") == WebRoute(.today))
        #expect(WebRoute(hash: "#brain/") == WebRoute(.brain))
        #expect(WebRoute(hash: "#brain/a/b") == WebRoute(.brain, param: "a"))
    }

    @Test func routesWriteHashes() {
        #expect(WebRoute(.settings).hash == "#settings")
        #expect(WebRoute(.brain, param: "a b").hash == "#brain/a%20b")
        #expect(WebRoute(hash: WebRoute(.brain, param: "a b").hash) == WebRoute(.brain, param: "a b"))
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(WebRoute.approval(id).hash == "#approvals/6f9619ff-8b86-d011-b42d-00c04fc964ff")
    }

    @Test func shortcutsFollowTheSidebar() {
        #expect(WebRoute.shortcut(1) == WebRoute(.today))
        #expect(WebRoute.shortcut(2) == WebRoute(.approvals))
        #expect(WebRoute.shortcut(5) == WebRoute(.brain))
        #expect(WebRoute.shortcut(8) == WebRoute(.settings))
        #expect(WebRoute.shortcut(9) == nil)
        #expect(WebRoute.shortcut(0) == nil)
    }

    @Test func routesBecomeAddresses() {
        let server = URL(string: "https://lighthouse.example.com")!
        #expect(WebRoute(.agents).url(on: server).absoluteString == "https://lighthouse.example.com/#agents")
        let local = URL(string: "http://127.0.0.1:8080/")!
        #expect(WebRoute(.today).url(on: local).absoluteString == "http://127.0.0.1:8080/#today")
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
    private func approval(_ id: UUID) throws -> Approval {
        let json = """
            {"id":"\(id.uuidString)","agent_id":"mail-triage","tool":"send_mail","input":{},
             "quotes_external":false,"reason":null,"consulted":[],"status":"pending",
             "expires_at":"2026-01-01T00:00:00Z"}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Approval.self, from: Data(json.utf8))
    }

    @Test func onlyNewRequestsAreAnnounced() throws {
        var tracker = RequestTracker()
        let first = try approval(UUID())
        #expect(tracker.notices(approvals: [first], permissions: []).isEmpty)
        #expect(tracker.notices(approvals: [first], permissions: []).isEmpty)
        let second = try approval(UUID())
        let notices = tracker.notices(approvals: [first, second], permissions: [])
        #expect(notices.count == 1)
        #expect(notices.first?.route == .approval(second.id))
        #expect(notices.first?.body.contains("Mail triage") == true)
        #expect(notices.first?.body.contains("Send mail") == true)
        #expect(tracker.notices(approvals: [], permissions: []).isEmpty)
        #expect(tracker.notices(approvals: [first], permissions: []).count == 1)
    }
}
