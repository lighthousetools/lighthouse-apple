import Foundation

/// The name under which the web app reaches the Mac app:
/// `window.webkit.messageHandlers.lighthouse.postMessage({...})`.
/// `docs/bridge.md` describes the protocol.
public enum Bridge {
    public static let handlerName = "lighthouse"
    /// The handler of the app's own scripts, which run in a separate content world.
    public static let shellHandlerName = "lighthouseShell"
    /// The event the app dispatches on `window` for commands such as the palette.
    public static let commandEvent = "lighthouse:command"
    /// The protocol version the app speaks.
    public static let version = 1

    static let maxTitle = 200
    static let maxBody = 1000
    static let maxBadge = 9999
}

/// Why a message from the web app was refused.
public enum BridgeError: Error, Equatable {
    case notAnObject
    case unknownType(String)
    case missing(String)
    case invalid(String)
    case unsupportedVersion(Int)
}

/// What the web app may ask of the Mac app.
public enum BridgeMessage: Equatable, Sendable {
    /// Shows a native notification. A click opens `route` in the main window.
    case notify(title: String, body: String, route: WebRoute?, id: String?)
    /// Sets the number on the Dock icon. Zero removes it.
    case badge(Int)
    /// Opens a link in the default browser.
    case openExternal(URL)
    /// The web app has adopted the bridge and handles commands itself.
    case ready(version: Int)
    /// The organization the web app shows now, or "" for all of them.
    case org(String)

    /// Reads the body of a script message, which WebKit delivers as a dictionary.
    public static func parse(_ body: Any) throws -> BridgeMessage {
        guard let object = body as? [String: Any] else { throw BridgeError.notAnObject }
        if let version = integer(object["v"]), version > Bridge.version {
            throw BridgeError.unsupportedVersion(version)
        }
        guard let type = object["type"] as? String else { throw BridgeError.missing("type") }
        switch type {
        case "notify":
            guard let title = text(object["title"], limit: Bridge.maxTitle) else {
                throw BridgeError.missing("title")
            }
            let body = text(object["body"], limit: Bridge.maxBody) ?? ""
            let route = (object["route"] as? String).map(WebRoute.init(hash:))
            let id = text(object["id"], limit: 200)
            return .notify(title: title, body: body, route: route, id: id)
        case "badge":
            guard let value = object["count"] else { throw BridgeError.missing("count") }
            guard let count = integer(value) else { throw BridgeError.invalid("count") }
            return .badge(min(max(count, 0), Bridge.maxBadge))
        case "openExternal":
            guard let text = object["url"] as? String else { throw BridgeError.missing("url") }
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                ExternalLink.schemes.contains(scheme)
            else { throw BridgeError.invalid("url") }
            if scheme != "mailto", url.host() == nil { throw BridgeError.invalid("url") }
            return .openExternal(url)
        case "ready":
            return .ready(version: integer(object["v"]) ?? Bridge.version)
        case "org":
            // A missing or null ID means all organizations.
            let value = object["id"]
            let id: String?
            if value == nil || value is NSNull { id = "" } else { id = value as? String }
            guard let id, OrganizationID.isValid(id) else { throw BridgeError.invalid("id") }
            return .org(id)
        default:
            throw BridgeError.unknownType(type)
        }
    }

    static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }

    static func integer(_ value: Any?) -> Int? {
        if value is Bool { return nil }
        if let number = value as? Int { return number }
        if let number = value as? Double, number.isFinite, number == number.rounded(),
            abs(number) < 1e9
        {
            return Int(number)
        }
        return nil
    }
}

/// What the app's own scripts report from inside the page. They run in a
/// separate content world, so the page cannot send these.
public enum ShellMessage: Equatable, Sendable {
    /// The hash changed, so the window can restore it next time.
    case route(WebRoute)
    /// Whether the pointer rests on an empty spot of the title bar strip, where
    /// a drag moves the window.
    case dragZone(Bool)
    /// The web app dropped its token: it signed out or was refused.
    case signedOut
    /// The web app holds another token, such as after it switched tenants.
    /// The app adopts it only once the server confirms it.
    case token(String)
    /// The language was changed in the web app.
    case language(Language)

    /// A bearer token: printable ASCII without spaces, and of a sane length.
    static func isToken(_ text: String) -> Bool {
        (1...512).contains(text.utf8.count) && text.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    public static func parse(_ body: Any) throws -> ShellMessage {
        guard let object = body as? [String: Any] else { throw BridgeError.notAnObject }
        guard let type = object["type"] as? String else { throw BridgeError.missing("type") }
        switch type {
        case "route":
            guard let hash = object["hash"] as? String else { throw BridgeError.missing("hash") }
            return .route(WebRoute(hash: hash))
        case "dragZone":
            guard let active = object["active"] as? Bool else { throw BridgeError.missing("active") }
            return .dragZone(active)
        case "signedOut":
            return .signedOut
        case "token":
            guard let value = object["value"] as? String else { throw BridgeError.missing("value") }
            guard Self.isToken(value) else { throw BridgeError.invalid("value") }
            return .token(value)
        case "language":
            guard let code = object["value"] as? String, let language = Language(rawValue: code) else {
                throw BridgeError.invalid("value")
            }
            return .language(language)
        default:
            throw BridgeError.unknownType(type)
        }
    }
}

/// A command the Mac app sends to the web app.
public enum BridgeCommand: Equatable, Sendable {
    case palette
    case newNote
    /// Shows one organization, or all of them for an empty ID.
    case org(String)

    public var name: String {
        switch self {
        case .palette: "palette"
        case .newNote: "newNote"
        case .org: "org"
        }
    }
}

/// The IDs of organizations: lowercase letters, digits and dashes. Empty means all.
public enum OrganizationID {
    public static func isValid(_ id: String) -> Bool {
        id.count <= 64 && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
    }
}

/// Links that leave the app.
public enum ExternalLink {
    static let schemes: Set<String> = ["http", "https", "mailto"]
}

/// Where a navigation of the web view may go.
public enum NavigationDecision: Equatable, Sendable {
    case allow
    case openExternally
    case cancel
}

/// Keeps the web view on the server: other pages open in the browser.
public enum NavigationPolicy {
    public static func decide(_ url: URL, server: URL, isMainFrame: Bool) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "http", "https":
            if sameOrigin(url, server) { return .allow }
            return .openExternally
        case "mailto":
            return .openExternally
        case "about", "blob", "data":
            // Previews and downloads of the web app live in frames and blobs.
            if scheme == "about", url.absoluteString == "about:blank" { return .allow }
            return isMainFrame ? .cancel : .allow
        default:
            return .cancel
        }
    }

    /// Scheme, host and port, with default ports filled in.
    public static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func origin(_ url: URL) -> (String, String, Int)? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else {
                return nil
            }
            let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
            return (scheme, host, port)
        }
        guard let left = origin(a), let right = origin(b) else { return false }
        return left == right
    }

    /// The origin as the page writes it in `location.origin`.
    public static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else {
            return nil
        }
        let shown = host.contains(":") ? "[\(host)]" : host
        if let port = url.port, !(scheme == "https" && port == 443), !(scheme == "http" && port == 80) {
            return "\(scheme)://\(shown):\(port)"
        }
        return "\(scheme)://\(shown)"
    }
}
