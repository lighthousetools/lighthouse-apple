import LighthouseKit
import SwiftUI

/// The day at a glance.
public struct TodayView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    private var activeSessions: Int {
        model.sessions.filter { $0.status != "done" }.count
    }

    private var nextAgent: Agent? {
        model.agents.filter { $0.nextRun != nil }.min { $0.nextRun! < $1.nextRun! }
    }

    public var body: some View {
        List {
            ErrorBanner()
            Section {
                LabeledContent("Need you", value: "\(model.pendingCount)")
                LabeledContent("Active sessions", value: "\(activeSessions)")
                LabeledContent("Model costs today", value: model.spentToday.euros)
                if let agent = nextAgent, let time = agent.nextRun {
                    LabeledContent(agent.name, value: time.formatted(.dateTime.weekday().hour().minute()))
                }
            }
            Section("Latest runs") {
                if model.runs.isEmpty {
                    Text("No runs yet.").foregroundStyle(.secondary)
                }
                ForEach(model.runs) { run in
                    NavigationLink(value: run) {
                        LabeledContent(run.agentId) { StatusBadge(status: run.status) }
                    }
                }
            }
        }
        .navigationTitle("Today")
        .navigationDestination(for: Run.self) { RunView(run: $0) }
        .refreshable { await model.refresh() }
    }
}

extension Run: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct RunView: View {
    let run: Run

    private var report: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let text = run.report ?? run.reason ?? "This run has no report."
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(status: run.status)
                Text(report).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(run.agentId)
    }
}

/// Machines and their Claude Code sessions.
public struct SessionsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List {
            ErrorBanner()
            Section("Machines") {
                if model.nodes.isEmpty {
                    Text("No machine is connected.").foregroundStyle(.secondary)
                }
                ForEach(model.nodes) { node in
                    LabeledContent {
                        Button(node.paused ? "Resume" : "Pause", role: node.paused ? nil : .destructive) {
                            Task { await model.setPaused(node, paused: !node.paused) }
                        }
                    } label: {
                        Text(node.name)
                        Text(node.online ? "Online" : "Offline")
                    }
                }
            }
            Section("Claude Code") {
                if model.sessions.isEmpty {
                    Text("No sessions yet.").foregroundStyle(.secondary)
                }
                ForEach(model.sessions, id: \.rowID) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(session.project).font(.headline)
                            Spacer()
                            StatusBadge(status: session.status)
                        }
                        Text([session.nodeName, session.branch].compactMap(\.self).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let summary = session.summary {
                            Text(summary).font(.footnote).lineLimit(3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .refreshable { await model.refresh() }
    }
}

extension Session {
    fileprivate var rowID: String { "\(nodeId)-\(id)" }
}

/// All agents.
public struct AgentsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List {
            ErrorBanner()
            if model.agents.isEmpty {
                ContentUnavailableView("No agents yet", systemImage: "sparkles")
            }
            ForEach(model.agents) { agent in
                VStack(alignment: .leading, spacing: 6) {
                    Text(agent.name).font(.headline)
                    if let next = agent.nextRun {
                        Text("Next: \(next.formatted(.dateTime.weekday().hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(agent.blocked, id: \.self) { reason in
                        Text(reason).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Run now") { Task { await model.run(agent) } }
                        .buttonStyle(.bordered)
                        .disabled(!agent.blocked.isEmpty)
                }
            }
        }
        .navigationTitle("Agents")
        .refreshable { await model.refresh() }
    }
}
