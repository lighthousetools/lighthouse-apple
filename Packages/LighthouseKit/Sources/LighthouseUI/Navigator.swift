import LighthouseKit
import SwiftUI

/// The areas of the app.
public enum Section: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case approvals = "Approvals"
    case sessions = "Sessions"
    case agents = "Agents"
    case brain = "Brain"
    case settings = "Settings"

    public var id: String { rawValue }
    public var title: String { tr(rawValue) }

    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .approvals: "checkmark.shield"
        case .sessions: "terminal"
        case .agents: "square.stack.3d.up"
        case .brain: "brain"
        case .settings: "gearshape"
        }
    }

    /// The same area in the web app.
    public var webRoute: WebRoute {
        WebRoute(WebArea(rawValue: rawValue.lowercased()) ?? .today)
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

/// What commands and shortcuts can reach from outside the views.
@MainActor
@Observable
public final class Navigator {
    public var section = Section.today
    public var showsPalette = false
    public var showsCapture = false
    /// Counts requests, so that the Brain reacts to each one.
    public var newNoteRequests = 0
    /// A place the Mac window should show, for an app that shows the web app.
    /// Whoever shows it sets it back to nil.
    public var requestedRoute: WebRoute?

    public init() {}

    /// Asks for the main window at a place of the web app.
    public func open(_ route: WebRoute) {
        requestedRoute = route
    }

    public func newNote() {
        section = .brain
        newNoteRequests += 1
    }
}
