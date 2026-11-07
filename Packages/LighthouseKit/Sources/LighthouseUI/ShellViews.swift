import LighthouseKit
import SwiftUI

/// The sign-in of an app whose main content is the web app: the same screen
/// as `RootView` shows, styled on its own.
public struct SignInScreen: View {
    @Environment(AppModel.self) private var model

    public init() {
        LighthouseFonts.register()
    }

    public var body: some View {
        LoginView()
            .tint(Theme.lamp)
            .environment(\.locale, Lang.locale)
            .id(model.language)
    }
}

/// Shown instead of the web app while the server cannot be reached. It stays
/// calm: the app tries again by itself, and the button only hurries it up.
public struct ConnectionProblemView: View {
    let title: String
    let message: String
    let detail: String?
    let retrying: Bool
    let retry: () -> Void

    public init(title: String, message: String, detail: String?, retrying: Bool, retry: @escaping () -> Void) {
        LighthouseFonts.register()
        self.title = title
        self.message = message
        self.detail = detail
        self.retrying = retrying
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogoMark(size: 30)
                .opacity(0.85)
                .padding(.bottom, 4)
            Text(title).font(Theme.display(22)).foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button(tr(retrying ? "Trying again…" : "Try again"), action: retry)
                    .buttonStyle(LampButtonStyle())
                    .disabled(retrying)
                    .keyboardShortcut(.defaultAction)
                if retrying { ProgressView().controlSize(.small) }
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: 440, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .tint(Theme.lamp)
        .environment(\.locale, Lang.locale)
    }
}

/// What needs the owner now: the ready count with its first items, and open
/// critical alerts. Each line opens its place in the web app.
public struct AttentionSummary: View {
    @Environment(AppModel.self) private var model
    let limit: Int
    let open: (WebRoute) -> Void

    public init(limit: Int = 3, open: @escaping (WebRoute) -> Void) {
        LighthouseFonts.register()
        self.limit = limit
        self.open = open
    }

    private func line(_ color: Color, _ name: String, _ detail: String, route: WebRoute) -> some View {
        Button {
            open(route)
        } label: {
            HStack(spacing: 10) {
                Dot(color: color)
                Text(name)
                    .font(Theme.body(13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(detail).font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Permission requests are answered right in the menu bar, so they are not repeated here.
    private var items: [ReadyItem] {
        (model.readyFeed?.items ?? []).filter { $0.kind != "permission" }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.criticalAlerts.prefix(limit)) { alert in
                line(Theme.crit, alert.title, tr("Open"), route: alert.route)
            }
            if let feed = model.readyFeed {
                if feed.total > 0 {
                    line(
                        Theme.lamp, tr("%@ ready for you", String(feed.total)), tr("Open"),
                        route: feed.total == 1 ? feed.items[0].route : WebRoute(.ready))
                    ForEach(items.prefix(limit)) { item in
                        line(Theme.ink3, item.title, "", route: item.route)
                            .padding(.leading, 18)
                    }
                }
            } else if !model.approvals.isEmpty {
                let only = model.approvals.count == 1 ? model.approvals.first : nil
                line(
                    Theme.lamp,
                    model.approvals.count == 1
                        ? tr("1 approval") : tr("%@ approvals", String(model.approvals.count)),
                    tr("Open"), route: only.map { WebRoute.approval($0.id) } ?? WebRoute(.ready))
            }
        }
    }
}
