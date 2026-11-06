import LighthouseKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Loads, searches and changes the entries of the Second Brain.
@MainActor
@Observable
final class BrainModel {
    var query = ""
    var entries: [EntrySummary] = []
    var selected: UUID?
    var answer: AskAnswer?
    var failure: String?
    var busy = false
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

    func ask(_ client: Client?) async {
        guard let client, !query.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            answer = try await client.ask(query)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func newNote(_ client: Client?) async {
        guard let client else { return }
        do {
            let entry = try await client.createNote(title: "Untitled", body: "")
            await load(client)
            selected = entry.id
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

/// The Second Brain: a list on one side, a Markdown workspace on the other.
public struct BrainView: View {
    @Environment(AppModel.self) private var app
    @State private var brain = BrainModel()
    @State private var importing = false
    @State private var dropping = false

    public init() {}

    private var searchBar: some View {
        @Bindable var brain = brain
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField("Search or ask", text: $brain.query)
                .textFieldStyle(.plain)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
                .onSubmit { Task { await brain.load(app.client) } }
            if !brain.query.isEmpty {
                Button(brain.busy ? "…" : "Ask") { Task { await brain.ask(app.client) } }
                    .buttonStyle(.plain)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.lampInk)
            }
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
                Label("New note", systemImage: "square.and.pencil")
            }
            .buttonStyle(LampButtonStyle())
            Button {
                importing = true
            } label: {
                Label(brain.uploading > 0 ? "Uploading…" : "Upload", systemImage: "arrow.up.doc")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    private func row(_ entry: EntrySummary) -> some View {
        Button {
            brain.selected = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Tag(text: entry.original == nil ? entry.type : "file")
                    Text(entry.updatedAt.formatted(.dateTime.day().month()))
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.ink3)
                }
                Text(entry.title).font(Theme.display(14)).foregroundStyle(Theme.ink).lineLimit(2)
                if !plainSnippet(entry.snippet).isEmpty {
                    Text(plainSnippet(entry.snippet))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                brain.selected == entry.id ? Theme.lampSoft : Theme.surface,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                #if os(macOS)
                    PageTitle(title: "Brain")
                #endif
                searchBar
                actions
                if let failure = brain.failure {
                    Text(failure).font(Theme.body(12.5)).foregroundStyle(Theme.crit)
                }
                if let answer = brain.answer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANSWER").font(Theme.mono(11)).tracking(0.8).foregroundStyle(Theme.lampInk)
                        MarkdownView(source: answer.answer, size: 14)
                        if !answer.sources.isEmpty {
                            Text("Based on \(answer.sources.map(\.title).joined(separator: ", "))")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .padding(12)
                    .background(Theme.lampSoft, in: RoundedRectangle(cornerRadius: 12))
                }
                SectionTitle(text: brain.query.isEmpty ? "Recent" : "Results", count: brain.entries.count)
                if brain.entries.isEmpty { Quiet(text: "Nothing here yet.") }
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
                        .background(Theme.lampSoft.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Text("Drop to add to your Brain")
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
                if brain.query.isEmpty {
                    brain.answer = nil
                    Task { await brain.load(app.client) }
                }
            }
            .task { await brain.load(app.client) }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                list.frame(width: 320)
                Divider().overlay(Theme.line)
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        #else
            @Bindable var brain = brain
            list
                .navigationTitle("Brain")
                .navigationDestination(item: $brain.selected) { id in
                    EntryWorkspace(id: id, brain: brain)
                }
        #endif
    }
}

struct DropHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.lamp)
            Text("Pick an entry, or drop files here").font(Theme.display(17)).foregroundStyle(Theme.ink)
            Text("PDFs, images, audio and text become searchable.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case split = "Split"
    case preview = "Preview"
    var id: String { rawValue }
}

/// One entry: title, Markdown editor, live preview and its original.
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
    #if os(macOS)
        @State private var mode = EditorMode.split
    #else
        @State private var mode = EditorMode.preview
    #endif

    private var isDirty: Bool { text != saved || title != savedTitle }
    private var isFile: Bool { entry?.original != nil }

    private func load() async {
        guard let client = app.client else { return }
        do {
            let loaded = try await client.entry(id)
            entry = loaded
            title = loaded.title
            savedTitle = loaded.title
            text = loaded.body
            saved = loaded.body
            if loaded.original != nil, isPreviewable(loaded.original) {
                original = try await client.original(of: id)
            }
            if loaded.body.isEmpty && loaded.original == nil { mode = .edit }
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
        do {
            try await client.update(entry: id, title: title, body: text)
            saved = text
            savedTitle = title
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("View", selection: $mode) {
                    ForEach(EditorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
                Text(isDirty ? "Unsaved" : "Saved").font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                Button("Save") { Task { await save() } }
                    .buttonStyle(LampButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(QuietButtonStyle(destructive: true))
                .accessibilityLabel("Delete")
            }
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
            if let entry {
                HStack(spacing: 8) {
                    Tag(text: entry.type)
                    ForEach(entry.sources, id: \.ref) { source in
                        Text("from \(source.kind)").font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                    }
                    Text(entry.updated.formatted(.dateTime.day().month().hour().minute()))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            if let failure { Text(failure).font(Theme.body(13)).foregroundStyle(Theme.crit) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(Theme.mono(13.5))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(Theme.surface2)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data = original, let name = entry?.original { OriginalPreview(data: data, name: name) }
                MarkdownView(source: text)
                if text.isEmpty && original == nil {
                    Text("Nothing to preview yet.").font(Theme.body(14)).foregroundStyle(Theme.ink3)
                }
            }
            .padding(22)
        }
        .background(Theme.surface)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            switch mode {
            case .edit: editor
            case .preview: preview
            case .split:
                HStack(spacing: 0) {
                    editor
                    Divider().overlay(Theme.line)
                    preview
                }
            }
        }
        .background(Theme.background)
        .confirmationDialog("Delete for good?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The file, its original and all search data are removed.")
        }
        .task { await load() }
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
