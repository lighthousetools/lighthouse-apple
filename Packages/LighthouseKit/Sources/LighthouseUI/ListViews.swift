import LighthouseKit
import SwiftUI

/// Everything that waits for a decision.
public struct ApprovalsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Page(maxWidth: 780) {
            PageTitle(title: "Approvals", subtitle: "Nothing with external effect happens without you.")
            if model.pendingCount == 0 { Quiet(text: "Nothing is waiting for you.") }
            ForEach(model.permissions) { PermissionCard(permission: $0) }
            ForEach(model.approvals) { ApprovalCard(approval: $0) }
        }
    }
}

/// Machines and their Claude Code sessions.
public struct SessionsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Page(maxWidth: 780) {
            PageTitle(title: "Sessions", subtitle: "Claude Code on your machines.")
            SectionTitle(text: "Machines", count: model.nodes.count)
            if model.nodes.isEmpty { Quiet(text: "No machine is connected.") }
            ForEach(model.nodes) { node in
                Card(padding: 12) {
                    HStack(spacing: 10) {
                        Dot(color: node.paused ? Theme.lamp : node.online ? Theme.ok : Theme.ink3, hollow: !node.online)
                        VStack(alignment: .leading) {
                            Text(node.name).font(Theme.display(14)).foregroundStyle(Theme.ink)
                            Text(node.paused ? "Paused" : node.online ? "Online" : "Offline")
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        Button(node.paused ? "Resume" : "Pause") {
                            Task { await model.setPaused(node, paused: !node.paused) }
                        }
                        .buttonStyle(QuietButtonStyle(destructive: !node.paused))
                    }
                }
            }
            SectionTitle(text: "Claude Code", count: model.sessions.count)
            if model.sessions.isEmpty { Quiet(text: "No sessions yet.") }
            ForEach(model.sessions, id: \.rowID) { session in
                EdgeRow(edge: session.status == "waiting" ? Theme.lamp : session.status == "running" ? Theme.info : Theme.ok) {
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

    public var body: some View {
        Page(maxWidth: 780) {
            PageTitle(title: "Agents", subtitle: "\(model.agents.count) agents. New ones are written in the web app.")
            if model.agents.isEmpty { Quiet(text: "No agents yet.") }
            ForEach(model.agents) { agent in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(agent.name).font(Theme.display(16)).foregroundStyle(Theme.ink)
                            Spacer()
                            if let next = agent.nextRun {
                                Text(next.dayAndTime).font(Theme.mono(11.5)).foregroundStyle(Theme.ink3)
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach(agent.tools.prefix(5), id: \.name) { tool in
                                Tag(text: tool.name, highlighted: tool.level == "write")
                            }
                        }
                        ForEach(agent.blocked, id: \.self) { reason in
                            Text(reason).font(Theme.body(13)).foregroundStyle(Theme.crit)
                        }
                        Button("Run now") { Task { await model.run(agent) } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(!agent.blocked.isEmpty)
                    }
                }
            }
        }
    }
}
