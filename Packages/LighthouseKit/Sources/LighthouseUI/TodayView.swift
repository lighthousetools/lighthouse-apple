import LighthouseKit
import SwiftUI

/// The briefing: what happened, what needs you, what comes next.
public struct TodayView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let opening =
            switch hour {
            case 5..<12: "Good morning"
            case 12..<18: "Good afternoon"
            default: "Good evening"
            }
        return model.ownerName.map { "\(opening), \($0.split(separator: " ").first ?? "")" } ?? opening
    }

    private var dateLine: String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
        return "\(date) · Week \(week)"
    }

    private var latestBrief: Run? {
        model.runs.first { $0.agentId.contains("brief") && $0.report != nil }
    }

    private var isWide: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    @ViewBuilder private var main: some View {
        if let brief = latestBrief, let report = brief.report {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Dot(color: Theme.lamp)
                    Text("SUMMARY").font(Theme.mono(11)).tracking(0.8).foregroundStyle(Theme.lampInk)
                }
                MarkdownView(source: report)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lampSoft, in: RoundedRectangle(cornerRadius: 16))
        }
        SectionTitle(text: "Needs you", count: model.pendingCount + model.waitingSessions.count)
        if model.pendingCount + model.waitingSessions.count == 0 {
            EdgeRow(edge: Theme.ok) {
                Text("Nothing is waiting for you.").font(Theme.body(14)).foregroundStyle(Theme.ink2)
            }
        }
        ForEach(model.permissions) { PermissionCard(permission: $0) }
        ForEach(model.approvals) { ApprovalCard(approval: $0) }
        ForEach(model.waitingSessions, id: \.rowID) { session in
            EdgeRow(edge: Theme.lamp) { SessionLines(session: session) }
        }
        SectionTitle(text: "Latest runs", count: model.runs.count)
        if model.runs.isEmpty { Quiet(text: "No runs yet.") }
        ForEach(model.runs.prefix(8)) { run in
            NavigationLink(value: run) {
                EdgeRow(edge: run.status == "failed" ? Theme.crit : Theme.ok) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Tag(text: run.startedAt.shortTime)
                            Text(run.costEur.euros).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                            Spacer()
                            Pill(status: run.status)
                        }
                        Text(run.agentId).font(Theme.display(15)).foregroundStyle(Theme.ink)
                        if let reason = run.reason {
                            Text(reason).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var openCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open for you").font(Theme.display(14)).foregroundStyle(Theme.ink)
                OpenLine(color: Theme.lamp, label: "Approvals", value: "\(model.pendingCount)")
                OpenLine(color: Theme.lamp, label: "Waiting sessions", value: "\(model.waitingSessions.count)")
                ForEach(model.connectors.filter { !$0.connected }) { connector in
                    OpenLine(color: Theme.crit, label: "\(connector.name): not connected", value: "")
                }
            }
        }
    }

    private var plannedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming up").font(Theme.display(14)).foregroundStyle(Theme.ink)
                let agents = model.agents.filter { $0.nextRun != nil }
                    .sorted { $0.nextRun! < $1.nextRun! }
                if agents.isEmpty { Quiet(text: "Nothing is scheduled.") }
                ForEach(agents.prefix(5)) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(agent.nextRun!.shortTime).font(Theme.mono(11.5)).foregroundStyle(Theme.ink3)
                        Dot(color: Theme.info)
                        VStack(alignment: .leading) {
                            Text(agent.name).font(Theme.body(13.5)).foregroundStyle(Theme.ink)
                            Text(agent.nextRun!.formatted(.dateTime.weekday(.wide)))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
            }
        }
    }

    private var costCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Costs today").font(Theme.display(14)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(model.spentToday.euros).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                }
                let top = model.costsToday.map(\.costEur).max() ?? 0
                if model.costsToday.isEmpty { Quiet(text: "No model calls today.") }
                ForEach(model.costsToday, id: \.provider) { cost in
                    HStack(spacing: 10) {
                        Text(cost.provider.capitalized)
                            .font(Theme.body(13))
                            .frame(width: 82, alignment: .leading)
                        ProgressBar(fraction: top > 0 ? cost.costEur / top : 0)
                        Text(cost.costEur.euros).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    public var body: some View {
        Page {
            Eyebrow(text: dateLine)
            PageTitle(title: greeting, subtitle: "\(model.pendingCount) items for you · \(model.runs.count) recent runs")
            if isWide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) { main }
                    VStack(spacing: 14) {
                        openCard
                        plannedCard
                        costCard
                    }
                    .frame(width: 310)
                }
            } else {
                main
                openCard
                plannedCard
                costCard
            }
        }
        .navigationDestination(for: Run.self) { RunView(run: $0) }
    }
}

struct OpenLine: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Dot(color: color)
            Text(label).font(Theme.body(13.5)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Theme.surface3)
            .frame(height: 8)
            .overlay(alignment: .leading) {
                Capsule().fill(Theme.lamp).scaleEffect(x: fraction, anchor: .leading)
            }
    }
}

extension Run: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Session {
    var rowID: String { "\(nodeId)-\(id)" }
}

struct SessionLines: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Tag(text: session.nodeName)
                if let branch = session.branch {
                    Text(branch).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                }
                Spacer()
                Pill(status: session.status)
            }
            Text(session.project).font(Theme.display(15)).foregroundStyle(Theme.ink)
            if let summary = session.summary {
                Text(summary).font(Theme.body(13)).lineLimit(3).foregroundStyle(Theme.ink2)
            }
        }
    }
}

struct RunView: View {
    let run: Run

    var body: some View {
        Page(maxWidth: 780) {
            Eyebrow(text: run.startedAt.formatted(.dateTime.day().month().hour().minute()))
            PageTitle(title: run.agentId)
            Pill(status: run.status)
            Card {
                MarkdownView(source: run.report ?? run.reason ?? "This run has no report.")
            }
        }
    }
}
