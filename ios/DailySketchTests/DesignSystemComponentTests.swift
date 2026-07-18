import SwiftUI
import XCTest
@testable import DailySketch

@MainActor
final class DesignSystemComponentTests: XCTestCase {
    func testPrimaryAndSecondaryButtonsExposeTitles() {
        let primary = PrimaryButton(title: "Start Sketch", action: {})
        let secondary = SecondaryButton(title: "Sign In", action: {})
        let tertiary = TertiaryTextButton(title: "Continue Later", action: {})

        XCTAssertEqual(String(describing: type(of: primary)), "PrimaryButton")
        XCTAssertEqual(String(describing: type(of: secondary)), "SecondaryButton")
        XCTAssertEqual(String(describing: type(of: tertiary)), "TertiaryTextButton")
    }

    func testStateViewsCanBeConstructed() {
        let loading = LoadingView(message: "Loading…")
        let empty = EmptyStateView(
            title: "No sketches yet",
            message: "Be the first to share an interpretation of today’s prompt."
        )
        let error = ErrorStateView(
            title: "Couldn’t load community sketches",
            message: "Check your connection and try again.",
            onRetry: {}
        )
        let promptGroup = PromptGroup(
            words: ["Chocolate", "Coffee", "Banana"],
            accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
        )
        let skeleton = LoadingSkeleton(height: 72)

        XCTAssertNotNil(loading.body)
        XCTAssertNotNil(empty.body)
        XCTAssertNotNil(error.body)
        XCTAssertNotNil(promptGroup.body)
        XCTAssertNotNil(skeleton.body)
    }

    func testSemanticColourTokensExist() {
        XCTAssertNotNil(AppColors.surfaceElevated)
        XCTAssertNotNil(AppColors.outline)
        XCTAssertNotNil(AppColors.dangerSoft)
        XCTAssertNotNil(AppColors.success)
        XCTAssertNotNil(AppTypography.timer)
        XCTAssertEqual(AppShadows.radius, 20)
        XCTAssertEqual(AppShadows.yOffset, 8)
    }
}
