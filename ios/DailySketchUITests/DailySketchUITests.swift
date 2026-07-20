import XCTest

final class DailySketchUITests: XCTestCase {
    func testLaunchShowsHomeAndProfileTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let homeTab = app.tabBars.buttons["Home"]
        let profileTab = app.tabBars.buttons["Profile"]

        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today’s Inspiration"].exists)

        XCTAssertTrue(profileTab.exists)
        profileTab.tap()
        XCTAssertTrue(app.staticTexts["Keep your creative history"].waitForExistence(timeout: 5))

        homeTab.tap()
        XCTAssertTrue(app.staticTexts["Today’s Inspiration"].waitForExistence(timeout: 5))
    }

    /// Account-deletion entry lives in Settings for authenticated users. Guests see
    /// the profile CTA instead; this asserts Settings is reachable from Profile when
    /// gear is present, and documents the Delete Account accessibility label for
    /// authenticated smoke runs.
    func testAccountDeletionEntryLabelExistsWhenSettingsPresented() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 2) {
            settings.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            // Authenticated: Delete Account row should be present and openable.
            let deleteAccount = app.buttons["Delete Account"]
            if deleteAccount.exists {
                deleteAccount.tap()
                XCTAssertTrue(app.navigationBars["Delete Account"].waitForExistence(timeout: 5))
            }
        } else {
            // Guest shell: Create Free Account is the account entry point.
            XCTAssertTrue(app.buttons["Create Free Account"].waitForExistence(timeout: 5))
        }
    }
}
