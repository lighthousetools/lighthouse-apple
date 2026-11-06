import Carbon.HIToolbox
import LighthouseKit
import LighthouseUI
import SwiftUI

@main
struct LighthouseMacApp: App {
    @State private var model = AppModel(
        deviceName: Host.current().localizedName ?? "Mac", deviceKind: "mac")
    @State private var navigator = Navigator()

    var body: some Scene {
        Window("Lighthouse", id: "main") {
            RootView()
                .environment(model)
                .environment(navigator)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 800)
        .commands { LighthouseCommands(navigator: navigator) }

        Window(tr("Quick note"), id: "capture") {
            QuickCaptureView().environment(model)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(navigator)
                .task { await model.keepFresh() }
        } label: {
            MenuBarLabel(model: model, navigator: navigator)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item. It stays alive with the app, so it also takes the
/// global shortcut.
struct MenuBarLabel: View {
    let model: AppModel
    let navigator: Navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image)
            if model.pendingCount > 0 { Text("\(model.pendingCount)") }
        }
        .task {
            GlobalShortcut.shared.onPress = { navigator.showsCapture = true }
            GlobalShortcut.shared.register()
        }
        .onChange(of: navigator.showsCapture) {
            guard navigator.showsCapture else { return }
            openWindow(id: "capture")
            NSApplication.shared.activate()
            navigator.showsCapture = false
        }
    }
}

struct LighthouseCommands: Commands {
    let navigator: Navigator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(tr("New note")) { navigator.newNote() }
                .keyboardShortcut("n")
            Button(tr("Quick note")) { navigator.showsCapture = true }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandMenu("Lighthouse") {
            Button(tr("Search actions")) { navigator.showsPalette = true }
                .keyboardShortcut("k")
            Divider()
            ForEach(Array(Section.allCases.enumerated()), id: \.offset) { index, section in
                Button(section.title) { navigator.section = section }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
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
