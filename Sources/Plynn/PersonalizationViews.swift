import AppKit
import PlynnKit
import SwiftUI

// MARK: - Home (transcription history + stats)

struct HomeView: View {
    let store: PersonalStore
    @State private var entries: [PersonalStore.HistoryEntry] = []
    @State private var stats: PersonalStore.Stats?
    @State private var search = ""
    @State private var copiedID: Int64?
    /// Bundle ID → (name, icon). Populated off-body in reload(); bundle
    /// lookups are too expensive for row bodies.
    @State private var apps: [String: (name: String, icon: NSImage)] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                statCard(value: "\(stats?.sessions ?? 0)", label: "Dictations")
                statCard(value: "\(stats?.words ?? 0)", label: "Words")
                statCard(
                    value: String(format: "%.0f min", (stats?.seconds ?? 0) / 60),
                    label: "Time spoken")
            }
            .padding(20)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcriptions", text: $search)
                    .textFieldStyle(.plain)
                    .onChange(of: search) { _, _ in reload() }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            if entries.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No dictations yet" : "No matches",
                    systemImage: "waveform",
                    description: Text(
                        search.isEmpty
                            ? "Hold fn in any text field and start talking."
                            : "Try a different search."))
                .frame(maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    row(entry)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.top, 8)
            }

            Divider()
            HStack {
                Text("\(entries.count) shown").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Clear History", role: .destructive) {
                    try? store.clearHistory()
                    reload()
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .onAppear { reload() }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ entry: PersonalStore.HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let app = apps[entry.app] {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.formatted).lineLimit(3)
                HStack(spacing: 6) {
                    Text(apps[entry.app]?.name ?? entry.app)
                    Text("·")
                    (Text(entry.timestamp, style: .relative) + Text(" ago"))
                    if entry.engine == "wispr-flow" {
                        Text("Wispr")
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    if entry.engine == "command" {
                        Text("Command")
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                copy(entry)
            } label: {
                Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedID == entry.id ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy transcription")
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { copy(entry) }
    }

    private func copy(_ entry: PersonalStore.HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.formatted, forType: .string)
        withAnimation { copiedID = entry.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { withAnimation { copiedID = nil } }
        }
    }

    private func reload() {
        let q = search.trimmingCharacters(in: .whitespaces)
        entries = (try? store.history(limit: 500, matching: q.isEmpty ? nil : q)) ?? []
        stats = try? store.stats()
        // Resolve icons/names once per unique bundle ID, off the row bodies.
        for bundleID in Set(entries.map(\.app)) where apps[bundleID] == nil {
            guard
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { continue }
            let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)?
                .replacingOccurrences(of: ".app", with: "") ?? bundleID
            apps[bundleID] = (name, NSWorkspace.shared.icon(forFile: url.path))
        }
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    let store: PersonalStore
    @State private var terms: [PersonalStore.Term] = []
    @State private var newTerm = ""
    @State private var newAliases = ""

    var body: some View {
        Form {
            Section {
                TextField("Term", text: $newTerm, prompt: Text("Plynn"))
                TextField(
                    "Heard as", text: $newAliases,
                    prompt: Text("plin, plyn (optional, comma-separated)"))
                Button("Add to Dictionary") { add() }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Terms are enforced in every transcript. Aliases catch what the recognizer hears instead. Plynn also learns automatically when you correct a word right after pasting.")
            }
            Section("\(terms.count) terms") {
                if terms.isEmpty {
                    Text("No terms yet").foregroundStyle(.secondary)
                }
                ForEach(terms) { term in
                    LabeledContent {
                        HStack {
                            Text(term.aliases.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                try? store.deleteTerm(id: term.id)
                                reload()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } label: {
                        Text(term.text)
                    }
                }
            }
            Section {
                Button("Import CSV…") { importCSV() }
            } footer: {
                Text("One term per line: term,alias1,alias2")
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func add() {
        let aliases = newAliases.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try? store.addTerm(text: newTerm.trimmingCharacters(in: .whitespaces), aliases: aliases)
        newTerm = ""
        newAliases = ""
        reload()
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
            let csv = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        try? store.importTermsCSV(csv)
        reload()
    }

    private func reload() { terms = (try? store.terms()) ?? [] }
}

// MARK: - Snippets

struct SnippetsView: View {
    let store: PersonalStore
    @State private var snippets: [PersonalStore.Snippet] = []
    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        Form {
            Section {
                TextField("Say", text: $newTrigger, prompt: Text("my email"))
                TextField("Inserts", text: $newExpansion, prompt: Text("carlton@example.com"))
                Button("Add Snippet") { add() }
                    .disabled(
                        newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                            || newExpansion.isEmpty)
            } footer: {
                Text("Speak the trigger phrase anywhere in a dictation and the full text is inserted.")
            }
            Section("\(snippets.count) snippets") {
                if snippets.isEmpty {
                    Text("No snippets yet").foregroundStyle(.secondary)
                }
                ForEach(snippets) { snippet in
                    LabeledContent {
                        HStack {
                            Text(snippet.expansion).foregroundStyle(.secondary).lineLimit(1)
                            Button(role: .destructive) {
                                try? store.deleteSnippet(id: snippet.id)
                                reload()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } label: {
                        Text(snippet.trigger)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func add() {
        try? store.addSnippet(
            trigger: newTrigger.trimmingCharacters(in: .whitespaces), expansion: newExpansion)
        newTrigger = ""
        newExpansion = ""
        reload()
    }

    private func reload() { snippets = (try? store.snippets()) ?? [] }
}
