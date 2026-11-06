import LighthouseKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AVFoundation
#endif

/// Loads, searches and changes the entries of the Second Brain.
@MainActor
@Observable
final class BrainModel {
    var query = ""
    var entries: [EntrySummary] = []
    var selected: UUID?
    var failure: String?
    var uploading = 0

    func load(_ client: Client?) async {
        guard let client else { return }
        do {
            let text = query.trimmingCharacters(in: .whitespaces)
            entries = text.isEmpty ? try await client.recentEntries() : try await client.search(text)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func newNote(_ client: Client?) async {
        guard let client else { return }
        do {
            let entry = try await client.createNote(title: tr("Untitled"), body: "")
            await load(client)
            selected = entry.id
        } catch {
            failure = error.localizedDescription
        }
    }

    func follow(_ title: String, _ client: Client?) async {
        guard let client else { return }
        do {
            selected = try await client.resolve(title: title)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Reads and uploads files, one after the other, so a failure names its file.
    func upload(_ urls: [URL], _ client: Client?) async {
        guard let client else { return }
        var last: UUID?
        for url in urls {
            uploading += 1
            defer { uploading -= 1 }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                let bytes = try Data(contentsOf: url)
                let entry = try await client.upload(
                    name: url.lastPathComponent,
                    contentType: type ?? "application/octet-stream", bytes: bytes)
                last = entry.id
                failure = nil
            } catch {
                failure = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        await load(client)
        if let last { selected = last }
    }
}

#if os(macOS)
    /// Records a voice note into a temporary file.
    @MainActor
    @Observable
    final class VoiceRecorder {
        private(set) var isRecording = false
        private var recorder: AVAudioRecorder?

        func start() async -> Bool {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
            let url = FileManager.default.temporaryDirectory.appending(
                path: "\(tr("Voice note %@", Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacing(":", with: "-"))).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            ]
            recorder = try? AVAudioRecorder(url: url, settings: settings)
            isRecording = recorder?.record() ?? false
            return isRecording
        }

        func stop() -> URL? {
            recorder?.stop()
            isRecording = false
            defer { recorder = nil }
            return recorder?.url
        }
    }
#endif

/// The Second Brain: a list on one side, a writing surface on the other.
public struct BrainView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator
    @State private var brain = BrainModel()
    @State private var importing = false
    @State private var dropping = false
    #if os(macOS)
        @State private var recorder = VoiceRecorder()
    #endif

    public init() {}

    private var searchBar: some View {
        @Bindable var brain = brain
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField(tr("Search"), text: $brain.query)
                .textFieldStyle(.plain)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
                .onSubmit { Task { await brain.load(app.client) } }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await brain.newNote(app.client) }
            } label: {
                Label(tr("New note"), systemImage: "square.and.pencil")
            }
            .buttonStyle(LampButtonStyle())
            Button {
                importing = true
            } label: {
                Image(systemName: "arrow.up.doc")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel(tr("Upload"))
            .help(tr("Upload"))
            #if os(macOS)
                Button {
                    Task {
                        if recorder.isRecording {
                            if let url = recorder.stop() { await brain.upload([url], app.client) }
                        } else {
                            _ = await recorder.start()
                        }
                    }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic")
                }
                .buttonStyle(QuietButtonStyle(destructive: recorder.isRecording))
                .accessibilityLabel(tr(recorder.isRecording ? "Stop recording" : "Record"))
                .help(tr(recorder.isRecording ? "Stop recording" : "Record"))
            #endif
        }
    }

    private func row(_ entry: EntrySummary) -> some View {
        Button {
            brain.selected = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(Theme.display(14)).foregroundStyle(Theme.ink).lineLimit(2)
                if !plainSnippet(entry.snippet).isEmpty {
                    Text(plainSnippet(entry.snippet))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                }
                Text(entry.updatedAt.dayAndMonth).font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                brain.selected == entry.id ? Theme.lampSoft : .clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                #if os(macOS)
                    PageTitle(title: tr("Brain"), subtitle: tr("What you know, with its source."))
                #endif
                searchBar
                actions.padding(.bottom, 4)
                if brain.uploading > 0 { Quiet(text: tr("Uploading…")) }
                if let failure = brain.failure {
                    Text(failure).font(Theme.body(12.5)).foregroundStyle(Theme.crit)
                }
                SectionTitle(text: tr(brain.query.isEmpty ? "Recent" : "Results"), count: brain.entries.count)
                if brain.entries.isEmpty { Quiet(text: tr("Nothing here yet.")) }
                ForEach(brain.entries) { row($0) }
            }
            .padding(16)
        }
    }

    private var workspace: some View {
        Group {
            if let id = brain.selected {
                EntryWorkspace(id: id, brain: brain).id(id)
            } else {
                DropHint()
            }
        }
    }

    public var body: some View {
        content
            .pageBackground()
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.lamp, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(Theme.lampSoft.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Text(tr("Drop to add to your Brain"))
                                .font(Theme.display(20))
                                .foregroundStyle(Theme.lampInk)
                        }
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await brain.upload(urls, app.client) }
                return true
            } isTargeted: { dropping = $0 }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await brain.upload(urls, app.client) }
                }
            }
            .onChange(of: brain.query) {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    await brain.load(app.client)
                }
            }
            .onChange(of: navigator.newNoteRequests) {
                Task { await brain.newNote(app.client) }
            }
            .task { await brain.load(app.client) }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                list.frame(width: 300)
                Divider().overlay(Theme.line)
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        #else
            @Bindable var brain = brain
            list
                .navigationTitle(tr("Brain"))
                .navigationDestination(item: $brain.selected) { id in
                    EntryWorkspace(id: id, brain: brain)
                }
        #endif
    }
}

/// Turns the start of a Markdown text into one plain line.
func plainSnippet(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline)
        .map { $0.drop { "#>-*+ ".contains($0) } }
        .filter { !$0.isEmpty && !$0.hasPrefix("|") && !$0.hasPrefix("```") }
        .joined(separator: " ")
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "*", with: "")
        .replacingOccurrences(of: "`", with: "")
}

struct DropHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.ink3)
            Text(tr("Pick an entry, or drop files here")).font(Theme.display(17)).foregroundStyle(Theme.ink)
            Text(tr("PDFs, images, audio and text become searchable."))
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One entry: a writing surface that saves itself, a reading view and its original.
struct EntryWorkspace: View {
    @Environment(AppModel.self) private var app
    let id: UUID
    let brain: BrainModel
    @State private var entry: EntryDetail?
    @State private var title = ""
    @State private var text = ""
    @State private var saved = ""
    @State private var savedTitle = ""
    @State private var original: Data?
    @State private var failure: String?
    @State private var confirmingDelete = false
    @State private var reading = false
    @State private var saving = false
    @State private var slashQuery: String?
    @State private var controller = EditorController()

    private var isDirty: Bool { text != saved || title != savedTitle }

    private var matchingCommands: [SlashCommand] {
        guard let query = slashQuery else { return [] }
        return SlashCommand.allCases.filter {
            query.isEmpty || tr($0.rawValue).lowercased().hasPrefix(query)
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            let loaded = try await client.entry(id)
            entry = loaded
            title = loaded.title
            savedTitle = loaded.title
            text = loaded.body
            saved = loaded.body
            if isPreviewable(loaded.original) { original = try await client.original(of: id) }
            reading = loaded.original != nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func isPreviewable(_ name: String?) -> Bool {
        guard let name, let type = UTType(filenameExtension: (name as NSString).pathExtension)
        else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private func save() async {
        guard isDirty, let client = app.client else { return }
        saving = true
        defer { saving = false }
        let (newTitle, newText) = (title, text)
        do {
            try await client.update(entry: id, title: newTitle, body: newText)
            saved = newText
            savedTitle = newTitle
            failure = nil
            await brain.load(client)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func delete() async {
        guard let client = app.client else { return }
        do {
            try await client.delete(entry: id)
            brain.selected = nil
            await brain.load(client)
        } catch {
            failure = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField(tr("Title"), text: $title)
                    .textFieldStyle(.plain)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.ink)
                Picker(tr("Read"), selection: $reading) {
                    Text(tr("Write")).tag(false)
                    Text(tr("Read")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
                .accessibilityLabel(tr("Delete"))
                .help(tr("Delete"))
            }
            if let entry {
                HStack(spacing: 10) {
                    Text(tr(saving || isDirty ? "Saving…" : "Saved"))
                    ForEach(entry.sources, id: \.ref) { Text(tr("from %@", $0.kind)) }
                    Text(entry.type)
                }
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)
            }
            if let failure { Text(failure).font(Theme.body(13)).foregroundStyle(Theme.crit) }
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var commands: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(matchingCommands) { command in
                    Button {
                        controller.apply(command)
                        slashQuery = nil
                    } label: {
                        Label(tr(command.rawValue), systemImage: command.symbol)
                            .font(Theme.body(12.5, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.surface3, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 6)
        }
    }

    private var reader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let data = original, let name = entry?.original { OriginalPreview(data: data, name: name) }
                MarkdownView(source: text, size: 16) { title in
                    Task { await brain.follow(title, app.client) }
                }
                if text.isEmpty && original == nil { Quiet(text: tr("Nothing to read yet.")) }
                backlinks
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var backlinks: some View {
        if let links = entry?.backlinks, !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: tr("Linked from"), count: links.count)
                ForEach(links) { link in
                    Button(link.title) { brain.selected = link.id }
                        .buttonStyle(.plain)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.lampInk)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if reading {
                reader
            } else {
                if !matchingCommands.isEmpty { commands }
                MarkdownEditor(text: $text, slashQuery: $slashQuery, controller: controller)
            }
        }
        .background(Theme.surface)
        .confirmationDialog(tr("Delete for good?"), isPresented: $confirmingDelete) {
            Button(tr("Delete"), role: .destructive) { Task { await delete() } }
        } message: {
            Text(tr("The file, its original and all search data are removed."))
        }
        .task { await load() }
        .task(id: "\(title)\u{0}\(text)") {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { await save() }
        }
        .onDisappear { Task { await save() } }
    }
}

/// Shows the image or PDF behind a file entry.
struct OriginalPreview: View {
    let data: Data
    let name: String

    var body: some View {
        if name.lowercased().hasSuffix(".pdf") {
            PDFPreview(data: data)
                .frame(minHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        } else if let image {
            image
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var image: Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}

#if os(macOS)
    struct PDFPreview: NSViewRepresentable {
        let data: Data

        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(data: data)
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {}
    }
#else
    struct PDFPreview: UIViewRepresentable {
        let data: Data

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(data: data)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
    }
#endif
