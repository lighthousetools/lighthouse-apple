import LighthouseKit
import SwiftUI

/// A permission request of a Claude Code session.
public struct PermissionRow: View {
    @Environment(AppModel.self) private var model
    let permission: Permission

    public init(permission: Permission) {
        self.permission = permission
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(permission.tool).font(.headline)
            Text("Claude Code, \(permission.project)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(permission.input.pretty)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            HStack {
                Button("Allow") { Task { await model.decide(permission, allow: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Deny", role: .destructive) {
                    Task { await model.decide(permission, allow: false) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A proposal of an agent.
struct ApprovalRow: View {
    @Environment(AppModel.self) private var model
    let approval: Approval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.tool).font(.headline)
            Text(approval.agentId).font(.subheadline).foregroundStyle(.secondary)
            if approval.quotesExternal {
                Label(
                    "This run read external content. Check the proposal carefully.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            Text(approval.input.pretty)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            HStack {
                Button("Approve") { Task { await model.decide(approval, approve: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Deny", role: .destructive) {
                    Task { await model.decide(approval, approve: false) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Everything that waits for a decision.
public struct ApprovalsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List {
            ErrorBanner()
            if model.pendingCount == 0 {
                ContentUnavailableView("Nothing is waiting for you", systemImage: "checkmark.circle")
            }
            if !model.permissions.isEmpty {
                Section("Claude Code") {
                    ForEach(model.permissions) { PermissionRow(permission: $0) }
                }
            }
            if !model.approvals.isEmpty {
                Section("Agents") {
                    ForEach(model.approvals) { ApprovalRow(approval: $0) }
                }
            }
        }
        .navigationTitle("Approvals")
        .refreshable { await model.refresh() }
    }
}
