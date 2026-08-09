import AppKit
import PlynnKit
import SwiftUI

// MARK: - Dictionary

struct DictionaryView: View {
    let store: PersonalStore
    @State private var terms: [PersonalStore.Term] = []
    @State private var newTerm = ""
    @State private var newAliases = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Term (e.g. Plynn)", text: $newTerm)
                    TextField("Heard as (comma-separated, optional)", text: $newAliases)
                    Button("Add") { add() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Terms are enforced in every transcript. Aliases catch what the recognizer hears instead — \"plin\" → \"Plynn\".")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if terms.isEmpty {
                    Text("No terms yet").foregroundStyle(.secondary)
                }
                ForEach(terms) { term in
                    HStack {
                        Text(term.text).fontWeight(.medium)
                        if !term.aliases.isEmpty {
                            Text(term.aliases.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            try? store.deleteTerm(id: term.id)
                            reload()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section {
                Button("Import CSV…") { importCSV() }
                Text("One term per line: term,alias1,alias2")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func add() {
        let aliases = newAliases.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try? store.addTerm(
            text: newTerm.trimmingCharacters(in: .whitespaces), aliases: aliases)
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
                HStack {
                    TextField("Say (e.g. my email)", text: $newTrigger)
                    TextField("Inserts", text: $newExpansion)
                    Button("Add") { add() }
                        .disabled(
                            newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                                || newExpansion.isEmpty)
                }
            } footer: {
                Text("Speak the trigger phrase anywhere in a dictation and it becomes the full text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if snippets.isEmpty {
                    Text("No snippets yet").foregroundStyle(.secondary)
                }
                ForEach(snippets) { snippet in
                    HStack {
                        Text(snippet.trigger).fontWeight(.medium)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(snippet.expansion).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            try? store.deleteSnippet(id: snippet.id)
                            reload()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
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

// MARK: - History

struct HistoryView: View {
    let store: PersonalStore
    @State private var entries: [PersonalStore.HistoryEntry] = []
    @State private var stats: PersonalStore.Stats?
    @State private var search = ""
    @State private var copiedID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            if let stats {
                HStack(spacing: 24) {
                    stat("\(stats.sessions)", "dictations")
                    stat("\(stats.words)", "words")
                    stat(String(format: "%.1f min", stats.seconds / 60), "spoken")
                }
                .padding(.vertical, 12)
            }
            Divider()
            TextField("Search history", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onChange(of: search) { _, _ in reload() }
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.formatted).lineLimit(2)
                    HStack {
                        Text(entry.timestamp, style: .relative) + Text(" ago")
                        Text("·")
                        Text(appName(entry.app))
                        if entry.engine == "wispr-flow" {
                            Text("Wispr")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        if copiedID == entry.id {
                            Text("Copied").foregroundStyle(.green)
                        }
                        Button {
                            copy(entry)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy transcription")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { copy(entry) }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Text("Click a row to copy").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Clear History", role: .destructive) {
                    try? store.clearHistory()
                    reload()
                }
            }
            .padding(8)
        }
        .frame(minWidth: 420, minHeight: 380)  // flexible: standalone window or Settings tab
        .onAppear { reload() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let name = Bundle(url: url)?.localizedName
        else { return bundleID }
        return name
    }

    private func copy(_ entry: PersonalStore.HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.formatted, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func reload() {
        let q = search.trimmingCharacters(in: .whitespaces)
        entries = (try? store.history(limit: 200, matching: q.isEmpty ? nil : q)) ?? []
        stats = try? store.stats()
    }
}

extension Bundle {
    var localizedName: String? {
        object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}

@MainActor
final class HistoryWindowController {
    private var window: NSWindow?
    private let store: PersonalStore

    init(store: PersonalStore) { self.store = store }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "Dictation History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(store: store))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
