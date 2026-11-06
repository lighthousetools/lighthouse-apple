import LighthouseKit
import LighthouseUI
import SwiftUI

@main
struct LighthouseMacApp: App {
    @State private var model = AppModel(
        deviceName: Host.current().localizedName ?? "Mac", deviceKind: "mac")

    var body: some Scene {
        Window("Lighthouse", id: "main") {
            RootView().environment(model).frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .task { await model.keepFresh() }
        } label: {
            Image(nsImage: MenuBarIcon.image)
            if model.pendingCount > 0 { Text("\(model.pendingCount)") }
        }
        .menuBarExtraStyle(.window)
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
