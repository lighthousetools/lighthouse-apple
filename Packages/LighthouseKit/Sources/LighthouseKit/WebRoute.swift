import Foundation

/// The views of the web app, in the order of its navigation.
public enum WebArea: String, CaseIterable, Sendable {
    case ready, tasks, brief, recap, sessions, alerts, brain, automations, agents, log
    case connections, rules, me, settings

    /// Older names that links and notifications may still use.
    static let aliases: [String: WebArea] = [
        "today": .ready, "approvals": .ready, "weekly": .recap, "claude": .sessions,
    ]

    /// The English name in the web app's navigation, translated with `tr`.
    public var title: String {
        switch self {
        case .ready: "Ready for you"
        case .tasks: "Tasks"
        case .brief: "Morning brief"
        case .recap: "Weekly recap"
        case .sessions: "Claude Code"
        case .alerts: "Alerts"
        case .brain: "Brain"
        case .automations: "Automations"
        case .agents: "Agents"
        case .log: "Log"
        case .connections: "Connections"
        case .rules: "Rules"
        case .me: "What I know about you"
        case .settings: "Settings"
        }
    }
}

/// A place in the web app. The web app routes with the URL hash, `#view/param`,
/// because paths like `/agents` belong to the API on the same origin.
public struct WebRoute: Equatable, Hashable, Sendable {
    public let area: WebArea
    public let param: String?

    public init(_ area: WebArea, param: String? = nil) {
        self.area = area
        let trimmed = param?.trimmingCharacters(in: .whitespaces)
        self.param = trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Reads a hash the way the web app does: everything after the first slash
    /// is the parameter, old names lead to their new place, unknown views to
    /// the ready feed.
    public init(hash: String) {
        var text = Substring(hash)
        if text.hasPrefix("#") { text = text.dropFirst() }
        if text.hasPrefix("/") { text = text.dropFirst() }
        let view: Substring
        var param: String?
        if let slash = text.firstIndex(of: "/") {
            view = text[..<slash]
            let rest = String(text[text.index(after: slash)...])
            param = rest.removingPercentEncoding ?? rest
        } else {
            view = text
        }
        guard let area = WebArea(rawValue: String(view)) ?? WebArea.aliases[String(view)] else {
            self.init(.ready)
            return
        }
        self.init(area, param: param)
    }

    /// Characters `encodeURIComponent` leaves as they are.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    /// The hash for `location.hash`, with the leading `#`.
    public var hash: String {
        guard let param else { return "#\(area.rawValue)" }
        return "#\(area.rawValue)/\(param.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? param)"
    }

    /// The route behind ⌘1 to ⌘9: the first nine entries of the web app's navigation.
    public static func shortcut(_ number: Int) -> WebRoute? {
        guard (1...9).contains(number) else { return nil }
        return WebRoute(WebArea.allCases[number - 1])
    }

    /// An item of the ready feed, keyed the way the web app keys it.
    public static func readyItem(kind: String, id: String) -> WebRoute {
        WebRoute(.ready, param: "\(kind):\(id)")
    }

    /// Where a pending approval is decided.
    public static func approval(_ id: UUID) -> WebRoute {
        readyItem(kind: "approval", id: id.uuidString.lowercased())
    }

    /// Where a permission request of a Claude Code session is decided.
    public static func permission(_ id: UUID) -> WebRoute {
        readyItem(kind: "permission", id: id.uuidString.lowercased())
    }

    public static func alert(_ id: UUID) -> WebRoute {
        WebRoute(.alerts, param: id.uuidString.lowercased())
    }

    public static func task(_ id: UUID) -> WebRoute {
        WebRoute(.tasks, param: id.uuidString.lowercased())
    }

    /// The full address of this route on a server.
    public func url(on server: URL) -> URL {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false) ?? URLComponents()
        if components.path.isEmpty { components.path = "/" }
        components.fragment = nil
        let base = components.url ?? server
        return URL(string: base.absoluteString + hash) ?? base
    }
}
