import Carbon.HIToolbox
import LighthouseKit
import LighthouseUI
import SwiftUI

@main
struct LighthouseMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Lighthouse", id: "main") {
            MainWindow()
                .environment(delegate.model)
                .environment(delegate.navigator)
                .environment(delegate.shell)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1240, height: 800)
        .commands { LighthouseCommands(model: delegate.model, navigator: delegate.navigator, shell: delegate.shell) }

        Window(tr("Quick note"), id: "capture") {
            QuickCaptureView().environment(delegate.model)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)

        MenuBarExtra {
            MenuBarContent()
                .environment(delegate.model)
                .environment(delegate.navigator)
        } label: {
            MenuBarLabel(delegate: delegate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item. It stays alive with the app, so it keeps the connection
/// to the server, takes the global shortcut and opens the main window on request.
struct MenuBarLabel: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    private var model: AppModel { delegate.model }
    private var navigator: Navigator { delegate.navigator }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image)
            if model.pendingCount > 0 { Text("\(model.pendingCount)") }
        }
        .task {
            GlobalShortcut.shared.onPress = { navigator.showsCapture = true }
            GlobalShortcut.shared.register()
        }
        .task(id: model.phase) {
            delegate.requestsChanged()
            if model.phase == .ready { await model.keepFresh() }
        }
        .onChange(of: model.approvals.map(\.id) + model.permissions.map(\.id)) {
            delegate.requestsChanged()
        }
        .onChange(of: navigator.showsCapture) {
            guard navigator.showsCapture else { return }
            openWindow(id: "capture")
            NSApplication.shared.activate()
            navigator.showsCapture = false
        }
        .onChange(of: navigator.requestedRoute) {
            guard let route = navigator.requestedRoute else { return }
            navigator.requestedRoute = nil
            delegate.shell.open(route)
            openWindow(id: "main")
            NSApplication.shared.activate()
        }
    }
}

struct LighthouseCommands: Commands {
    let model: AppModel
    let navigator: Navigator
    let shell: WebShell
    @Environment(\.openWindow) private var openWindow

    private func show(_ route: WebRoute) {
        navigator.open(route)
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("Settings…")) { show(WebRoute(.settings)) }
                .keyboardShortcut(",")
                .disabled(model.phase != .ready)
        }
        CommandGroup(replacing: .newItem) {
            Button(tr("New note")) { shell.send(.newNote) }
                .keyboardShortcut("n")
                .disabled(model.phase != .ready)
            Button(tr("Quick note")) { navigator.showsCapture = true }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button(tr("Reload")) { shell.reload() }
                .keyboardShortcut("r")
                .disabled(model.phase != .ready)
        }
        CommandMenu("Lighthouse") {
            Button(tr("Search actions")) { shell.send(.palette) }
                .keyboardShortcut("k")
            Divider()
            ForEach(Array(WebArea.allCases.enumerated()), id: \.offset) { index, area in
                Button(tr(area.title)) { show(WebRoute(area)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            Button(tr("Change server…")) { Task { await model.signOut() } }
                .disabled(model.phase != .ready)
        }
    }
}

extension WebArea {
    /// The English name, translated with `tr`.
    var title: String {
        switch self {
        case .today: "Today"
        case .approvals: "Approvals"
        case .sessions: "Sessions"
        case .agents: "Agents"
        case .brain: "Brain"
        case .weekly: "Weekly report"
        case .log: "Log"
        case .settings: "Settings"
        }
    }
}

/// Registers ⌥⌘L everywhere on the Mac, for a thought that should not wait.
@MainActor
final class GlobalShortcut {
    static let shared = GlobalShortcut()
    var onPress: () -> Void = {}
    private var reference: EventHotKeyRef?

    func register() {
        guard reference == nil else { return }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalShortcut.shared.onPress() } }
                return noErr
            }, 1, &type, nil, nil)
        let identifier = EventHotKeyID(signature: OSType(0x4C_48_54_53), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey), identifier,
            GetApplicationEventTarget(), 0, &reference)
    }
}

/// The lighthouse as a template image, so it follows the menu bar's color.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            let tower = NSBezierPath()
            tower.move(to: NSPoint(x: 7, y: 16))
            tower.line(to: NSPoint(x: 11, y: 16))
            tower.line(to: NSPoint(x: 10.2, y: 7))
            tower.line(to: NSPoint(x: 7.8, y: 7))
            tower.close()
            tower.fill()
            let roof = NSBezierPath()
            roof.move(to: NSPoint(x: 9, y: 2))
            roof.line(to: NSPoint(x: 11.5, y: 4.5))
            roof.line(to: NSPoint(x: 6.5, y: 4.5))
            roof.close()
            roof.fill()
            NSRect(x: 7.5, y: 5, width: 3, height: 1.4).fill()
            NSRect(x: 2.5, y: 5.2, width: 3.5, height: 1).fill()
            NSRect(x: 12, y: 5.2, width: 3.5, height: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
