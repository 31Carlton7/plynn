import Foundation
import SQLite3

/// All personalization data — dictionary terms, snippets, dictation history —
/// in one local SQLite file. Raw sqlite3; no dependencies.
public final class PersonalStore: @unchecked Sendable {
    public struct Term: Identifiable, Equatable, Sendable {
        public let id: Int64
        public let text: String
        public let aliases: [String]
    }

    public struct Snippet: Identifiable, Equatable, Sendable {
        public let id: Int64
        public let trigger: String
        public let expansion: String
    }

    public struct HistoryEntry: Identifiable, Equatable, Sendable {
        public let id: Int64
        public let timestamp: Date
        public let app: String
        public let verbatim: String
        public let formatted: String
        public let durationSeconds: Double
        public let engine: String
    }

    public struct Stats: Equatable, Sendable {
        public let sessions: Int
        public let words: Int
        public let seconds: Double
    }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "co.charmtechnologies.plynn.store")

    public static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plynn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("personal.db").path
    }

    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS terms(
                id INTEGER PRIMARY KEY, text TEXT NOT NULL UNIQUE,
                aliases TEXT NOT NULL DEFAULT '', created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS snippets(
                id INTEGER PRIMARY KEY, trigger TEXT NOT NULL,
                expansion TEXT NOT NULL, created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS history(
                id INTEGER PRIMARY KEY, ts REAL NOT NULL, app TEXT NOT NULL,
                verbatim TEXT NOT NULL, formatted TEXT NOT NULL,
                duration_s REAL NOT NULL, engine TEXT NOT NULL);
            """)
    }

    deinit { sqlite3_close(db) }

    public enum StoreError: Error {
        case open(String), step(String), prepare(String)
    }

    // MARK: Terms

    @discardableResult
    public func addTerm(text: String, aliases: [String]) throws -> Int64 {
        try queue.sync {
            try run(
                "INSERT INTO terms(text, aliases, created) VALUES(?,?,?)",
                bind: [.text(text), .text(aliases.joined(separator: "\u{1F}")), .real(now())])
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func terms() throws -> [Term] {
        try queue.sync {
            try query("SELECT id, text, aliases FROM terms ORDER BY text") { s in
                Term(
                    id: sqlite3_column_int64(s, 0),
                    text: column(s, 1),
                    aliases: column(s, 2).isEmpty ? [] : column(s, 2).components(separatedBy: "\u{1F}"))
            }
        }
    }

    public func deleteTerm(id: Int64) throws {
        try queue.sync { try run("DELETE FROM terms WHERE id = ?", bind: [.int(id)]) }
    }

    /// Lines of `term` or `term,alias1,alias2`. Skips blanks and terms that
    /// already exist. Returns the number imported.
    @discardableResult
    public func importTermsCSV(_ csv: String) throws -> Int {
        let existing = Set(try terms().map { $0.text.lowercased() })
        var added = 0
        for line in csv.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let text = parts.first, !existing.contains(text.lowercased()) else { continue }
            try addTerm(text: text, aliases: Array(parts.dropFirst()))
            added += 1
        }
        return added
    }

    // MARK: Snippets

    @discardableResult
    public func addSnippet(trigger: String, expansion: String) throws -> Int64 {
        try queue.sync {
            try run(
                "INSERT INTO snippets(trigger, expansion, created) VALUES(?,?,?)",
                bind: [.text(trigger), .text(expansion), .real(now())])
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func snippets() throws -> [Snippet] {
        try queue.sync {
            try query("SELECT id, trigger, expansion FROM snippets ORDER BY trigger") { s in
                Snippet(id: sqlite3_column_int64(s, 0), trigger: column(s, 1), expansion: column(s, 2))
            }
        }
    }

    public func deleteSnippet(id: Int64) throws {
        try queue.sync { try run("DELETE FROM snippets WHERE id = ?", bind: [.int(id)]) }
    }

    // MARK: History

    public func record(
        app: String, verbatim: String, formatted: String,
        durationSeconds: Double, engine: String
    ) throws {
        try queue.sync {
            try run(
                "INSERT INTO history(ts, app, verbatim, formatted, duration_s, engine) VALUES(?,?,?,?,?,?)",
                bind: [
                    .real(now()), .text(app), .text(verbatim), .text(formatted),
                    .real(durationSeconds), .text(engine),
                ])
        }
    }

    public func history(limit: Int, matching: String? = nil) throws -> [HistoryEntry] {
        try queue.sync {
            let filter = matching.map { _ in "WHERE formatted LIKE ? OR verbatim LIKE ?" } ?? ""
            var binds: [Value] = []
            if let matching { binds = [.text("%\(matching)%"), .text("%\(matching)%")] }
            binds.append(.int(Int64(limit)))
            return try query(
                "SELECT id, ts, app, verbatim, formatted, duration_s, engine FROM history \(filter) ORDER BY ts DESC LIMIT ?",
                bind: binds
            ) { s in
                HistoryEntry(
                    id: sqlite3_column_int64(s, 0),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                    app: column(s, 2), verbatim: column(s, 3), formatted: column(s, 4),
                    durationSeconds: sqlite3_column_double(s, 5), engine: column(s, 6))
            }
        }
    }

    public func stats() throws -> Stats {
        try queue.sync {
            var sessions = 0, words = 0
            var seconds = 0.0
            for entry in try query(
                "SELECT formatted, duration_s FROM history",
                transform: { s in (column(s, 0), sqlite3_column_double(s, 1)) })
            {
                sessions += 1
                words += entry.0.split(whereSeparator: \.isWhitespace).count
                seconds += entry.1
            }
            return Stats(sessions: sessions, words: words, seconds: seconds)
        }
    }

    public func clearHistory() throws {
        try queue.sync { try run("DELETE FROM history") }
    }

    // MARK: SQLite plumbing

    private enum Value {
        case text(String), int(Int64), real(Double)
    }

    private func now() -> Double { Date().timeIntervalSince1970 }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func prepare(_ sql: String, bind: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in bind.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .text(let t): sqlite3_bind_text(stmt, idx, t, -1, transient)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            }
        }
        return stmt
    }

    private func run(_ sql: String, bind: [Value] = []) throws {
        let stmt = try prepare(sql, bind: bind)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(
        _ sql: String, bind: [Value] = [], transform: (OpaquePointer) -> T
    ) throws -> [T] {
        let stmt = try prepare(sql, bind: bind)
        defer { sqlite3_finalize(stmt) }
        var rows: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(transform(stmt))
        }
        return rows
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}
