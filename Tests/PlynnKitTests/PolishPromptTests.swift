import XCTest
@testable import PlynnKit

final class PolishPromptTests: XCTestCase {
    private let glossary = ["Jay", "Kerry", "Lyle", "Neo", "OAUTH", "SMU", "npm"]
    private let spoken = "Realm needs custom access so we can run commands without asking again."

    // MARK: sanitize — glossary echo

    /// The reported bug: the polish model appended the preferred-spellings
    /// list to the cleaned text as a bulleted block.
    func testStripsEchoedGlossaryList() {
        let leaked = """
            Realm needs custom access so we can run commands without asking again.

            - Jay
            - Kerry
            - Lyle
            - Neo
            - OAUTH
            - SMU
            - npm
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsEchoedGlossaryWithoutBullets() {
        let leaked = spoken + "\n\nJay\nKerry\nnpm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsCommaSeparatedGlossaryLine() {
        let leaked = spoken + "\n\nJay, Kerry, npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsNumberedGlossaryList() {
        let leaked = spoken + "\n\n1. Jay\n2. Kerry"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    /// Only the trailing block goes — real content above it must survive intact.
    func testKeepsBodyAboveTheEchoedList() {
        let body = "First line of the note.\nSecond line of the note."
        XCTAssertEqual(
            PolishPrompt.sanitize(body + "\n\n- Jay\n- npm", input: body, glossary: glossary),
            body)
    }

    /// A term the speaker actually dictated is legitimate output, not an echo.
    func testKeepsGlossaryTermsTheSpeakerActuallySaid() {
        let input = "the ones to ping are\nJay\nKerry"
        XCTAssertEqual(
            PolishPrompt.sanitize(input, input: input, glossary: glossary), input)
    }

    /// The echoed list usually contains at least one term the speaker DID say —
    /// `relevantTerms` picks terms near transcript words, and the dictionary
    /// pass has already spelled the spoken ones canonically. Exempting those
    /// per-line left the rest of the list standing.
    func testStripsMixedEchoWhenSomeTermsWereSpoken() {
        let said = "Ask Jay whether the release is ready."
        let leaked = said + "\n\n- Jay\n- Kerry\n- npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: said, glossary: glossary), said)
    }

    /// Same leak on one comma-separated line: a spoken term first meant the
    /// whole line failed the all-unspoken test and nothing was stripped.
    func testStripsMixedCommaSeparatedEchoLedBySpokenTerm() {
        let said = "Ask Jay whether the release is ready."
        let leaked = said + "\n\nJay, Kerry, npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: said, glossary: glossary), said)
    }

    func testKeepsTextWithNoGlossaryTail() {
        let clean = "Ship the release on Monday."
        XCTAssertEqual(
            PolishPrompt.sanitize(clean, input: clean, glossary: glossary), clean)
    }

    /// Output that is nothing but the glossary is unusable — fall back to input.
    func testAllGlossaryOutputFallsBackToInput() {
        XCTAssertEqual(
            PolishPrompt.sanitize("- Jay\n- Kerry\n- npm", input: spoken, glossary: glossary),
            spoken)
    }

    func testEmptyGlossaryLeavesOutputUntouched() {
        let text = "Jay\nKerry"
        XCTAssertEqual(PolishPrompt.sanitize(text, input: spoken, glossary: []), text)
    }

    // MARK: sanitize — appended recap list

    func testStripsAppendedTodoListRepeatedFromProse() {
        let input = """
            Whenever you're done with everything, use the D-slop skill over all of the PRs. Make sure that we have clean code written, then consolidate everything and merge it to the main code base. Release the new release and install it on my machine. Make sure everything works as intended.
            """
        let leaked = input + """


            - Use the D-slop skill over all of the PRs
            - Make sure that we have clean code written
            - Consolidate everything and merge it to the main code base
            - Release the new release and install it on my machine
            - Make sure everything works as intended
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: input, rejectAddedContent: true),
            input)
    }

    func testStripsNumberedRecapRepeatedFromProse() {
        let body = "Review the changes. Run the tests."
        let leaked = body + "\n\n1. Review the changes\n2. Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: body, rejectAddedContent: true),
            body)
    }

    func testKeepsStandaloneDictatedList() {
        let list = "- Review the changes\n- Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(
                list, input: "first review the changes second run the tests",
                rejectAddedContent: true),
            list)
    }

    func testKeepsTrailingListWithNewContent() {
        let text = "Here is the plan.\n\n- Review the changes\n- Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: text, rejectAddedContent: true),
            text)
    }

    func testSharedSanitizerKeepsIntentionalTransformList() {
        let selection = "Review the changes. Run the tests."
        let transformed = selection + "\n\n- Review the changes\n- Run the tests"
        XCTAssertEqual(PolishPrompt.sanitize(transformed, input: selection), transformed)
    }

    // MARK: sanitize — content the speaker never said

    /// The reported bug: the prose came back intact with a numbered recap
    /// under it, ending in "Ship on Monday" lifted from the prompt's example.
    func testRejectsRecapEndingInCopiedPromptExample() {
        let input = """
            Yes, I am going to bed, so work to get this brand new version of Realm set up. Ensure there's no bugs, everything looks really clean, is very usable. I am very excited for this. Have the Electron version up and running for me by the time I wake up tomorrow with all the changes, including the bug fixes that we asked for our buddy Johnny.
            """
        let leaked = input + """


            1. Ensure there's no bugs
            2. Everything looks really clean
            3. Everything is very usable
            4. Have the Electron version up and running for me by the time I wake up tomorrow with all the changes, including the bug fixes that we asked for our buddy Johnny
            5. Ship on Monday
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: input, rejectAddedContent: true), input)
    }

    func testRejectsAReplyInsteadOfTheText() {
        let input = "can you check whether the build passed on main"
        let reply = "Sure! I can't access your build system, but you could open the CI page to see it."
        XCTAssertEqual(
            PolishPrompt.sanitize(reply, input: input, rejectAddedContent: true), input)
    }

    func testKeepsOrdinaryCleanup() {
        let input = "um so I think we should uh ship this today you know"
        let cleaned = "So I think we should ship this today."
        XCTAssertEqual(
            PolishPrompt.sanitize(cleaned, input: input, rejectAddedContent: true), cleaned)
    }

    func testKeepsDictatedListAndRespelledName() {
        let input = "first email jae second run the tests third don't forget the deck"
        let cleaned = "1. Email Jay\n2. Run the tests\n3. Don't forget the deck"
        XCTAssertEqual(
            PolishPrompt.sanitize(
                cleaned, input: input, glossary: ["Jay"], rejectAddedContent: true),
            cleaned)
    }

    /// Filler removal shrinks the prose about as much as a one-line tail
    /// adds, so this one gets past the length check.
    func testStripsOneLineTailUnderShrunkProse() {
        let input = "So look, we need like an auto updater so we can just redo the build"
        let body = "We need an auto updater so we can redo the build."
        XCTAssertEqual(
            PolishPrompt.sanitize(
                body + "\n\n- ship on Monday", input: input, rejectAddedContent: true),
            body)
    }

    func testStripsNameDumpUnderProse() {
        let input = "fix the margin or padding because the list bleeds through the gaps"
        let body = "Fix the margin or padding because the list bleeds through the gaps."
        XCTAssertEqual(
            PolishPrompt.sanitize(
                body + "\n\n- margin\n- padding", input: input, rejectAddedContent: true),
            body)
    }

    func testStripsBareTrailingLineOfUnspokenWords() {
        let input = "just add like a little more spacing above it because it seems crimped there"
        let body = "Just add a little more spacing above it because it seems crimped there."
        XCTAssertEqual(
            PolishPrompt.sanitize(
                body + "  \nship on Monday", input: input, rejectAddedContent: true),
            body)
    }

    func testKeepsDictatedLastLine() {
        let input = "thanks for the help\nsee you on Monday"
        let text = "Thanks for the help.\nSee you on Monday."
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: input, rejectAddedContent: true), text)
    }

    func testKeepsListIntroducedByColon() {
        let input = "my old classes which is EE451 EE250 and CSCI 350"
        let text = "My old classes:\n\n- EE451\n- EE250\n- CSCI 350"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: input, rejectAddedContent: true), text)
    }

    /// From history: the recap ran straight on from the prose, no blank line,
    /// with Markdown hard breaks on every line.
    func testStripsRecapWithNoBlankLineAbove() {
        let input = "we should text Sam about the permission screenshot and keep it short and then draft a message for the team channel and show me before we send it"
        let body = "We should text Sam about the permission screenshot and keep it short. Then draft a message for the team channel and show me before we send it."
        let leaked = body
            + "  \n- text Sam about the permission screenshot  \n- keep it short  "
            + "\n- draft a message for the team channel and show me before we send it"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: input, rejectAddedContent: true), body)
    }

    func testStripsOrdinalLinesRestatingTheProse() {
        let input = "check the comments in the design file and then read the chat and then let's come up with a plan for all of this"
        let body = "Check the comments in the design file, then read the chat, and then let's come up with a plan for all of this."
        let leaked = body + """


            First, check the comments in the design file.
            Second, read the chat.
            Third, come up with a plan.
            Fourth, ship on Monday.
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: input, rejectAddedContent: true), body)
    }

    func testStripsSentenceAppendedOnTheSameLine() {
        let input = "can we look into ways to cut the memory use but keep them efficient"
        let body = "Can we look into ways to cut the memory use but keep them efficient?"
        XCTAssertEqual(
            PolishPrompt.sanitize(
                body + " Ship on Monday.", input: input, rejectAddedContent: true),
            body)
    }

    /// The model turned the second half of the speech into bullets. Ugly, but
    /// every word is the speaker's, so none of it may be cut.
    func testKeepsSpeechTheModelReflowedIntoBullets() {
        let input = "the register file needs three things what do they mean and is that the stage it is in"
        let text = "The register file needs three things.\n\n- What do they mean\n- Is that the stage it is in"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: input, rejectAddedContent: true), text)
    }

    func testStripsOneWordListItemRepeatingTheProse() {
        let input = "I want each team to pick a mascot for the dashboard"
        let body = "I want each team to pick a mascot for the dashboard."
        XCTAssertEqual(
            PolishPrompt.sanitize(body + "\n\n1. Mascot", input: input, rejectAddedContent: true),
            body)
    }

    func testKeepsNameOnItsOwnClosingLine() {
        let input = "thanks for the help Jay"
        let text = "Thanks for the help,\nJay"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: input, glossary: ["Jay"], rejectAddedContent: true),
            text)
    }

    func testKeepsOneRewordedClosingWord() {
        let input = "send it over when you're done okay"
        let text = "Send it over when you're done. OK."
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: input, rejectAddedContent: true), text)
    }

    /// No example sentence in the prompt for a small model to copy.
    func testPromptHasNoExampleSentenceToCopy() {
        let p = PolishPrompt.instructions(tone: .neutral, technical: false)
        XCTAssertFalse(p.lowercased().contains("monday"), "got: \(p)")
        XCTAssertFalse(p.contains("becomes"), "got: \(p)")
    }

    // MARK: existing sanitize behavior still holds

    func testStillUnquotesAndFallsBackOnRunaway() {
        XCTAssertEqual(PolishPrompt.sanitize("\"hello there\"", input: "hello there"), "hello there")
        XCTAssertEqual(PolishPrompt.sanitize("", input: "keep me"), "keep me")
        XCTAssertEqual(PolishPrompt.sanitize(nil, input: "keep me"), "keep me")
    }

    // MARK: prompt shape

    /// A trailing word list reads as a cue to emit one, so the glossary must
    /// never be the last thing the model sees.
    func testOutputOnlyRuleIsTheFinalInstruction() {
        let p = PolishPrompt.instructions(
            tone: .neutral, technical: true, preferredSpellings: glossary)
        XCTAssertTrue(
            p.hasSuffix("- Output ONLY the cleaned text, nothing else."), "got tail: \(p.suffix(80))")
        XCTAssertTrue(p.contains("Spell these names exactly as written"))
        XCTAssertTrue(p.contains("Jay, Kerry"))
    }

    /// Regression: naming the list a <glossary> taught the model to append a
    /// "**Glossary**" section and a literal "<glossary>" trailer. The word and
    /// the tag must not appear anywhere the model can copy them from.
    func testPromptNeverSaysGlossaryOrUsesATag() {
        let p = PolishPrompt.instructions(
            tone: .neutral, technical: true, preferredSpellings: glossary)
        XCTAssertFalse(p.lowercased().contains("glossary"), "got: \(p)")
        XCTAssertFalse(p.contains("<glossary"), "got: \(p)")
    }

    func testNoGlossarySectionWhenNoSpellings() {
        let p = PolishPrompt.instructions(tone: .casual, technical: false)
        XCTAssertFalse(p.contains("Spell these names"))
        XCTAssertTrue(p.hasSuffix("- Output ONLY the cleaned text, nothing else."))
    }

    // MARK: echo shapes seen in the wild after the Sep 1 fix

    /// The reported bug: a heading plus a "Term: gloss" definition line.
    func testStripsGlossaryHeadingWithDefinitionLine() {
        let body = "So now it can generate guides for me the same way I would write them myself."
        let leaked = body + "\n\n**Glossary**  \n- Jay: pdf"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: body, glossary: ["Jay"]), body)
    }

    func testStripsDefinitionLinesWithDashAndBold() {
        let leaked = spoken + "\n\nGlossary:\n- **Jay** — a name\n- Kerry - another"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    /// Nine of ten artifacts: the model closed its answer with the tag itself.
    func testStripsLiteralGlossaryTagTrailer() {
        let leaked = spoken + "\n\n<glossary>"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
        XCTAssertEqual(
            PolishPrompt.sanitize(spoken + "\n</glossary>\n", input: spoken, glossary: []), spoken)
    }

    func testStripsTagThenEchoedList() {
        let leaked = spoken + "\n\n- Jay\n- npm\n</glossary>"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsCleanedTextCueTrailer() {
        XCTAssertEqual(
            PolishPrompt.sanitize(spoken + "\n\nCleaned text:", input: spoken), spoken)
    }

    /// A heading is only consumed when an echo sits under it — a dictated
    /// "Glossary" heading over real content is the speaker's own.
    func testKeepsDictatedGlossaryHeadingOverRealContent() {
        let text = "Notes from today.\n\nGlossary:\n- latency is how long a round trip takes"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: text, glossary: glossary), text)
    }

    /// A definition of a term the speaker actually said is content.
    func testKeepsDefinitionOfSpokenTerm() {
        let text = "Two names to know.\n\n- Jay: runs infra\n- Kerry: runs design"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: text, glossary: glossary), text)
    }
}
