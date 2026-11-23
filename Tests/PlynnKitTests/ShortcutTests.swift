import XCTest
@testable import PlynnKit

final class ShortcutTests: XCTestCase {
    func testRawValueRoundTrips() {
        let shortcuts = [Shortcut.fn, Shortcut(keyCode: 49, modifiers: .option),
                         Shortcut(keyCode: 46, modifiers: [.control, .shift])]
        for shortcut in shortcuts {
            XCTAssertEqual(Shortcut(rawValue: shortcut.rawValue), shortcut)
        }
        XCTAssertNil(Shortcut(rawValue: "fn"))
    }

    func testModifierOnlyDropsModifierFlags() {
        // Pressing Right Command reports .command on itself; it's still a lone key.
        XCTAssertEqual(Shortcut(keyCode: 54, modifiers: .command), Shortcut(keyCode: 54))
        XCTAssertTrue(Shortcut(keyCode: 54).isModifierOnly)
        XCTAssertFalse(Shortcut(keyCode: 49, modifiers: .option).isModifierOnly)
    }

    func testFnIsNotAComboModifier() {
        // Arrow and function keys report fn on their own.
        XCTAssertEqual(Shortcut(keyCode: 122, modifiers: .function), Shortcut(keyCode: 122))
    }

    func testDisplayNames() {
        XCTAssertEqual(Shortcut.fn.displayName, "fn (Globe)")
        XCTAssertEqual(Shortcut(keyCode: 54).displayName, "Right Command")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: .option).displayName, "⌥Space")
        XCTAssertEqual(
            Shortcut(keyCode: 122, modifiers: [.command, .shift, .option, .control]).displayName,
            "⌃⌥⇧⌘F1")
    }

    func testDictationAcceptsLoneModifiersAndCombos() {
        XCTAssertNil(Shortcut.fn.problem(for: .dictate))
        XCTAssertNil(Shortcut(keyCode: 61).problem(for: .dictate))
        XCTAssertNil(Shortcut(keyCode: 49, modifiers: .option).problem(for: .dictate))
        XCTAssertNil(Shortcut(keyCode: 105).problem(for: .dictate), "bare F13 types nothing")
    }

    func testRejectsShortcutsThatWouldTypeOrClash() {
        XCTAssertNotNil(Shortcut(keyCode: 55).problem(for: .dictate), "left Command")
        XCTAssertNotNil(Shortcut(keyCode: 0).problem(for: .dictate), "bare A")
        XCTAssertNotNil(Shortcut(keyCode: 0, modifiers: .shift).problem(for: .dictate), "⇧A")
        XCTAssertNotNil(Shortcut(keyCode: 53, modifiers: .option).problem(for: .dictate), "⌥Esc")
    }

    func testDictationDefaultsToFn() {
        let defaults = scratchDefaults()
        XCTAssertEqual(HotkeyAction.dictate.shortcut(in: defaults), .fn)
    }

    func testDictationKeepsTheOldActivationKey() {
        let defaults = scratchDefaults()
        defaults.set("rightCommand", forKey: "hotkeyTrigger")
        XCTAssertEqual(HotkeyAction.dictate.shortcut(in: defaults), Shortcut(keyCode: 54))
    }

    func testRecordedShortcutWinsAndResetRestoresFn() {
        let defaults = scratchDefaults()
        defaults.set("rightOption", forKey: "hotkeyTrigger")
        let optionSpace = Shortcut(keyCode: 49, modifiers: .option)
        defaults.set(optionSpace.rawValue, forKey: HotkeyAction.dictate.defaultsKey)
        XCTAssertEqual(HotkeyAction.dictate.shortcut(in: defaults), optionSpace)
        HotkeyAction.dictate.resetShortcut(in: defaults)
        XCTAssertEqual(HotkeyAction.dictate.shortcut(in: defaults), .fn)
    }

    private func scratchDefaults() -> UserDefaults {
        let suite = "ShortcutTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
