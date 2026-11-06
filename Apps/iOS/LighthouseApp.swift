import LighthouseKit
import LighthouseUI
import SwiftUI
import UIKit

@main
struct LighthouseApp: App {
    @State private var model = AppModel(deviceName: UIDevice.current.name, deviceKind: "ios")
    @State private var navigator = Navigator()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model).environment(navigator)
        }
    }
}
