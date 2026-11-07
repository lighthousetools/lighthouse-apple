import Foundation

/// The scripts the Mac app adds to the web app. They run in a content world of
/// their own, so the page neither sees them nor can send their messages.
public enum ShellScript {
    /// The keys under which the web app keeps its sign-in and its language.
    public static let tokenKey = "lighthouse.token"
    public static let languageKey = "lighthouse.language"
    /// The height of the strip at the top that moves the window, in points.
    public static let dragStrip = 28

    /// A JavaScript string literal, safe for any text.
    static func literal(_ text: String?) -> String {
        guard let text else { return "null" }
        let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
        let encoded = data.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        // Line separators end a statement in older engines.
        return encoded.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Runs before any script of the page. Hands over the token from the
    /// Keychain, so the owner signs in once, and reports what the window keeps.
    public static func documentStart(origin: String, token: String?, language: Language) -> String {
        """
        (() => {
          const origin = \(literal(origin));
          const token = \(literal(token));
          const language = \(literal(language.rawValue));
          if (location.origin !== origin) return;
          const post = (message) => {
            try { webkit.messageHandlers.\(Bridge.shellHandlerName).postMessage(message); } catch {}
          };
          const read = (key) => { try { return localStorage.getItem(key); } catch { return null; } };
          try {
            if (token !== null && read(\(literal(tokenKey))) !== token) localStorage.setItem(\(literal(tokenKey)), token);
            localStorage.setItem(\(literal(languageKey)), language);
          } catch {}
          let lastToken = read(\(literal(tokenKey)));
          let lastLanguage = language;
          setInterval(() => {
            const current = read(\(literal(tokenKey)));
            if (lastToken !== null && current === null) post({ type: "signedOut" });
            lastToken = current;
            const chosen = read(\(literal(languageKey)));
            if (chosen && chosen !== lastLanguage) {
              lastLanguage = chosen;
              post({ type: "language", value: chosen });
            }
          }, 1000);
          const report = () => post({ type: "route", hash: location.hash });
          addEventListener("hashchange", report);
          addEventListener("DOMContentLoaded", report);
          const interactive = "a, button, input, textarea, select, label, summary, kbd, [role], [contenteditable], [tabindex]";
          let zone = false;
          const setZone = (active) => {
            if (active !== zone) { zone = active; post({ type: "dragZone", active }); }
          };
          addEventListener("mousemove", (event) => {
            const target = event.target instanceof Element ? event.target : null;
            setZone(event.clientY < \(dragStrip) && !(target && target.closest(interactive)));
          }, { capture: true, passive: true });
          document.addEventListener("mouseleave", () => setZone(false));
        })();
        """
    }

    /// Runs once the page is parsed. Marks the document as running in the Mac
    /// app and keeps the sidebar clear of the window buttons.
    public static func documentEnd(origin: String) -> String {
        """
        (() => {
          if (location.origin !== \(literal(origin))) return;
          document.documentElement.dataset.nativeShell = "mac";
          const style = document.createElement("style");
          style.textContent = `\(css)`;
          document.head.appendChild(style);
        })();
        """
    }

    static let css = """
        :root[data-native-shell="mac"] { --native-titlebar-height: 28px; --native-controls-width: 78px; }
        :root[data-native-shell="mac"] .layout > .sidebar { padding-top: 46px; }
        """

    /// Sends a command to the page. A web app that adopted the bridge cancels
    /// the event; otherwise the app falls back to what the web app already knows.
    public static func command(_ command: BridgeCommand) -> String {
        let fallback: String
        switch command {
        case .palette:
            fallback =
                #"window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, bubbles: true, cancelable: true }));"#
        case .newNote:
            fallback = ##"location.hash = "#brain/new";"##
        }
        return """
            (() => {
              const event = new CustomEvent(\(literal(Bridge.commandEvent)), { detail: { command: \(literal(command.rawValue)) }, cancelable: true });
              if (window.dispatchEvent(event)) { \(fallback) }
            })();
            """
    }

    /// Moves the web app to a route without reloading it.
    public static func navigate(_ route: WebRoute) -> String {
        "location.hash = \(literal(route.hash));"
    }
}
