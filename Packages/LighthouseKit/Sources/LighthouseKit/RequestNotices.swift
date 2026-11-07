import Foundation

/// A notification about a request that has just arrived.
public struct RequestNotice: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let route: WebRoute
}

/// Tells which requests are new since the last look, so each one is announced
/// once. The first look only remembers what is already there.
public struct RequestTracker: Sendable {
    private var seen: Set<UUID> = []
    private var started = false

    public init() {}

    public mutating func notices(approvals: [Approval], permissions: [Permission]) -> [RequestNotice] {
        let fresh = !started
        started = true
        var notices: [RequestNotice] = []
        for approval in approvals where !seen.contains(approval.id) {
            notices.append(
                RequestNotice(
                    id: approval.id, title: tr("Approval needed"),
                    body: tr("%@ wants to use %@", readableName(approval.agentId), readableName(approval.tool)),
                    route: .approval(approval.id)))
        }
        for permission in permissions where !seen.contains(permission.id) {
            notices.append(
                RequestNotice(
                    id: permission.id, title: tr("%@ wants to run", permission.project),
                    body: permission.input.fields.first?.value ?? permission.tool,
                    route: .permission(permission.id)))
        }
        // Forget what is gone, so the set does not grow forever.
        seen = Set(approvals.map(\.id) + permissions.map(\.id))
        return fresh ? [] : notices
    }
}
