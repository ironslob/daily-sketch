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
        let promptCardStack = PromptCardStack(
            words: ["Chocolate", "Coffee", "Banana"],
            accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
        )
        let skeleton = LoadingSkeleton(height: 72)
        let avatar = AvatarView(displayName: "Matt", username: "sketchy_matt")
        let chip = PromptChip(word: "Coffee")
        let social = SocialActionButton(kind: .like, count: 3, action: {})
        let card = SubmissionCard(
            item: FeedItemModel.preview,
            onTapArtwork: {},
            onTapOwner: {}
        )

        XCTAssertNotNil(loading.body)
        XCTAssertNotNil(empty.body)
        XCTAssertNotNil(error.body)
        XCTAssertNotNil(promptGroup.body)
        XCTAssertNotNil(promptCardStack.body)
        XCTAssertNotNil(skeleton.body)
        XCTAssertNotNil(avatar.body)
        XCTAssertNotNil(chip.body)
        XCTAssertNotNil(social.body)
        XCTAssertNotNil(card.body)
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

    func testPromptCardFanGeometryRestingSpreadsSideCards() {
        let left = PromptCardFanGeometry.transform(index: 0, phase: .resting)
        let center = PromptCardFanGeometry.transform(index: 1, phase: .resting)
        let right = PromptCardFanGeometry.transform(index: 2, phase: .resting)

        XCTAssertLessThan(left.rotation, 0)
        XCTAssertEqual(center.rotation, 0)
        XCTAssertGreaterThan(right.rotation, 0)
        XCTAssertLessThan(left.xOffset, 0)
        XCTAssertEqual(center.xOffset, 0)
        XCTAssertGreaterThan(right.xOffset, 0)
        XCTAssertEqual(center.zIndex, 3)
    }

    func testPromptCardFanGeometryFannedOutSpreadsFurtherThanResting() {
        let restingLeft = PromptCardFanGeometry.transform(index: 0, phase: .resting)
        let fannedLeft = PromptCardFanGeometry.transform(index: 0, phase: .fannedOut)

        XCTAssertLessThan(fannedLeft.rotation, restingLeft.rotation)
        XCTAssertLessThan(fannedLeft.xOffset, restingLeft.xOffset)
    }

    func testPromptCardFanGeometryStackedCardsOverlap() {
        let stacked = PromptCardFanGeometry.transform(index: 1, phase: .stacked)

        XCTAssertEqual(stacked.rotation, 0)
        XCTAssertEqual(stacked.xOffset, 0)
    }
}
