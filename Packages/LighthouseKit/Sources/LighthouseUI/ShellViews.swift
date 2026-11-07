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
