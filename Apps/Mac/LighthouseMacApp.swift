import LighthouseKit
import LighthouseUI
import SwiftUI

@main
struct LighthouseMacApp: App {
    @State private var model = AppModel(
        deviceName: Host.current().localizedName ?? "Mac", deviceKind: "mac")

    var body: some Scene {
        Window("Lighthouse", id: "main") {
            RootView().environment(model).frame(minWidth: 720, minHeight: 520)
        }
        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .task { await model.keepFresh() }
        } label: {
            Image(systemName: model.pendingCount > 0 ? "lightbulb.max.fill" : "lightbulb")
            if model.pendingCount > 0 { Text("\(model.pendingCount)") }
        }
        .menuBarExtraStyle(.window)
    }
}
