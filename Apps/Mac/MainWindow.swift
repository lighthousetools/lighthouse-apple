import AppKit
import LighthouseKit
import LighthouseUI
import SwiftUI
import WebKit

/// The main window: the web app, so it looks exactly like in the browser.
/// Sign-in and a lost connection stay native.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(WebShell.self) private var shell

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                Color(nsColor: ShellColors.background)
            case .signedOut:
                SignInScreen()
                    .padding(.top, 28)
                    .background(Color(nsColor: ShellColors.background))
            case .ready:
                ZStack {
                    WebViewHost(webView: shell.webView)
                        .opacity(shell.status == .ready ? 1 : 0)
                    problem
                }
                .background(Color(nsColor: ShellColors.background))
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 960, minHeight: 620)
        .background(WindowStyler())
        .onAppear(perform: configure)
        .onChange(of: model.phase) { configure() }
        .onChange(of: model.serverAddress) { configure() }
        .onChange(of: model.language) { configure() }
        .onChange(of: model.isConnected) { if model.isConnected { shell.serverIsBack() } }
    }

    private func configure() {
        guard model.phase == .ready, let server = model.serverURL, let token = model.webToken else {
            if model.phase == .signedOut { shell.reset() }
            return
        }
        shell.configure(server: server, token: token, language: model.language)
    }

    @ViewBuilder private var problem: some View {
        switch shell.status {
        case .unreachable(let reason):
            ConnectionProblemView(
                title: tr("Lighthouse is not reachable"),
                message: tr("The server at %@ does not answer. Lighthouse tries again by itself.", model.serverHost),
                detail: reason, retrying: shell.retrying, retry: shell.retry
            )
            .padding(.top, 28)
        case .noWebApp:
            ConnectionProblemView(
                title: tr("Lighthouse is not reachable"),
                message: tr(
                    "The server at %@ does not deliver the web app. Set paths.web in lighthouse.toml.",
                    model.serverHost),
                detail: nil, retrying: shell.retrying, retry: shell.retry
            )
            .padding(.top, 28)
        case .loading where shell.retrying:
            ConnectionProblemView(
                title: tr("Lighthouse is not reachable"),
                message: tr("The server at %@ does not answer. Lighthouse tries again by itself.", model.serverHost),
                detail: nil, retrying: true, retry: shell.retry
            )
            .padding(.top, 28)
        default:
            EmptyView()
        }
    }
}

/// Puts the shell's web view into SwiftUI. The view outlives the window.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// Lets the page run up under a transparent title bar, with the window
/// buttons resting on the web app's sidebar.
struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class StylerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.backgroundColor = ShellColors.background
            window.tabbingMode = .disallowed
        }
    }
}
