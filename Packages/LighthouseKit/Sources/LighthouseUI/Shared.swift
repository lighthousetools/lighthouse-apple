import LighthouseKit
import SwiftUI

/// Shows an error of the app model.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.lastError {
            Text(message)
                .font(Theme.body(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.critSoft, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.crit)
        }
    }
}

/// A scrolling page with the width and spacing of all views.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 1120
    @ViewBuilder let content: Content
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ErrorBanner()
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .refreshable { await model.refresh() }
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.display(30)).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(Theme.body(14)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(.bottom, 8)
    }
}

/// Text for an empty state.
struct Quiet: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.body(14)).foregroundStyle(Theme.ink3).padding(.vertical, 6)
    }
}

extension Double {
    var euros: String { formatted(.currency(code: "EUR").locale(Lang.locale)) }
}

extension Date {
    var shortTime: String { formatted(.dateTime.hour().minute().locale(Lang.locale)) }
    var dayAndTime: String {
        formatted(.dateTime.weekday().hour().minute().locale(Lang.locale))
    }
    var dayAndMonth: String { formatted(.dateTime.day().month().locale(Lang.locale)) }
}

/// The buttons of a decision, with a quick reaction before the server answers.
struct DecisionButtons: View {
    let yes: String
    let onYes: () async -> Void
    let onNo: () async -> Void
    @State private var busy = false

    private func run(_ action: @escaping () async -> Void) {
        Task {
            busy = true
            await action()
            busy = false
        }
    }

    var body: some View {
        HStack {
            Button(yes) { run(onYes) }.buttonStyle(LampButtonStyle())
            Button(tr("Deny")) { run(onNo) }.buttonStyle(QuietButtonStyle(destructive: true))
        }
        .disabled(busy)
        .padding(.top, 4)
    }
}

/// A permission request of a Claude Code session, with its decision.
struct PermissionCard: View {
    @Environment(AppModel.self) private var model
    let permission: Permission

    private var command: String {
        if case .object(let fields) = permission.input, case .string(let line)? = fields["command"] {
            return line
        }
        return permission.input.pretty
    }

    var body: some View {
        EdgeRow(edge: Theme.lamp) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Tag(text: "Claude Code")
                    Text(permission.project).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                }
                Text(tr("%@ wants to run", permission.project))
                    .font(Theme.display(15))
                    .foregroundStyle(Theme.ink)
                Text(command)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                DecisionButtons(
                    yes: tr("Allow"),
                    onYes: { await model.decide(permission, allow: true) },
                    onNo: { await model.decide(permission, allow: false) })
            }
        }
    }
}

/// A proposal of an agent in plain words, with its decision.
struct ApprovalCard: View {
    @Environment(AppModel.self) private var model
    let approval: Approval
    @State private var showsDetails = false

    private var tool: (connector: String, action: String) {
        let parts = approval.tool.split(separator: ".", maxSplits: 1).map(String.init)
        return (parts.first ?? "", readableName(parts.last ?? approval.tool))
    }

    var body: some View {
        EdgeRow(edge: Theme.lamp) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Tag(text: tool.connector)
                    Text(model.agentName(approval.agentId))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                Text(tool.action).font(Theme.display(16)).foregroundStyle(Theme.ink)
                if let reason = approval.reason {
                    Text(reason).font(Theme.body(14)).foregroundStyle(Theme.ink2)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(approval.input.fields, id: \.name) { field in
                        GridRow {
                            Text(field.name).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                            Text(field.value)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                        }
                    }
                }
                if approval.quotesExternal {
                    Text(tr("This run read external content, which may have shaped the proposal. Check it carefully."))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.lampInk)
                }
                if !approval.consulted.isEmpty {
                    HStack(spacing: 6) {
                        Text(tr("Used before")).font(Theme.body(12)).foregroundStyle(Theme.ink3)
                        ForEach(approval.consulted, id: \.self) { Tag(text: $0) }
                    }
                }
                DisclosureGroup(tr(showsDetails ? "Hide details" : "Show details"), isExpanded: $showsDetails) {
                    Text(approval.input.pretty)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.ink2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)
                DecisionButtons(
                    yes: tr("Approve"),
                    onYes: { await model.decide(approval, approve: true) },
                    onNo: { await model.decide(approval, approve: false) })
            }
        }
    }
}
