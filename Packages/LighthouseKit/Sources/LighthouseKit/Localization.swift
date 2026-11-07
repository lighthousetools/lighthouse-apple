import Foundation

/// The languages of the apps.
public enum Language: String, CaseIterable, Sendable, Identifiable {
    case english = "en"
    case german = "de"

    public var id: String { rawValue }

    /// The name of the language in itself.
    public var name: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// The language that fits the system.
    public static var system: Language {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("de") ? .german : .english
    }
}

/// The active language, read by `tr` while views render.
public enum Lang {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active = Language.system

    public static var current: Language {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }

    public static var locale: Locale { current.locale }
}

/// Translates an English text. `%@` stands for the arguments, in order.
public func tr(_ text: String, _ arguments: String...) -> String {
    var result = Lang.current == .german ? (germanStrings[text] ?? text) : text
    for argument in arguments {
        guard let slot = result.range(of: "%@") else { break }
        result.replaceSubrange(slot, with: argument)
    }
    return result
}

/// Human words for what the server stores as a status.
public func statusName(_ status: String) -> String {
    switch status {
    case "succeeded", "done": tr("Done")
    case "running": tr("Running")
    case "waiting": tr("Waiting for you")
    case "pending": tr("Open")
    case "failed": tr("Failed")
    case "rejected": tr("Not started")
    case "limit_exceeded": tr("Stopped at its limit")
    case "allowed", "approved": tr("Approved")
    case "denied": tr("Denied")
    case "expired": tr("Expired")
    default: status.replacingOccurrences(of: "_", with: " ")
    }
}

/// Turns a slug into words: `morning-brief` becomes `Morning brief`.
public func readableName(_ slug: String) -> String {
    switch slug {
    case "brain-ask": return tr("Question to the Brain")
    case "agent-draft": return tr("New agent")
    default:
        let words = slug.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

let germanStrings: [String: String] = [
    "Good morning": "Guten Morgen",
    "Good afternoon": "Guten Tag",
    "Good evening": "Guten Abend",
    "Week %@": "KW %@",
    "%@ items for you": "%@ Punkte für dich",
    "1 item for you": "1 Punkt für dich",
    "Nothing needs you right now": "Gerade braucht dich nichts",
    "What do you want to know?": "Was möchtest du wissen?",
    "Ask": "Fragen",
    "Thinking…": "Denke nach…",
    "Based on": "Basierend auf",
    "Close": "Schließen",
    "Your briefing": "Dein Briefing",
    "Needs you": "Braucht dich",
    "Nothing is waiting for you.": "Nichts wartet auf dich.",
    "What happened": "Was passiert ist",
    "Nothing has happened yet.": "Bisher ist nichts passiert.",
    "%@ finished at %@": "%@ war um %@ fertig",
    "%@ failed at %@": "%@ ist um %@ fehlgeschlagen",
    "%@ is running": "%@ läuft gerade",
    "%@ waits for your decision": "%@ wartet auf deine Entscheidung",
    "Open for you": "Offen für dich",
    "Approvals": "Freigaben",
    "Waiting sessions": "Wartende Sessions",
    "%@: not connected": "%@: nicht verbunden",
    "Coming up": "Als Nächstes",
    "Nothing is scheduled.": "Nichts geplant.",
    "Costs today": "Kosten heute",
    "No model calls today.": "Heute keine Modellaufrufe.",
    "Today": "Heute",
    "Sessions": "Sessions",
    "Agents": "Agents",
    "Brain": "Brain",
    "Settings": "Einstellungen",
    "Back": "Zurück",
    "This run has no report.": "Dieser Lauf hat keinen Bericht.",
    "Nothing with external effect happens without you.": "Nichts mit Außenwirkung passiert ohne dich.",
    "Approve all": "Alle freigeben",
    "Deny all": "Alle ablehnen",
    "Approve": "Freigeben",
    "Deny": "Ablehnen",
    "Allow": "Erlauben",
    "Why": "Warum",
    "Used before": "Vorher genutzt",
    "This run read external content, which may have shaped the proposal. Check it carefully.":
        "Dieser Lauf hat externe Inhalte gelesen, die den Vorschlag beeinflusst haben können. Prüfe ihn genau.",
    "Show details": "Details zeigen",
    "Hide details": "Details ausblenden",
    "%@ wants to run": "%@ möchte ausführen",
    "Claude Code on your machines.": "Claude Code auf deinen Rechnern.",
    "Machines": "Rechner",
    "No machine is connected.": "Kein Rechner verbunden.",
    "No sessions yet.": "Noch keine Sessions.",
    "Paused": "Pausiert",
    "Online": "Online",
    "Offline": "Offline",
    "Pause": "Pausieren",
    "Resume": "Fortsetzen",
    "Pause all": "Alle pausieren",
    "Resume all": "Alle fortsetzen",
    "New agents are written in the web app.": "Neue Agents schreibst du in der Web-App.",
    "No agents yet.": "Noch keine Agents.",
    "Run now": "Jetzt starten",
    "Manual": "Manuell",
    "What you know, with its source.": "Was du weißt, mit Quelle.",
    "Search": "Suchen",
    "New note": "Neue Notiz",
    "Upload": "Hochladen",
    "Uploading…": "Lade hoch…",
    "Record": "Aufnehmen",
    "Stop recording": "Aufnahme beenden",
    "Recent": "Zuletzt",
    "Results": "Treffer",
    "Nothing here yet.": "Noch nichts hier.",
    "Untitled": "Ohne Titel",
    "Pick an entry, or drop files here": "Wähle einen Eintrag oder zieh Dateien hierher",
    "PDFs, images, audio and text become searchable.": "PDFs, Bilder, Audio und Text werden durchsuchbar.",
    "Drop to add to your Brain": "Loslassen, um es ins Brain zu legen",
    "Write": "Schreiben",
    "Read": "Lesen",
    "Saving…": "Speichere…",
    "Saved": "Gespeichert",
    "Title": "Titel",
    "from %@": "aus %@",
    "Linked from": "Verlinkt von",
    "Delete": "Löschen",
    "Delete for good?": "Endgültig löschen?",
    "The file, its original and all search data are removed.": "Datei, Original und alle Suchdaten werden entfernt.",
    "Nothing to read yet.": "Noch nichts zu lesen.",
    "Heading": "Überschrift",
    "List": "Liste",
    "Task": "Aufgabe",
    "Table": "Tabelle",
    "Code": "Code",
    "Quote": "Zitat",
    "Link": "Link",
    "Language": "Sprache",
    "Server": "Server",
    "Sign out": "Abmelden",
    "Connectors": "Connectors",
    "No connectors configured.": "Keine Connectors eingerichtet.",
    "connected": "verbunden",
    "not connected": "nicht verbunden",
    "Credentials and new connections are managed in the web app.":
        "Zugangsdaten und neue Verbindungen verwaltest du in der Web-App.",
    "Connect to the server you run.": "Verbinde dich mit deinem Server.",
    "Server address": "Serveradresse",
    "Password": "Passwort",
    "Sign in": "Anmelden",
    "Signing in…": "Melde an…",
    "Connected to %@": "Verbunden mit %@",
    "No connection to %@": "Keine Verbindung zu %@",
    "All quiet": "Alles ruhig",
    "%@ approvals": "%@ Freigaben",
    "1 approval": "1 Freigabe",
    "Open": "Öffnen",
    "Open Lighthouse": "Lighthouse öffnen",
    "Quit": "Beenden",
    "Sign in in the main window.": "Melde dich im Hauptfenster an.",
    "Services": "Dienste",
    "Done": "Fertig",
    "Running": "Läuft",
    "Waiting for you": "Wartet auf dich",
    "Failed": "Fehlgeschlagen",
    "Not started": "Nicht gestartet",
    "Stopped at its limit": "Am Limit gestoppt",
    "Approved": "Freigegeben",
    "Denied": "Abgelehnt",
    "Expired": "Abgelaufen",
    "Question to the Brain": "Frage ans Brain",
    "New agent": "Neuer Agent",
    "Search actions": "Aktionen suchen",
    "Go to %@": "Gehe zu %@",
    "Run %@": "%@ starten",
    "Quick note": "Schnellnotiz",
    "Capture a thought…": "Halte einen Gedanken fest…",
    "Save": "Sichern",
    "Cancel": "Abbrechen",
    "Voice note %@": "Sprachnotiz %@",
    "Approval needed": "Freigabe nötig",
    "%@ wants to use %@": "%@ möchte %@ nutzen",
    "Lighthouse is not reachable": "Lighthouse ist nicht erreichbar",
    "The server at %@ does not answer. Lighthouse tries again by itself.": "Der Server unter %@ antwortet nicht. Lighthouse versucht es von selbst wieder.",
    "The server at %@ does not deliver the web app. Set paths.web in lighthouse.toml.": "Der Server unter %@ liefert die Web-App nicht aus. Setze paths.web in lighthouse.toml.",
    "Try again": "Erneut versuchen",
    "Trying again…": "Versuche es erneut…",
    "Change server…": "Server wechseln…",
    "Reload": "Neu laden",
    "Settings…": "Einstellungen…",
    "Weekly report": "Wochenbericht",
    "Log": "Protokoll",
]
