import XCTest
@testable import PlynnKit

final class AppCategoriesTests: XCTestCase {
    func testCasualApps() {
        XCTAssertEqual(AppCategories.profile(forBundleID: "com.apple.MobileSMS").tone, .casual)
        XCTAssertEqual(AppCategories.profile(forBundleID: "net.whatsapp.WhatsApp").tone, .casual)
        XCTAssertEqual(AppCategories.profile(forBundleID: "com.hnc.Discord").tone, .casual)
        XCTAssertEqual(AppCategories.profile(forBundleID: "com.tinyspeck.slackmacgap").tone, .casual)
    }

    func testFormalApps() {
        XCTAssertEqual(AppCategories.profile(forBundleID: "com.apple.mail").tone, .formal)
        XCTAssertEqual(AppCategories.profile(forBundleID: "com.microsoft.Outlook").tone, .formal)
    }

    func testTechnicalApps() {
        let terminal = AppCategories.profile(forBundleID: "com.apple.Terminal")
        XCTAssertEqual(terminal.tone, .neutral)
        XCTAssertTrue(terminal.isTechnical)
        XCTAssertTrue(AppCategories.profile(forBundleID: "com.todesktop.230313mzl4w4u92").isTechnical) // Cursor
        XCTAssertTrue(AppCategories.profile(forBundleID: "com.microsoft.VSCode").isTechnical)
    }

    func testUnknownDefaultsNeutral() {
        let p = AppCategories.profile(forBundleID: "com.example.unknown")
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertFalse(p.isTechnical)
    }

    func testNilBundleID() {
        XCTAssertEqual(AppCategories.profile(forBundleID: nil).tone, .neutral)
    }
}
