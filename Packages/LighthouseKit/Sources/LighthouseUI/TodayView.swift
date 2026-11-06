import LighthouseKit
import SwiftUI

/// Holds a question and the answer as it arrives.
@MainActor
@Observable
final class AskModel {
    var question = ""
    var answer = ""
    var sources: [EntrySummary] = []
    var failure: String?
    var busy = false
    private var task: Task<Void, Never>?

    func ask(_ client: Client?) {
        guard let client, !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        task?.cancel()
        answer = ""
        sources = []
        failure = nil
        busy = true
        let text = question
        task = Task {
            defer { busy = false }
            do {
                for try await event in try client.askStream(text) {
                    switch event {
                    case .delta(let piece): answer += piece
                    case .done(let done):
                        answer = done.answer
                        sources = done.sources
                    }
                }
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func reset() {
        task?.cancel()
        question = ""
        answer = ""
        sources = []
        failure = nil
        busy = false
    }

    var hasResult: Bool { !answer.isEmpty || failure != nil || busy }
}

/// The question field and the answer below it.
struct AskField: View {
    @Environment(AppModel.self) private var model
    @State private var ask = AskModel()
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var ask = ask
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(Theme.lamp)
                TextField(tr("What do you want to know?"), text: $ask.question)
                    .textFieldStyle(.plain)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .onSubmit { ask.ask(model.client) }
                Button(ask.busy ? tr("Thinking…") : tr("Ask")) { ask.ask(model.client) }
                    .buttonStyle(LampButtonStyle())
                    .disabled(ask.busy || ask.question.isEmpty)
            }
            if ask.hasResult {
                Divider().overlay(Theme.line)
                if let failure = ask.failure {
                    Text(failure).font(Theme.body(14)).foregroundStyle(Theme.crit)
                } else if ask.answer.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    MarkdownView(source: ask.answer)
                }
                HStack(spacing: 6) {
                    if !ask.sources.isEmpty {
                        Text(tr("Based on")).font(Theme.body(12)).foregroundStyle(Theme.ink3)
                        ForEach(ask.sources.prefix(4)) { Tag(text: $0.title) }
                    }
                    Spacer()
                    Button(tr("Close")) { ask.reset() }
                        .buttonStyle(.plain)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Theme.lamp : Theme.line))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// The briefing: what happened, what needs you, what comes next.
public struct TodayView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let opening =
            switch hour {
            case 5..<12: tr("Good morning")
            case 12..<18: tr("Good afternoon")
            default: tr("Good evening")
            }
        guard let name = model.ownerName?.split(separator: " ").first else { return opening }
        return "\(opening), \(name)"
    }

    private var dateLine: String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Lang.locale))
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
        return "\(date) · \(tr("Week %@", String(week)))"
    }

    private var needCount: Int { model.pendingCount + model.waitingSessions.count }

    private var subtitle: String {
        switch needCount {
        case 0: tr("Nothing needs you right now")
        case 1: tr("1 item for you")
        default: tr("%@ items for you", String(needCount))
        }
    }

    private var latestBrief: Run? {
        model.runs.first { $0.agentId.contains("brief") && $0.report != nil }
    }

    private var activity: [Run] {
        model.runs.filter { $0.agentId != "brain-ask" && $0.agentId != "agent-draft" }
    }

    private func story(_ run: Run) -> String {
        let name = model.agentName(run.agentId)
        switch run.status {
        case "running": return tr("%@ is running", name)
        case "waiting": return tr("%@ waits for your decision", name)
        case "failed", "rejected", "limit_exceeded":
            return tr("%@ failed at %@", name, run.startedAt.shortTime)
        default: return tr("%@ finished at %@", name, run.startedAt.shortTime)
        }
    }

    @ViewBuilder private var main: some View {
        AskField()
        if let brief = latestBrief, let report = brief.report {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Dot(color: Theme.lamp)
                    Text(tr("Your briefing").uppercased())
                        .font(Theme.mono(11))
                        .tracking(0.8)
                        .foregroundStyle(Theme.lampInk)
                    Spacer()
                    Text(brief.startedAt.shortTime).font(Theme.mono(11)).foregroundStyle(Theme.lampInk)
                }
                MarkdownView(source: report)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lampSoft, in: RoundedRectangle(cornerRadius: 16))
        }
        if needCount > 0 {
            SectionTitle(text: tr("Needs you"), count: needCount)
            ForEach(model.permissions) { PermissionCard(permission: $0) }
            ForEach(model.approvals) { ApprovalCard(approval: $0) }
            ForEach(model.waitingSessions, id: \.rowID) { session in
                EdgeRow(edge: Theme.lamp) { SessionLines(session: session) }
            }
        }
        SectionTitle(text: tr("What happened"))
        if activity.isEmpty { Quiet(text: tr("Nothing has happened yet.")) }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(activity.prefix(6)) { run in
                NavigationLink(value: run) {
                    HStack(spacing: 10) {
                        Dot(color: run.status == "failed" ? Theme.crit : run.status == "running" ? Theme.info : Theme.ink3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(story(run)).font(Theme.body(14)).foregroundStyle(Theme.ink)
                            if run.status == "running", let activity = run.activity {
                                Text(activity).font(Theme.mono(11.5)).foregroundStyle(Theme.ink3)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.ink3)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 22) {
            if needCount > 0 || model.connectors.contains(where: { !$0.connected }) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("Open for you")).font(Theme.display(14)).foregroundStyle(Theme.ink)
                    if model.pendingCount > 0 {
                        OpenLine(color: Theme.lamp, label: tr("Approvals"), value: "\(model.pendingCount)")
                    }
                    if !model.waitingSessions.isEmpty {
                        OpenLine(color: Theme.lamp, label: tr("Waiting sessions"), value: "\(model.waitingSessions.count)")
                    }
                    ForEach(model.connectors.filter { !$0.connected }) { connector in
                        OpenLine(color: Theme.crit, label: tr("%@: not connected", connector.name), value: "")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Coming up")).font(Theme.display(14)).foregroundStyle(Theme.ink)
                let agents = model.agents.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
                if agents.isEmpty { Quiet(text: tr("Nothing is scheduled.")) }
                ForEach(agents.prefix(5)) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(agent.nextRun!.shortTime).font(Theme.mono(11.5)).foregroundStyle(Theme.ink3)
                        VStack(alignment: .leading) {
                            Text(agent.name).font(Theme.body(13.5)).foregroundStyle(Theme.ink)
                            Text(agent.nextRun!.formatted(.dateTime.weekday(.wide).locale(Lang.locale)))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("Costs today")).font(Theme.display(14)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(model.spentToday.euros).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                }
                let top = model.costsToday.map(\.costEur).max() ?? 0
                if model.costsToday.isEmpty { Quiet(text: tr("No model calls today.")) }
                ForEach(model.costsToday, id: \.provider) { cost in
                    HStack(spacing: 10) {
                        Text(cost.provider.capitalized)
                            .font(Theme.body(13))
                            .frame(width: 76, alignment: .leading)
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
            PageTitle(title: greeting, subtitle: subtitle)
            #if os(macOS)
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 14) { main }
                    side.frame(width: 260).padding(.top, 8)
                }
            #else
                main
                side.padding(.top, 8)
            #endif
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
            .frame(height: 6)
            .overlay(alignment: .leading) {
                Capsule().fill(Theme.ink3).scaleEffect(x: fraction, anchor: .leading)
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
    @Environment(AppModel.self) private var model
    let run: Run

    var body: some View {
        Page(maxWidth: 760) {
            Eyebrow(text: run.startedAt.formatted(.dateTime.day().month().hour().minute().locale(Lang.locale)))
            PageTitle(title: model.agentName(run.agentId))
            Pill(status: run.status)
            MarkdownView(source: run.report ?? run.reason ?? tr("This run has no report."))
        }
    }
}
