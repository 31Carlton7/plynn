import XCTest
@testable import PlynnKit

final class MeetingSummarizerTests: XCTestCase {
    // MARK: MeetingTranscript

    func testTranscriptRendersTimestampedSegments() {
        var t = MeetingTranscript()
        t.append("Let's get started.", at: 0)
        t.append("First item is the roadmap.", at: 65)
        t.append("We agreed on Monday.", at: 3725)
        let text = t.plainText
        XCTAssertTrue(text.contains("[00:00] Let's get started."))
        XCTAssertTrue(text.contains("[01:05] First item is the roadmap."))
        XCTAssertTrue(text.contains("[1:02:05] We agreed on Monday."))
    }

    func testEmptyTranscriptIsEmpty() {
        XCTAssertTrue(MeetingTranscript().isEmpty)
        XCTAssertEqual(MeetingTranscript().plainText, "")
    }

    func testTranscriptWordCount() {
        var t = MeetingTranscript()
        t.append("one two three", at: 0)
        t.append("four five", at: 10)
        XCTAssertEqual(t.wordCount, 5)
    }

    // MARK: Chunking

    func testShortTranscriptIsOneChunk() {
        let chunks = MeetingSummarizer.chunk("Short meeting. Nothing much.", maxWords: 500)
        XCTAssertEqual(chunks, ["Short meeting. Nothing much."])
    }

    func testChunkingSplitsOnSentenceBoundaries() {
        // 3 sentences of 4 words; cap of 6 words forces a split, but only at a period.
        let text = "One two three four. Five six seven eight. Nine ten eleven twelve."
        let chunks = MeetingSummarizer.chunk(text, maxWords: 6)
        XCTAssertEqual(chunks.count, 3)
        for c in chunks {
            XCTAssertTrue(c.hasSuffix("."), "chunk must end at a sentence: \(c)")
        }
    }

    func testChunkingNeverExceedsCapUnlessSingleSentenceDoes() {
        let text = (1...40).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let chunks = MeetingSummarizer.chunk(text, maxWords: 25)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.split(separator: " ").count, 25, "over cap: \(c)")
        }
        // Nothing lost.
        let rejoined = chunks.joined(separator: " ")
        XCTAssertEqual(rejoined.split(separator: " ").count, text.split(separator: " ").count)
    }

    func testOversizedSingleSentenceStillEmitted() {
        // A single sentence longer than the cap can't be split; it must still come out whole.
        let long = Array(repeating: "word", count: 30).joined(separator: " ") + "."
        let chunks = MeetingSummarizer.chunk(long, maxWords: 10)
        XCTAssertEqual(chunks, [long])
    }

    func testEmptyChunksForEmptyText() {
        XCTAssertTrue(MeetingSummarizer.chunk("   ", maxWords: 100).isEmpty)
    }

    // MARK: Prompts

    func testChunkPromptFencesTranscript() {
        let p = MeetingSummarizer.chunkPrompt("we discussed pricing", index: 2, total: 5)
        XCTAssertTrue(p.contains("<transcript>"))
        XCTAssertTrue(p.contains("we discussed pricing"))
        XCTAssertTrue(p.contains("part 2 of 5"))
    }

    func testMergePromptCarriesEveryChunkSummary() {
        let p = MeetingSummarizer.mergePrompt(["- alpha point", "- beta point"], title: "Sync")
        XCTAssertTrue(p.contains("alpha point"))
        XCTAssertTrue(p.contains("beta point"))
        XCTAssertTrue(p.contains("# ") || p.contains("Markdown"))
    }

    func testFallbackNoteWhenNoEngine() {
        // With no summarizer available we still produce a valid note that
        // says the summary is pending — never an empty file.
        let note = MeetingSummarizer.pendingNote(title: "Standup", transcriptWords: 120)
        XCTAssertTrue(note.hasPrefix("# Standup"))
        XCTAssertTrue(note.lowercased().contains("pending") || note.lowercased().contains("unavailable"))
    }
}
