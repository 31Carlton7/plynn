import XCTest
@testable import PlynnKit

final class ReferenceResolverTests: XCTestCase {
    let main = PersonalStore.Term(id: 1, text: "main.swift", aliases: [])
    let contentView = PersonalStore.Term(id: 2, text: "ContentView.swift", aliases: [])

    func testTagsSpokenFilename() {
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences(
                "open main dot swift", terms: [main]),
            "open @main.swift")
    }

    func testSplitsCamelCaseFilename() {
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences(
                "edit content view dot swift", terms: [contentView]),
            "edit @ContentView.swift")
    }

    func testDoesNotDoubleTagOrMatchInsideWord() {
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences(
                "@main.swift and main.swift.bak", terms: [main]),
            "@main.swift and main.swift.bak")
    }

    func testIgnoresNonFilenameTerms() {
        let term = PersonalStore.Term(id: 3, text: "Plynn", aliases: ["plin"])
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences("plin is fast", terms: [term]),
            "plin is fast")
    }

    func testExplicitSpokenAliasIsSupported() {
        let term = PersonalStore.Term(id: 4, text: "README.md", aliases: ["read me dot markdown"])
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences(
                "update read me dot markdown", terms: [term]),
            "update @README.md")
    }

    func testTagsUniqueWorkspaceCandidateWithoutDictionaryTerm() {
        XCTAssertEqual(
            ReferenceResolver.tagFileReferences(
                "review package dot swift", terms: [], fileCandidates: ["Package.swift"]),
            "review @Package.swift")
    }

    func testFormatterTagsOnlyTechnicalApps() async {
        let mainTerm = PersonalStore.Term(id: 1, text: "main.swift", aliases: [])
        let formatter = TranscriptFormatter(personalization: {
            (snippets: [], terms: [mainTerm])
        })

        let technical = await formatter.format(
            "open main dot swift",
            context: ContextSnapshot(bundleID: "com.microsoft.VSCode"),
            aiPolish: false)
        XCTAssertEqual(technical.text, "Open @main.swift")

        let general = await formatter.format(
            "open main dot swift",
            context: ContextSnapshot(bundleID: "com.apple.MobileSMS"),
            aiPolish: false)
        XCTAssertEqual(general.text, "Open main dot swift")
    }
}
