import LighthouseKit
import SwiftUI

/// Everything that waits for a decision.
public struct ApprovalsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Page(maxWidth: 760) {
            PageTitle(title: tr("Approvals"), subtitle: tr("Nothing with external effect happens without you."))
            if model.pendingCount == 0 { Quiet(text: tr("Nothing is waiting for you.")) }
            ForEach(model.permissions) { PermissionCard(permission: $0) }
            if model.approvals.count > 1 {
                HStack {
                    Button(tr("Approve all")) { Task { await model.decideAll(approve: true) } }
                        .buttonStyle(QuietButtonStyle())
                    Button(tr("Deny all")) { Task { await model.decideAll(approve: false) } }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                }
            }
            ForEach(model.approvals) { ApprovalCard(approval: $0) }
        }
    }
}

/// Machines and their Claude Code sessions.
public struct SessionsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Page(maxWidth: 760) {
            PageTitle(title: tr("Sessions"), subtitle: tr("Claude Code on your machines."))
            SectionTitle(text: tr("Machines"), count: model.nodes.count)
            if model.nodes.isEmpty { Quiet(text: tr("No machine is connected.")) }
            ForEach(model.nodes) { node in
                HStack(spacing: 10) {
                    Dot(color: node.paused ? Theme.lamp : node.online ? Theme.ok : Theme.ink3, hollow: !node.online)
                    VStack(alignment: .leading) {
                        Text(node.name).font(Theme.display(14)).foregroundStyle(Theme.ink)
                        Text(tr(node.paused ? "Paused" : node.online ? "Online" : "Offline"))
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Button(tr(node.paused ? "Resume" : "Pause")) {
                        Task { await model.setPaused(node, paused: !node.paused) }
                    }
                    .buttonStyle(QuietButtonStyle(destructive: !node.paused))
                }
                .padding(.vertical, 4)
            }
            SectionTitle(text: "Claude Code", count: model.sessions.count)
            if model.sessions.isEmpty { Quiet(text: tr("No sessions yet.")) }
            ForEach(model.sessions, id: \.rowID) { session in
                EdgeRow(edge: session.status == "waiting" ? Theme.lamp : session.status == "running" ? Theme.info : Theme.line) {
                    SessionLines(session: session)
                }
            }
        }
    }
}

/// All agents.
public struct AgentsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    private func lastRun(_ agent: Agent) -> Run? {
        model.runs.first { $0.agentId == agent.id }
    }

    public var body: some View {
        Page(maxWidth: 760) {
            PageTitle(title: tr("Agents"), subtitle: tr("New agents are written in the web app."))
            if model.agents.isEmpty { Quiet(text: tr("No agents yet.")) }
            ForEach(model.agents) { agent in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(agent.name).font(Theme.display(16)).foregroundStyle(Theme.ink)
                            Spacer()
                            if let run = lastRun(agent), run.status == "running" { Pill(status: run.status) }
                            Text(agent.nextRun?.dayAndTime ?? tr("Manual"))
                                .font(Theme.mono(11.5))
                                .foregroundStyle(Theme.ink3)
                        }
                        HStack(spacing: 6) {
                            ForEach(agent.tools.prefix(5), id: \.name) { tool in
                                Tag(text: tool.name, highlighted: tool.level == "write")
                            }
                        }
                        ForEach(agent.blocked, id: \.self) { reason in
                            Text(reason).font(Theme.body(13)).foregroundStyle(Theme.crit)
                        }
                        Button(tr("Run now")) { Task { await model.run(agent) } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(!agent.blocked.isEmpty)
                    }
                }
            }
        }
    }
}
