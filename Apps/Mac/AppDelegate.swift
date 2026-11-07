import AppKit
import LighthouseKit
import LighthouseUI
import UserNotifications

/// Owns what lives as long as the app: the model, the web app of the main
/// window and the notifications. Both work while the window is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(
        store: KeychainTokenStore(service: AppDelegate.keychainService),
        deviceName: Host.current().localizedName ?? "Mac", deviceKind: "mac")
    let navigator = Navigator()
    let shell = WebShell()
    private var tracker = RequestTracker()
    private var askedForNotifications = false
    nonisolated private static let routeKey = "route"

    /// The release app shares the service of the iOS app; any other bundle
    /// identifier keeps its own sign-in.
    private static var keychainService: String {
        let identifier = Bundle.main.bundleIdentifier ?? "tools.lighthouse.mac"
        return identifier == "tools.lighthouse.mac" ? KeychainTokenStore.defaultService : identifier
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        shell.onNotify = { [weak self] id, title, body, route in
            self?.notify(id: id, title: title, body: body, route: route)
        }
        shell.onBadge = { [weak self] in self?.updateBadge() }
        shell.onSignedOut = { [weak self] in
            guard let self else { return }
            Task { await self.model.signOut() }
        }
        shell.onLanguage = { [weak self] language in
            guard let self, self.model.language != language else { return }
            self.model.language = language
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true
    }

    /// Looks for new requests after each refresh and announces them.
    func requestsChanged() {
        guard model.phase == .ready else {
            tracker = RequestTracker()
            return
        }
        // The first look after sign-in or launch only learns what is already there.
        guard model.hasLoaded else { return }
        let candidates = RequestNotice.candidates(
            ready: model.readyFeed, approvals: model.approvals, permissions: model.permissions,
            alerts: model.alerts)
        // While the web app runs and uses the bridge, it announces ready items
        // itself, with the same keys; the app adds what it does not announce.
        let webAnnounces = shell.webAnnounces
        for notice in tracker.fresh(candidates) where !(webAnnounces && notice.webAnnounces) {
            notify(id: notice.key, title: notice.title, body: notice.body, route: notice.route)
        }
        updateBadge()
    }

    /// The web app's own count wins once it sends one.
    func updateBadge() {
        let count = model.phase == .ready ? (shell.webBadge ?? model.pendingCount) : 0
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    private func notify(id: String, title: String, body: String, route: WebRoute?) {
        let center = UNUserNotificationCenter.current()
        Task {
            if !askedForNotifications {
                askedForNotifications = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let route { content.userInfo = [Self.routeKey: route.hash] }
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// While the window is in front, the web app shows what is new itself.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { NSApp.isActive ? [.list] : [.banner, .list, .sound] }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let hash = response.notification.request.content.userInfo[Self.routeKey] as? String
        await MainActor.run {
            navigator.open(hash.map(WebRoute.init(hash:)) ?? shell.lastRoute)
        }
    }
}
