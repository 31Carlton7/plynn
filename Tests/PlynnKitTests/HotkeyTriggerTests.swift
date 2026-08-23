import XCTest
@testable import PlynnKit

final class HotkeyTriggerTests: XCTestCase {
    func testEachTriggerHasADistinctKeycode() {
        let codes = Set(HotkeyTrigger.allCases.map(\.keycode))
        XCTAssertEqual(codes.count, HotkeyTrigger.allCases.count, "keycodes must not collide")
    }

    func testMatchesOnlyItsOwnKeycode() {
        for trigger in HotkeyTrigger.allCases {
            XCTAssertTrue(trigger.matches(keycode: trigger.keycode))
            for other in HotkeyTrigger.allCases where other != trigger {
                XCTAssertFalse(trigger.matches(keycode: other.keycode))
            }
        }
    }

    func testRawValueRoundTrips() {
        for trigger in HotkeyTrigger.allCases {
            XCTAssertEqual(HotkeyTrigger(rawValue: trigger.rawValue), trigger)
        }
    }

    func testDefaultIsFn() {
        XCTAssertEqual(HotkeyTrigger.fn.keycode, 63)
    }

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let names = Set(HotkeyTrigger.allCases.map(\.displayName))
        XCTAssertEqual(names.count, HotkeyTrigger.allCases.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }
}
