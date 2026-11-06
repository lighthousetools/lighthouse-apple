import LighthouseKit
import SwiftUI

/// Chooses between sign-in and the app.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .signedOut:
            LoginView()
        case .ready:
            MainView().task { await model.keepFresh() }
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    private func tab(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack { content() }
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { tab { TodayView() } }
            Tab("Approvals", systemImage: "checkmark.seal") { tab { ApprovalsView() } }
                .badge(model.pendingCount)
            Tab("Sessions", systemImage: "terminal") { tab { SessionsView() } }
            Tab("Agents", systemImage: "sparkles") { tab { AgentsView() } }
            Tab("Brain", systemImage: "brain") { tab { BrainView() } }
            Tab("Settings", systemImage: "gear") { tab { SettingsView() } }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("Server", value: model.serverAddress)
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
