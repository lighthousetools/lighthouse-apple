#if os(macOS)
    import LighthouseKit
    import SwiftUI

    /// The menu bar window of the Mac app.
    public struct MenuBarContent: View {
        @Environment(AppModel.self) private var model
        @Environment(\.openWindow) private var openWindow

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

        private var header: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LogoMark(size: 20)
                    Text("Lighthouse").font(Theme.display(15)).foregroundStyle(Theme.ink)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Dot(color: model.isConnected ? Theme.ok : Theme.crit)
                    Text(model.isConnected ? "Connected to \(model.serverHost)" : "No connection to \(model.serverHost)")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink2)
                }
            }
        }

        private func request(_ permission: Permission) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(permission.project) wants to run").font(Theme.body(12.5)).foregroundStyle(Theme.ink2)
                Text(permission.input.pretty)
                    .font(Theme.mono(12, weight: .medium))
                    .lineLimit(4)
                    .foregroundStyle(Theme.ink)
                HStack {
                    Button {
                        Task { await model.decide(permission, allow: false) }
                    } label: {
                        Text("Deny").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle(destructive: true))
                    Button {
                        Task { await model.decide(permission, allow: true) }
                    } label: {
                        Text("Allow").frame(maxWidth: .infinity)
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
            default: Theme.ok
            }
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                header
                ErrorBanner()
                if model.phase != .ready {
                    Text("Sign in in the main window.").font(Theme.body(13)).foregroundStyle(Theme.ink2)
                } else {
                    Divider().overlay(Theme.line)
                    heading("Needs you")
                    if model.pendingCount == 0 {
                        line(Theme.ok, "All quiet", "")
                    }
                    ForEach(model.permissions) { request($0) }
                    if !model.approvals.isEmpty {
                        Button {
                            openWindow(id: "main")
                            NSApplication.shared.activate()
                        } label: {
                            line(Theme.lamp, "\(model.approvals.count) approvals", "Open ›")
                        }
                        .buttonStyle(.plain)
                    }
                    if !model.sessions.isEmpty {
                        Divider().overlay(Theme.line)
                        heading("Claude Code")
                        ForEach(model.sessions.prefix(5), id: \.rowID) { session in
                            line(sessionColor(session.status), session.project, session.status)
                        }
                    }
                    if !model.nodes.isEmpty {
                        Divider().overlay(Theme.line)
                        heading("Machines")
                        ForEach(model.nodes) { node in
                            line(
                                node.paused ? Theme.lamp : Theme.ok, node.name,
                                node.paused ? "paused" : node.online ? "online" : "offline",
                                hollow: !node.online)
                        }
                        if let active = model.nodes.first(where: { !$0.paused }) {
                            Button("Disconnect all") {
                                Task {
                                    await model.setPaused(active, paused: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.crit)
                            .padding(.leading, 18)
                        } else if let paused = model.nodes.first {
                            Button("Resume \(paused.name)") {
                                Task { await model.setPaused(paused, paused: false) }
                            }
                            .buttonStyle(.plain)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.lampInk)
                            .padding(.leading, 18)
                        }
                    }
                    if !model.connectors.isEmpty {
                        Divider().overlay(Theme.line)
                        heading("Services")
                        ForEach(model.connectors) { connector in
                            line(
                                connector.connected ? Theme.ok : Theme.crit, connector.name,
                                connector.connected ? "connected" : "not connected")
                        }
                    }
                    let scheduled = model.agents.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
                    if !scheduled.isEmpty {
                        Divider().overlay(Theme.line)
                        heading("Agents")
                        ForEach(scheduled.prefix(3)) { agent in
                            line(Theme.info, agent.name, agent.nextRun!.dayAndTime)
                        }
                    }
                }
                Divider().overlay(Theme.line)
                HStack {
                    Button("Open Lighthouse") {
                        openWindow(id: "main")
                        NSApplication.shared.activate()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.lampInk)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(14)
            .frame(width: 340)
            .background(Theme.surface)
        }
    }
#endif
