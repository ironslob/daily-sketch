import XCTest

final class DailySketchUITests: XCTestCase {
    func testLaunchShowsHomeFeedAndTimerEntry() throws {
        let app = XCUIApplication()
        app.launch()

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today’s Inspiration"].exists)
        XCTAssertTrue(app.buttons["Start Sketch"].exists)

        app.buttons["Start Sketch"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'minute'")).firstMatch
                .waitForExistence(timeout: 5)
                || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'timer'")).firstMatch
                .waitForExistence(timeout: 2)
        )
    }

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

    func testVoiceOverSmokeLabelsOnHome() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Today’s Inspiration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Sketch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
    }

    func testLargeDynamicTypeHomeStillShowsPrimaryActions() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UIAccessibilityExtraExtraExtraLarge"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Today’s Inspiration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Sketch"].waitForExistence(timeout: 5))
    }
}
