import LighthouseKit
import SwiftUI

/// Chooses between sign-in and the app.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {
        LighthouseFonts.register()
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case .signedOut:
                LoginView()
            case .ready:
                MainView().task { await model.keepFresh() }
            }
        }
        .tint(Theme.lamp)
    }
}

enum Section: String, CaseIterable, Identifiable {
    case today = "Today"
    case approvals = "Approvals"
    case sessions = "Sessions"
    case agents = "Agents"
    case brain = "Brain"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .approvals: "checkmark.shield"
        case .sessions: "terminal"
        case .agents: "square.stack.3d.up"
        case .brain: "brain"
        case .settings: "gearshape"
        }
    }

    @ViewBuilder @MainActor var content: some View {
        switch self {
        case .today: TodayView()
        case .approvals: ApprovalsView()
        case .sessions: SessionsView()
        case .agents: AgentsView()
        case .brain: BrainView()
        case .settings: SettingsView()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Section.today

    private func badge(_ section: Section) -> Int {
        switch section {
        case .approvals: model.pendingCount
        case .sessions: model.waitingSessions.count
        default: 0
        }
    }

    var body: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                Sidebar(selection: $selection, badge: badge)
                NavigationStack { selection.content }
                    .id(selection)
            }
            .ignoresSafeArea(.container, edges: .top)
        #else
            TabView(selection: $selection) {
                ForEach(Section.allCases) { section in
                    Tab(section.rawValue, systemImage: section.symbol, value: section) {
                        NavigationStack { section.content }
                    }
                    .badge(badge(section))
                }
            }
        #endif
    }
}

#if os(macOS)
    struct Sidebar: View {
        @Environment(AppModel.self) private var model
        @Binding var selection: Section
        let badge: (Section) -> Int

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LogoMark(size: 22)
                    Text("Lighthouse").font(Theme.display(18)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 10)
                .padding(.top, 34)
                .padding(.bottom, 12)
                HStack(spacing: 8) {
                    Dot(color: model.isConnected ? Theme.ok : Theme.crit)
                    Text(model.serverHost)
                        .font(Theme.mono(11.5))
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                .padding(.bottom, 10)
                ForEach(Section.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .frame(width: 18)
                                .foregroundStyle(selection == section ? Theme.lamp : Theme.ink2)
                            Text(section.rawValue).font(Theme.body(14, weight: .medium))
                            Spacer()
                            if badge(section) > 0 {
                                Text("\(badge(section))")
                                    .font(Theme.body(11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .background(Theme.lamp, in: Capsule())
                                    .foregroundStyle(Theme.onLamp)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selection == section ? Theme.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let name = model.ownerName {
                    Text(name).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.ink2)
                        .padding(10)
                }
            }
            .padding(10)
            .frame(width: 232)
            .frame(maxHeight: .infinity)
            .background(Theme.sidebar)
        }
    }
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(maxWidth: 780) {
            PageTitle(title: "Settings")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    OpenLine(color: model.isConnected ? Theme.ok : Theme.crit, label: "Server", value: model.serverHost)
                    Button("Sign out") { Task { await model.signOut() } }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                }
            }
            SectionTitle(text: "Connectors", count: model.connectors.count)
            if model.connectors.isEmpty { Quiet(text: "No connectors configured.") }
            ForEach(model.connectors) { connector in
                Card(padding: 12) {
                    OpenLine(
                        color: connector.connected ? Theme.ok : Theme.crit, label: connector.name,
                        value: connector.connected ? "connected" : "not connected")
                }
            }
            Quiet(text: "Credentials and new connections are managed in the web app.")
        }
    }
}
