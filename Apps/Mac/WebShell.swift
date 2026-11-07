import AppKit
import LighthouseKit
import Observation
import WebKit

/// What the main window shows.
enum ShellStatus: Equatable {
    case idle
    case loading
    case ready
    /// The server did not answer, with the reason for the curious.
    case unreachable(String)
    /// The server answers, but does not deliver the web app.
    case noWebApp
}

/// The web app in the main window. It lives as long as the app, so closing
/// the window keeps the place and reopening it is instant.
@MainActor
@Observable
final class WebShell: NSObject {
    private(set) var status = ShellStatus.idle
    private(set) var retrying = false
    /// The count the web app asked for, once it uses the bridge.
    private(set) var webBadge: Int?

    @ObservationIgnored let webView: ShellWebView
    @ObservationIgnored var onSignedOut: () -> Void = {}
    @ObservationIgnored var onLanguage: (Language) -> Void = { _ in }
    @ObservationIgnored var onNotify: (_ id: String, _ title: String, _ body: String, _ route: WebRoute?) -> Void = {
        _, _, _, _ in
    }
    @ObservationIgnored var onBadge: () -> Void = {}

    @ObservationIgnored private var server: URL?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var language = Language.english
    @ObservationIgnored private var webAdopted = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay = 3
    @ObservationIgnored private var pendingRoute: WebRoute?
    @ObservationIgnored private let defaults: UserDefaults
    private static let routeKey = "web-last-route"
    private static let world = WKContentWorld.world(name: "lighthouse-shell")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = WKWebViewConfiguration()
        // Nothing of the web app reaches the disk: the token comes from the
        // Keychain with every page load.
        configuration.websiteDataStore = .nonPersistent()
        configuration.applicationNameForUserAgent = "LighthouseMac"
        configuration.preferences.isElementFullscreenEnabled = true
        webView = ShellWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = ShellColors.background
        #if DEBUG
            webView.isInspectable = true
        #endif
        let handler = WeakMessageHandler(self)
        let controller = configuration.userContentController
        controller.add(handler, contentWorld: .page, name: Bridge.handlerName)
        controller.add(handler, contentWorld: Self.world, name: Bridge.shellHandlerName)
    }

    /// The route the window showed last.
    var lastRoute: WebRoute {
        WebRoute(hash: defaults.string(forKey: Self.routeKey) ?? "")
    }

    /// Points the web app at a server and a sign-in. Loads only when something
    /// it depends on changed.
    func configure(server: URL, token: String, language: Language) {
        let changed = server != self.server || token != self.token
        self.language = language
        guard changed || status == .idle else {
            installScripts()
            return
        }
        if let current = self.server, current != server { defaults.removeObject(forKey: Self.routeKey) }
        self.server = server
        self.token = token
        installScripts()
        load(pendingRoute ?? lastRoute)
        pendingRoute = nil
    }

    /// Forgets the sign-in, so the next owner starts fresh.
    func reset() {
        token = nil
        server = nil
        webAdopted = false
        webBadge = nil
        retryTask?.cancel()
        status = .idle
        webView.configuration.userContentController.removeAllUserScripts()
        webView.loadHTMLString("", baseURL: nil)
        onBadge()
    }

    private func installScripts() {
        guard let server, let origin = NavigationPolicy.origin(of: server) else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: ShellScript.documentStart(origin: origin, token: token, language: language),
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world))
        controller.addUserScript(
            WKUserScript(
                source: ShellScript.documentEnd(origin: origin), injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: Self.world))
    }

    private func load(_ route: WebRoute) {
        guard let server else { return }
        status = .loading
        webAdopted = false
        var request = URLRequest(url: route.url(on: server))
        request.timeoutInterval = 15
        webView.load(request)
    }

    /// Shows a place of the web app, loading it first if needed.
    func open(_ route: WebRoute) {
        guard server != nil else {
            pendingRoute = route
            return
        }
        if status == .ready {
            webView.evaluateJavaScript(ShellScript.navigate(route), in: nil, in: .page)
        } else {
            load(route)
        }
    }

    /// Sends a command to the web app, such as opening its palette.
    func send(_ command: BridgeCommand) {
        guard status == .ready else { return }
        webView.evaluateJavaScript(ShellScript.command(command), in: nil, in: .page)
    }

    func reload() {
        guard server != nil else { return }
        if status == .ready { webView.reload() } else { load(lastRoute) }
    }

    /// Tries again now rather than waiting for the next automatic attempt.
    func retry() {
        retryTask?.cancel()
        retrying = true
        load(lastRoute)
    }

    /// Called when the app's own connection is back, so the page follows.
    func serverIsBack() {
        if case .unreachable = status { retry() }
    }

    private func fail(_ status: ShellStatus) {
        self.status = status
        retrying = false
        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retrying = true
            self.load(self.lastRoute)
        }
    }

    private func isOnServer(_ frame: WKFrameInfo) -> Bool {
        guard let server, frame.isMainFrame else { return false }
        let origin = frame.securityOrigin
        let port = origin.port == 0 ? nil : origin.port
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        components.port = port
        guard let url = components.url else { return false }
        return NavigationPolicy.sameOrigin(url, server)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard isOnServer(message.frameInfo) else { return }
        if message.name == Bridge.shellHandlerName {
            guard let parsed = try? ShellMessage.parse(message.body) else { return }
            handle(parsed)
        } else if message.name == Bridge.handlerName {
            guard let parsed = try? BridgeMessage.parse(message.body) else { return }
            handle(parsed)
        }
    }

    private func handle(_ message: ShellMessage) {
        switch message {
        case .route(let route):
            defaults.set(route.hash, forKey: Self.routeKey)
        case .dragZone(let active):
            webView.dragZoneActive = active
        case .signedOut:
            onSignedOut()
        case .language(let chosen):
            language = chosen
            onLanguage(chosen)
        }
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .notify(let title, let body, let route, let id):
            onNotify(id ?? UUID().uuidString, title, body, route)
        case .badge(let count):
            webBadge = count
            onBadge()
        case .openExternal(let url):
            NSWorkspace.shared.open(url)
        case .ready:
            webAdopted = true
        }
    }
}

extension WebShell: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { return .download }
        guard let url = action.request.url, let server else { return .cancel }
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decide(url, server: server, isMainFrame: isMainFrame) {
        case .allow:
            return .allow
        case .openExternally:
            if action.navigationType == .linkActivated || action.targetFrame == nil || isMainFrame {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        case .cancel:
            return .cancel
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard response.isForMainFrame else { return response.canShowMIMEType ? .allow : .download }
        if let http = response.response as? HTTPURLResponse {
            if http.statusCode == 404 || http.statusCode == 405 {
                fail(.noWebApp)
                return .cancel
            }
            if http.statusCode >= 500 {
                fail(.unreachable(HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
                return .cancel
            }
        }
        return response.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard server != nil, webView.url?.scheme?.hasPrefix("http") == true else { return }
        status = .ready
        retrying = false
        retryDelay = 3
        retryTask?.cancel()
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        // A cancelled load or one turned into a download is no failure.
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain", [102, 204].contains(error.code) { return }
        guard server != nil else { return }
        if case .noWebApp = status { return }
        fail(.unreachable(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load(lastRoute)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

extension WebShell: WKUIDelegate {
    /// Links that open a new window leave for the browser, the web view stays.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, let server,
            NavigationPolicy.decide(url, server: server, isMainFrame: true) != .cancel
        {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window = webView.window else {
            return panel.runModal() == .OK ? panel.urls : nil
        }
        let answer = await panel.beginSheetModal(for: window)
        return answer == .OK ? panel.urls : nil
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: tr("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

extension WebShell: WKDownloadDelegate {
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String
    ) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = (suggestedFilename as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        var target = folder.appending(path: name.isEmpty ? "Download" : name)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appending(path: suffix.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(suffix)")
            counter += 1
        }
        return target
    }

    func downloadDidFinish(_ download: WKDownload) {
        NSWorkspace.shared.open(
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }
}

/// WebKit keeps its message handlers strongly, so this one holds the shell weakly.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var shell: WebShell?

    init(_ shell: WebShell) {
        self.shell = shell
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { shell?.receive(message) }
    }
}

/// The web view of the window. The strip at the top moves the window where the
/// page has nothing to click, like a title bar would.
final class ShellWebView: WKWebView {
    var dragZoneActive = false

    private func inStrip(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        return fromTop < CGFloat(ShellScript.dragStrip)
    }

    override func mouseDown(with event: NSEvent) {
        guard dragZoneActive, inStrip(event), let window else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2 {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            if action == "Minimize" { window.miniaturize(nil) } else if action != "None" { window.zoom(nil) }
        } else {
            window.performDrag(with: event)
        }
    }
}

/// The page colors of the web app, for what shows before it paints.
enum ShellColors {
    static let background = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0x0A / 255, green: 0x0F / 255, blue: 0x17 / 255, alpha: 1)
            : NSColor(srgbRed: 0xED / 255, green: 0xF0 / 255, blue: 0xF4 / 255, alpha: 1)
    }
}
