import AppKit
import PlynnKit
import SwiftUI

/// The Notes tab: every recorded meeting, with a Notes / Transcript viewer.
struct MeetingsView: View {
    let store: PersonalStore
    @State private var meetings: [PersonalStore.Meeting] = []
    @State private var selectedID: Int64?
    @State private var pane: Pane = .notes
    @State private var copied = false

    enum Pane: String, CaseIterable { case notes = "Notes", transcript = "Transcript" }

    private var selected: PersonalStore.Meeting? {
        meetings.first { $0.id == selectedID }
    }

    var body: some View {
        if meetings.isEmpty {
            ContentUnavailableView {
                Label("No meetings yet", systemImage: "waveform.badge.mic")
            } description: {
                Text("Triple-tap fn to start recording a meeting. Plynn captures both sides of the call, transcribes it on your Mac, and writes the notes.")
            }
            .onAppear { reload() }
        } else {
            HSplitView {
                list
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                detail
                    .frame(minWidth: 360)
            }
            .onAppear { reload() }
        }
    }

    // MARK: List

    private var list: some View {
        List(meetings, selection: $selectedID) { m in
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(m.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("·")
                    Text(Self.duration(m.durationSeconds))
                    statusBadge(m.status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .tag(m.id)
        }
        .listStyle(.sidebar)
        .onChange(of: meetings.count) { _, _ in
            if selectedID == nil { selectedID = meetings.first?.id }
        }
        .task {
            // Notes are written a little after the meeting ends; poll gently
            // while any meeting is still summarizing so the pane fills in.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if meetings.contains(where: { $0.status == .summarizing || $0.status == .recording }) {
                    reload()
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PersonalStore.Meeting.Status) -> some View {
        switch status {
        case .recording:
            Label("Recording", systemImage: "record.circle").foregroundStyle(.red)
        case .summarizing:
            Label("Writing notes", systemImage: "sparkles").foregroundStyle(.blue)
        case .failed:
            Label("Summary pending", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        case .ready:
            EmptyView()
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let m = selected {
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Spacer()
                    Button {
                        copyCurrent(m)
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PersonalStore.meetingsDirectory())
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        try? store.deleteMeeting(id: m.id)
                        selectedID = nil
                        reload()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this meeting")
                }
                .padding(12)
                Divider()
                ScrollView {
                    Group {
                        switch pane {
                        case .notes:
                            if let notes = m.notes {
                                MarkdownView(text: notes)
                            } else {
                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text(m.status == .recording ? "Recording…" : "Writing notes…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 200)
                            }
                        case .transcript:
                            if m.transcript.isEmpty {
                                Text("Transcript will appear when the meeting ends.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 200)
                            } else {
                                Text(m.transcript)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        } else {
            ContentUnavailableView("Select a meeting", systemImage: "sidebar.left")
        }
    }

    private func copyCurrent(_ m: PersonalStore.Meeting) {
        let text = pane == .notes ? (m.notes ?? "") : m.transcript
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
    }

    private func reload() {
        meetings = (try? store.meetings()) ?? []
        if selectedID == nil { selectedID = meetings.first?.id }
    }

    static func duration(_ s: Double) -> String {
        let m = Int(s) / 60
        return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)m"
    }
}

/// Dependency-free Markdown renderer for the shapes our summarizer emits:
/// headings, bullets (incl. task boxes), and paragraphs with inline styles.
/// Each block goes through AttributedString(markdown:) for bold/italic/code.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private enum Block {
        case h1(String), h2(String), h3(String)
        case bullet(String, checked: Bool?)
        case rule
        case paragraph(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("### ") { flush(); out.append(.h3(String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { flush(); out.append(.h2(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { flush(); out.append(.h1(String(line.dropFirst(2)))) }
            else if line == "---" || line == "***" { flush(); out.append(.rule) }
            else if line.hasPrefix("- [ ] ") { flush(); out.append(.bullet(String(line.dropFirst(6)), checked: false)) }
            else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flush(); out.append(.bullet(String(line.dropFirst(6)), checked: true))
            }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); out.append(.bullet(String(line.dropFirst(2)), checked: nil))
            }
            else { para.append(line) }
        }
        flush()
        return out
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .h1(let s):
            inline(s).font(.system(size: 24, weight: .bold, design: .rounded)).padding(.bottom, 4)
        case .h2(let s):
            inline(s).font(.system(size: 17, weight: .semibold, design: .rounded)).padding(.top, 8)
        case .h3(let s):
            inline(s).font(.system(size: 14, weight: .semibold)).padding(.top, 4)
        case .rule:
            Divider().padding(.vertical, 4)
        case .bullet(let s, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? .green : .secondary)
                } else {
                    Text("•").foregroundStyle(.secondary)
                }
                inline(s)
            }
            .padding(.leading, 6)
        case .paragraph(let s):
            inline(s)
        }
    }

    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }
}
