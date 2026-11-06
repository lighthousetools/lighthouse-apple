#if os(macOS)
    import LighthouseKit
    import SwiftUI

    /// The menu bar window of the Mac app: what matters now, the rest on demand.
    public struct MenuBarContent: View {
        @Environment(AppModel.self) private var model
        @Environment(Navigator.self) private var navigator
        @Environment(\.openWindow) private var openWindow
        @State private var showsMore = false

        public init() {
            LighthouseFonts.register()
        }

        private func heading(_ text: String) -> some View {
            Text(text).font(Theme.display(12)).foregroundStyle(Theme.ink3)
        }

        private func line(_ color: Color, _ name: String, _ detail: String, hollow: Bool = false) -> some View {
            HStack(spacing: 10) {
                Dot(color: color, hollow: hollow)
                Text(name).font(Theme.body(13.5, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(detail).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
            }
        }

        private func open(_ section: Section) {
            navigator.section = section
            openWindow(id: "main")
            NSApplication.shared.activate()
        }

        private var header: some View {
            HStack(spacing: 8) {
                LogoMark(size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Lighthouse").font(Theme.display(15)).foregroundStyle(Theme.ink)
                    Text(tr(model.isConnected ? "Connected to %@" : "No connection to %@", model.serverHost))
                        .font(Theme.body(11.5))
                        .foregroundStyle(model.isConnected ? Theme.ink3 : Theme.crit)
                }
                Spacer()
                Dot(color: model.isConnected ? Theme.ok : Theme.crit)
            }
        }

        private func request(_ permission: Permission) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("%@ wants to run", permission.project))
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.lampInk)
                Text(permission.input.fields.first?.value ?? permission.tool)
                    .font(Theme.mono(12, weight: .medium))
                    .lineLimit(4)
                    .foregroundStyle(Theme.ink)
                HStack {
                    Button {
                        Task { await model.decide(permission, allow: false) }
                    } label: {
                        Text(tr("Deny")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle(destructive: true))
                    Button {
                        Task { await model.decide(permission, allow: true) }
                    } label: {
                        Text(tr("Allow")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LampButtonStyle())
                }
            }
            .padding(10)
            .background(Theme.lampSoft, in: RoundedRectangle(cornerRadius: 10))
        }

        private func sessionColor(_ status: String) -> Color {
            switch status {
            case "waiting": Theme.lamp
            case "running": Theme.info
            default: Theme.ink3
            }
        }

        @ViewBuilder private var more: some View {
            if !model.nodes.isEmpty {
                Divider().overlay(Theme.line)
                heading(tr("Machines"))
                ForEach(model.nodes) { node in
                    line(
                        node.paused ? Theme.lamp : node.online ? Theme.ok : Theme.ink3, node.name,
                        tr(node.paused ? "Paused" : node.online ? "Online" : "Offline"),
                        hollow: !node.online)
                }
                let active = model.nodes.filter { !$0.paused }
                Button(tr(active.isEmpty ? "Resume all" : "Pause all")) {
                    Task {
                        for node in active.isEmpty ? model.nodes : active {
                            await model.setPaused(node, paused: !active.isEmpty)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(Theme.body(13))
                .foregroundStyle(active.isEmpty ? Theme.lampInk : Theme.crit)
                .padding(.leading, 18)
            }
            if !model.connectors.isEmpty {
                Divider().overlay(Theme.line)
                heading(tr("Services"))
                ForEach(model.connectors) { connector in
                    line(
                        connector.connected ? Theme.ok : Theme.crit, connector.name,
                        tr(connector.connected ? "connected" : "not connected"))
                }
            }
            let scheduled = model.agents.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
            if !scheduled.isEmpty {
                Divider().overlay(Theme.line)
                heading(tr("Agents"))
                ForEach(scheduled.prefix(3)) { agent in
                    line(Theme.info, agent.name, agent.nextRun!.dayAndTime)
                }
            }
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                header
                ErrorBanner()
                if model.phase != .ready {
                    Text(tr("Sign in in the main window.")).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                } else {
                    Divider().overlay(Theme.line)
                    if model.pendingCount == 0 && model.waitingSessions.isEmpty {
                        line(Theme.ok, tr("All quiet"), "")
                    }
                    ForEach(model.permissions) { request($0) }
                    if !model.approvals.isEmpty {
                        Button {
                            open(.approvals)
                        } label: {
                            line(
                                Theme.lamp,
                                model.approvals.count == 1
                                    ? tr("1 approval") : tr("%@ approvals", String(model.approvals.count)),
                                tr("Open"))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(model.sessions.filter { $0.status != "done" }.prefix(4), id: \.rowID) { session in
                        line(sessionColor(session.status), session.project, statusName(session.status))
                    }
                    DisclosureGroup(tr(showsMore ? "Hide details" : "Show details"), isExpanded: $showsMore) {
                        VStack(alignment: .leading, spacing: 8) { more }
                            .padding(.top, 4)
                    }
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                }
                Divider().overlay(Theme.line)
                HStack {
                    Button(tr("Open Lighthouse")) { open(navigator.section) }
                        .buttonStyle(.plain)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.lampInk)
                    Spacer()
                    Button(tr("Quit")) { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(Theme.surface)
            .tint(Theme.lamp)
            .id(model.language)
        }
    }
#endif
