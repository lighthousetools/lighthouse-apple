#if os(macOS)
import LighthouseKit
import SwiftUI

/// The menu bar window of the Mac app.
public struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    private var waitingSessions: [Session] {
        model.sessions.filter { $0.status == "waiting" }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ErrorBanner()
            if model.phase != .ready {
                Text("Sign in to Lighthouse in the main window.")
            } else if model.pendingCount == 0 {
                Label("All quiet", systemImage: "checkmark.circle")
            }
            ForEach(model.permissions) { PermissionRow(permission: $0) }
            if !model.approvals.isEmpty {
                Text("\(model.approvals.count) agent proposals wait for you")
                    .font(.subheadline)
            }
            if !model.sessions.isEmpty {
                Divider()
                ForEach(model.sessions.prefix(6), id: \.id) { session in
                    LabeledContent(session.project) { StatusBadge(status: session.status) }
                }
            }
            if !model.nodes.isEmpty {
                Divider()
                ForEach(model.nodes) { node in
                    Button(node.paused ? "Resume \(node.name)" : "Pause \(node.name), deny all") {
                        Task { await model.setPaused(node, paused: !node.paused) }
                    }
                }
            }
            Divider()
            HStack {
                Button("Open Lighthouse") {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 340)
    }
}
#endif
