import LighthouseKit
import SwiftUI

/// Searches the Second Brain, asks it and takes notes.
public struct BrainView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var entries: [EntrySummary] = []
    @State private var answer: AskAnswer?
    @State private var failure: String?
    @State private var asking = false
    @State private var writing = false

    public init() {}

    private func load() async {
        guard let client = model.client else { return }
        do {
            let text = query.trimmingCharacters(in: .whitespaces)
            entries = text.isEmpty ? try await client.recentEntries() : try await client.search(text)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func ask() async {
        guard let client = model.client else { return }
        asking = true
        defer { asking = false }
        do {
            answer = try await client.ask(query)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    public var body: some View {
        List {
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if !query.isEmpty {
                Button(asking ? "Thinking…" : "Ask the Brain") { Task { await ask() } }
                    .disabled(asking)
            }
            if let answer {
                Section("Answer") {
                    Text((try? AttributedString(markdown: answer.answer)) ?? AttributedString(answer.answer))
                        .textSelection(.enabled)
                    if !answer.sources.isEmpty {
                        Text("Based on: \(answer.sources.map(\.title).joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(query.isEmpty ? "Recent" : "Results") {
                if entries.isEmpty {
                    Text("Nothing found.").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    NavigationLink(value: entry.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.headline)
                            Text(entry.snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Brain")
        .navigationDestination(for: UUID.self) { EntryView(id: $0) }
        .searchable(text: $query, prompt: "Search or ask")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: query) { if query.isEmpty { answer = nil; Task { await load() } } }
        .toolbar {
            Button("New note", systemImage: "square.and.pencil") { writing = true }
        }
        .sheet(isPresented: $writing) {
            NoteEditor { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }
}

struct EntryView: View {
    @Environment(AppModel.self) private var model
    let id: UUID
    @State private var entry: EntryDetail?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let failure { Text(failure).foregroundStyle(.red) }
                if let entry { Text(entry.body).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(entry?.title ?? "")
        .task {
            do {
                entry = try await model.client?.entry(id)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $text).frame(minHeight: 160)
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("New note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await model.client?.saveNote(title: title, body: text)
                                onSaved()
                                dismiss()
                            } catch {
                                failure = error.localizedDescription
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
