import Foundation

/// The views of the web app, in the order of its sidebar.
public enum WebArea: String, CaseIterable, Sendable {
    case today, approvals, sessions, agents, brain, weekly, log, settings
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

    /// Reads a hash the way the web app does: unknown views mean today.
    public init(hash: String) {
        var text = Substring(hash)
        if text.hasPrefix("#") { text = text.dropFirst() }
        let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let view = parts.first.map(String.init) ?? ""
        guard let area = WebArea(rawValue: view) else {
            self.init(.today)
            return
        }
        let param = parts.count > 1 ? parts[1].split(separator: "/").first.map(String.init) : nil
        self.init(area, param: param?.removingPercentEncoding ?? param)
    }

    /// The hash for `location.hash`, with the leading `#`.
    public var hash: String {
        guard let param else { return "#\(area.rawValue)" }
        let allowed = CharacterSet.urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "/#"))
        return "#\(area.rawValue)/\(param.addingPercentEncoding(withAllowedCharacters: allowed) ?? param)"
    }

    /// The route behind ⌘1 to ⌘9, by the web app's sidebar order.
    public static func shortcut(_ number: Int) -> WebRoute? {
        let areas = WebArea.allCases
        guard (1...areas.count).contains(number) else { return nil }
        return WebRoute(areas[number - 1])
    }

    /// Where a pending approval is decided.
    public static func approval(_ id: UUID) -> WebRoute {
        WebRoute(.approvals, param: id.uuidString.lowercased())
    }

    /// Where a permission request of a Claude Code session is decided.
    public static func permission(_ id: UUID) -> WebRoute {
        WebRoute(.approvals, param: id.uuidString.lowercased())
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
