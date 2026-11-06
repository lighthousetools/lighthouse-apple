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
            VStack(alignment: .leading, spacing: 12) {
                ErrorBanner()
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
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
            Text(title).font(Theme.display(28)).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(Theme.body(14)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(.bottom, 6)
    }
}

/// Text for an empty state.
struct Quiet: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.body(14)).foregroundStyle(Theme.ink3).padding(.vertical, 8)
    }
}

extension Double {
    var euros: String { formatted(.currency(code: "EUR")) }
}

extension Date {
    var shortTime: String { formatted(.dateTime.hour().minute()) }
    var dayAndTime: String { formatted(.dateTime.weekday().hour().minute()) }
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
                Text("\(permission.tool) wants to run").font(Theme.display(15)).foregroundStyle(Theme.ink)
                Text(command)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                HStack {
                    Button("Allow") { Task { await model.decide(permission, allow: true) } }
                        .buttonStyle(LampButtonStyle())
                    Button("Deny") { Task { await model.decide(permission, allow: false) } }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                }
                .padding(.top, 4)
            }
        }
    }
}

/// A proposal of an agent, with its decision.
struct ApprovalCard: View {
    @Environment(AppModel.self) private var model
    let approval: Approval

    var body: some View {
        EdgeRow(edge: Theme.lamp) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Tag(text: approval.tool.split(separator: ".").first.map(String.init) ?? "tool")
                    Text(approval.agentId).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                }
                Text(approval.tool).font(Theme.display(15)).foregroundStyle(Theme.ink)
                if approval.quotesExternal {
                    Text("This run read external content. Check the proposal carefully.")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.lampInk)
                }
                Text(approval.input.pretty)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.ink2)
                    .textSelection(.enabled)
                HStack {
                    Button("Approve") { Task { await model.decide(approval, approve: true) } }
                        .buttonStyle(LampButtonStyle())
                    Button("Deny") { Task { await model.decide(approval, approve: false) } }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                }
                .padding(.top, 4)
            }
        }
    }
}
