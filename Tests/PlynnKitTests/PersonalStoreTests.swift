import XCTest
@testable import PlynnKit

final class PersonalStoreTests: XCTestCase {
    var store: PersonalStore!
    var dbPath: String!

    override func setUpWithError() throws {
        dbPath = NSTemporaryDirectory() + "plynn-test-\(UUID().uuidString).db"
        store = try PersonalStore(path: dbPath)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: Terms

    func testAddListDeleteTerm() throws {
        let id = try store.addTerm(text: "Plynn", aliases: ["plin", "plyn"])
        let terms = try store.terms()
        XCTAssertEqual(terms.count, 1)
        XCTAssertEqual(terms[0].text, "Plynn")
        XCTAssertEqual(terms[0].aliases, ["plin", "plyn"])
        try store.deleteTerm(id: id)
        XCTAssertTrue(try store.terms().isEmpty)
    }

    func testTermWithoutAliases() throws {
        _ = try store.addTerm(text: "Charm", aliases: [])
        XCTAssertEqual(try store.terms()[0].aliases, [])
    }

    func testCSVImport() throws {
        let csv = """
        Plynn,plin,plyn
        Charm Technologies
        Aikins,akins,aikens
        """
        let count = try store.importTermsCSV(csv)
        XCTAssertEqual(count, 3)
        let terms = try store.terms()
        XCTAssertEqual(terms.count, 3)
        XCTAssertEqual(terms.first { $0.text == "Aikins" }?.aliases, ["akins", "aikens"])
    }

    func testCSVImportDedupes() throws {
        _ = try store.addTerm(text: "Plynn", aliases: ["plin"])
        let count = try store.importTermsCSV("Plynn,plyn\nNew Term")
        XCTAssertEqual(count, 1)  // only New Term added
        XCTAssertEqual(try store.terms().count, 2)
    }

    func testAddAliasIdempotent() throws {
        let id = try store.addTerm(text: "Plynn", aliases: ["plin"])
        try store.addAlias(termID: id, alias: "plyn")
        try store.addAlias(termID: id, alias: "PLYN")  // dupe, case-insensitive
        XCTAssertEqual(try store.terms()[0].aliases, ["plin", "plyn"])
    }

    // MARK: Snippets

    func testAddListDeleteSnippet() throws {
        let id = try store.addSnippet(trigger: "my email", expansion: "carlton@charmtechnologies.co")
        let snippets = try store.snippets()
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets[0].trigger, "my email")
        XCTAssertEqual(snippets[0].expansion, "carlton@charmtechnologies.co")
        try store.deleteSnippet(id: id)
        XCTAssertTrue(try store.snippets().isEmpty)
    }

    // MARK: History

    func testRecordAndStats() throws {
        try store.record(
            app: "com.tinyspeck.slackmacgap", verbatim: "um hello there",
            formatted: "Hello there", durationSeconds: 3.5, engine: "Parakeet (local)")
        try store.record(
            app: "com.apple.mail", verbatim: "dear team",
            formatted: "Dear team,", durationSeconds: 2.0, engine: "Parakeet (local)")
        let history = try store.history(limit: 10)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].formatted, "Dear team,")  // newest first
        let stats = try store.stats()
        XCTAssertEqual(stats.sessions, 2)
        XCTAssertEqual(stats.words, 4)  // "Hello there" + "Dear team," = 2 + 2
        XCTAssertEqual(stats.seconds, 5.5, accuracy: 0.01)
    }

    func testHistorySearchAndClear() throws {
        try store.record(app: "a", verbatim: "x", formatted: "the quick fox", durationSeconds: 1, engine: "e")
        try store.record(app: "a", verbatim: "y", formatted: "lazy dog", durationSeconds: 1, engine: "e")
        XCTAssertEqual(try store.history(limit: 10, matching: "fox").count, 1)
        try store.clearHistory()
        XCTAssertTrue(try store.history(limit: 10).isEmpty)
        XCTAssertEqual(try store.stats().sessions, 0)
    }

    // MARK: Meetings

    func testMeetingLifecycle() throws {
        let id = try store.addMeeting(title: "Design sync", startedAt: Date(timeIntervalSince1970: 1_000))
        var m = try XCTUnwrap(try store.meeting(id: id))
        XCTAssertEqual(m.title, "Design sync")
        XCTAssertEqual(m.status, .recording)
        XCTAssertEqual(m.transcript, "")
        XCTAssertNil(m.notes)

        try store.updateMeeting(
            id: id, transcript: "[00:00] hi", durationSeconds: 90, status: .summarizing)
        m = try XCTUnwrap(try store.meeting(id: id))
        XCTAssertEqual(m.transcript, "[00:00] hi")
        XCTAssertEqual(m.durationSeconds, 90, accuracy: 0.01)
        XCTAssertEqual(m.status, .summarizing)

        try store.updateMeeting(id: id, notes: "# Design sync\n\n## TL;DR\nGood.", status: .ready)
        m = try XCTUnwrap(try store.meeting(id: id))
        XCTAssertEqual(m.notes, "# Design sync\n\n## TL;DR\nGood.")
        XCTAssertEqual(m.status, .ready)

        try store.deleteMeeting(id: id)
        XCTAssertNil(try store.meeting(id: id))
    }

    func testMeetingsListNewestFirst() throws {
        _ = try store.addMeeting(title: "Old", startedAt: Date(timeIntervalSince1970: 100))
        _ = try store.addMeeting(title: "New", startedAt: Date(timeIntervalSince1970: 200))
        let list = try store.meetings()
        XCTAssertEqual(list.map(\.title), ["New", "Old"])
    }

    func testMeetingMarkdownFileWritten() throws {
        let dir = NSTemporaryDirectory() + "plynn-notes-\(UUID().uuidString)"
        let url = try store.writeMarkdownFile(
            title: "Weekly / Sync: Q3?", startedAt: Date(timeIntervalSince1970: 0),
            notes: "# Weekly\n\nhello", transcript: "[00:00] hello", directory: dir)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# Weekly"))
        XCTAssertTrue(content.contains("## Transcript"))
        XCTAssertTrue(content.contains("[00:00] hello"))
        // Filename is filesystem-safe: no slashes/colons/question marks.
        let name = url.lastPathComponent
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("?"))
        XCTAssertTrue(name.hasSuffix(".md"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testPersistsAcrossReopen() throws {
        _ = try store.addTerm(text: "Plynn", aliases: ["plin"])
        store = nil
        store = try PersonalStore(path: dbPath)
        XCTAssertEqual(try store.terms().count, 1)
    }
}
