import LighthouseKit
import SwiftUI

/// Chooses between sign-in and the app.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    public init() {
        LighthouseFonts.register()
    }

    public var body: some View {
        @Bindable var navigator = navigator
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case .signedOut:
                LoginView()
            case .ready:
                MainView()
                    .task { await model.keepFresh() }
                    .sheet(isPresented: $navigator.showsPalette) { CommandPalette() }
            }
        }
        .tint(Theme.lamp)
        .environment(\.locale, Lang.locale)
        .id(model.language)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    private func badge(_ section: Section) -> Int {
        switch section {
        case .approvals: model.pendingCount
        case .sessions: model.waitingSessions.count
        default: 0
        }
    }

    var body: some View {
        @Bindable var navigator = navigator
        #if os(macOS)
            NavigationSplitView {
                List(Section.allCases, selection: Binding($navigator.section)) { section in
                    Label(section.title, systemImage: section.symbol)
                        .font(Theme.body(14, weight: .medium))
                        .badge(badge(section))
                        .tag(section)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 8) {
                        Dot(color: model.isConnected ? Theme.ok : Theme.crit)
                        Text(model.serverHost)
                            .font(Theme.mono(11))
                            .lineLimit(1)
                            .foregroundStyle(Theme.ink3)
                        Spacer()
                    }
                    .padding(14)
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            } detail: {
                NavigationStack { navigator.section.content }
                    .id(navigator.section)
                    .navigationTitle("")
            }
        #else
            TabView(selection: $navigator.section) {
                ForEach(Section.allCases) { section in
                    Tab(section.title, systemImage: section.symbol, value: section) {
                        NavigationStack { section.content }
                    }
                    .badge(badge(section))
                }
            }
        #endif
    }
}

extension Binding {
    /// Offers a required value as the optional selection a list expects.
    fileprivate init(_ base: Binding<Section>) where Value == Section? {
        self.init(get: { base.wrappedValue }, set: { if let value = $0 { base.wrappedValue = value } })
    }
}

/// Everything you can do, from the keyboard.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let action: () -> Void
    }

    private var items: [Item] {
        var items = Section.allCases.map { section in
            Item(id: tr("Go to %@", section.title), symbol: section.symbol) { navigator.section = section }
        }
        items.append(Item(id: tr("New note"), symbol: "square.and.pencil") { navigator.newNote() })
        items.append(Item(id: tr("Quick note"), symbol: "bolt") { navigator.showsCapture = true })
        for agent in model.agents where agent.blocked.isEmpty {
            items.append(Item(id: tr("Run %@", agent.name), symbol: "play") {
                Task { await model.run(agent) }
            })
        }
        let query = text.lowercased()
        return query.isEmpty ? items : items.filter { $0.id.lowercased().contains(query) }
    }

    private func perform(_ item: Item) {
        dismiss()
        item.action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(tr("Search actions"), text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .padding(16)
                .onSubmit { if let first = items.first { perform(first) } }
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        Button {
                            perform(item)
                        } label: {
                            Label(item.id, systemImage: item.symbol)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 480, height: 340)
        .background(Theme.surface)
        .onAppear { focused = true }
        .onExitCommandIfAvailable { dismiss() }
    }
}

extension View {
    @ViewBuilder fileprivate func onExitCommandIfAvailable(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }
}

/// A small window for a thought or a task, reachable from anywhere. On top it
/// shows what waits, so a glance is enough.
public struct QuickCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind = QuickEntryKind.note
    @State private var failure: String?
    @State private var busy = false
    @FocusState private var focused: Bool
    private let open: ((WebRoute) -> Void)?

    /// `open` shows a place of the web app; without it the summary stays hidden.
    public init(open: ((WebRoute) -> Void)? = nil) {
        LighthouseFonts.register()
        self.open = open
    }

    private func save() async {
        let entry = QuickEntry(text: text)
        guard !entry.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            switch kind {
            case .note:
                _ = try await model.client?.createNote(title: entry.title, body: entry.body)
            case .task:
                try await model.createTask(title: entry.title, notes: entry.body)
            }
            text = ""
            failure = nil
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    private var hasSummary: Bool {
        open != nil && (model.pendingCount > 0 || !model.criticalAlerts.isEmpty)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let open, hasSummary {
                AttentionSummary(limit: 2) { route in
                    open(route)
                    dismiss()
                }
                Divider().overlay(Theme.line)
            }
            Picker(tr("Kind"), selection: $kind) {
                Text(tr("Note")).tag(QuickEntryKind.note)
                Text(tr("Task")).tag(QuickEntryKind.task)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(tr(kind == .note ? "Capture a thought…" : "What needs doing?"))
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.ink3)
                        .padding(.leading, 5)
                }
                TextEditor(text: $text)
                    .font(Theme.body(15))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
            }
            .frame(height: 110)
            if let failure { Text(failure).font(Theme.body(12.5)).foregroundStyle(Theme.crit) }
            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(tr(kind == .note ? "Save" : "New task")) { Task { await save() } }
                    .buttonStyle(LampButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(busy || QuickEntry(text: text).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface)
        .tint(Theme.lamp)
        .onAppear { focused = true }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page(maxWidth: 760) {
            PageTitle(title: tr("Settings"))
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    OpenLine(color: model.isConnected ? Theme.ok : Theme.crit, label: tr("Server"), value: model.serverHost)
                    HStack {
                        Text(tr("Language")).font(Theme.body(13.5)).foregroundStyle(Theme.ink)
                        Spacer()
                        Picker(tr("Language"), selection: $model.language) {
                            ForEach(Language.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Button(tr("Sign out")) { Task { await model.signOut() } }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                }
            }
            SectionTitle(text: tr("Connectors"), count: model.connectors.count)
            if model.connectors.isEmpty { Quiet(text: tr("No connectors configured.")) }
            ForEach(model.connectors) { connector in
                OpenLine(
                    color: connector.connected ? Theme.ok : Theme.crit, label: connector.name,
                    value: tr(connector.connected ? "connected" : "not connected"))
            }
            Quiet(text: tr("Credentials and new connections are managed in the web app."))
        }
    }
}
