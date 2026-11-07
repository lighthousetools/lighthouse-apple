import Foundation

/// A notification about something that has just arrived.
public struct RequestNotice: Equatable, Sendable {
    /// Unique per item and shared with the web app, which posts the same keys
    /// for ready items (`kind:id`), so a notification is never shown twice.
    public let key: String
    public let title: String
    public let body: String
    public let route: WebRoute
    /// Whether the web app announces this kind itself while it runs.
    public let webAnnounces: Bool
}

extension RequestNotice {
    /// What the owner should hear about: each item of the ready feed (or, on
    /// older servers, approvals and permission requests) and critical alerts.
    public static func candidates(
        ready: ReadyFeed?, approvals: [Approval], permissions: [Permission], alerts: [Alert]
    ) -> [RequestNotice] {
        var notices: [RequestNotice] = []
        if let ready {
            for item in ready.items {
                notices.append(
                    RequestNotice(
                        key: item.key, title: item.title, body: item.summary ?? readyKindName(item.kind),
                        route: item.route, webAnnounces: true))
            }
        } else {
            for approval in approvals {
                notices.append(
                    RequestNotice(
                        key: "approval:\(approval.id.uuidString.lowercased())", title: tr("Approval needed"),
                        body: tr("%@ wants to use %@", readableName(approval.agentId), readableName(approval.tool)),
                        route: .approval(approval.id), webAnnounces: true))
            }
            for permission in permissions {
                notices.append(
                    RequestNotice(
                        key: "permission:\(permission.id.uuidString.lowercased())",
                        title: tr("%@ wants to run", permission.project),
                        body: permission.input.fields.first?.value ?? permission.tool,
                        route: .permission(permission.id), webAnnounces: true))
            }
        }
        for alert in alerts where alert.isCritical {
            notices.append(
                RequestNotice(
                    key: "alert:\(alert.id.uuidString.lowercased())", title: tr("Critical alert"),
                    body: alert.title, route: alert.route, webAnnounces: false))
        }
        return notices
    }

    static func readyKindName(_ kind: String) -> String {
        switch kind {
        case "approval": tr("Approval needed")
        case "permission": tr("Permission request")
        case "draft": tr("Draft ready")
        case "task": tr("Suggested task")
        case "fact": tr("Something learned about you")
        default: tr("Ready for you")
        }
    }
}

/// Tells which notices are new since the last look, so each one is announced
/// once. The first look only remembers what is already there.
public struct RequestTracker: Sendable {
    private var seen: Set<String> = []
    private var started = false

    public init() {}

    public mutating func fresh(_ candidates: [RequestNotice]) -> [RequestNotice] {
        let first = !started
        started = true
        let notices = candidates.filter { !seen.contains($0.key) }
        // Forget what is gone, so the set does not grow forever.
        seen = Set(candidates.map(\.key))
        return first ? [] : notices
    }
}
