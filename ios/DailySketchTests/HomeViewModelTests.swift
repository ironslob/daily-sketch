import XCTest
@testable import DailySketch

@MainActor
final class HomeViewModelTests: XCTestCase {
    private func samplePrompt(
        words: (String, String, String) = ("Chocolate", "Coffee", "Banana")
    ) -> DailyPromptModel {
        DailyPromptModel(
            id: UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ef1234567890")!,
            promptDate: Date(timeIntervalSince1970: 1_784_332_800),
            word1: words.0,
            word2: words.1,
            word3: words.2,
            status: "published",
            publishedAt: Date(timeIntervalSince1970: 1_784_246_400)
        )
    }

    func testLoadRendersThreeWordsInOrder() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()

        guard case .loaded(let prompt) = model.promptState else {
            return XCTFail("Expected loaded prompt")
        }
        XCTAssertEqual(prompt.words, ["Chocolate", "Coffee", "Banana"])
        XCTAssertTrue(model.canStartSketch)
        XCTAssertEqual(model.feedState, .empty)
    }

    func testFeedFailureDoesNotBlockPromptOrStartSketch() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        fetcher.feedError = PromptAPIError.underlying("network down")
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()

        XCTAssertEqual(fetcher.todaysPromptCallCount, 1)
        XCTAssertEqual(fetcher.recentFeedCallCount, 1)
        guard case .loaded = model.promptState else {
            return XCTFail("Prompt should remain usable when feed fails")
        }
        XCTAssertTrue(model.canStartSketch)
        guard case .failed = model.feedState else {
            return XCTFail("Expected feed failure state")
        }
    }

    func testPromptFailureDoesNotBlockFeed() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.promptError = PromptAPIError.underlying("timeout")
        fetcher.feed = RecentFeedPage(items: [], nextCursor: nil)
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()

        guard case .failed = model.promptState else {
            return XCTFail("Expected prompt failure")
        }
        XCTAssertFalse(model.canStartSketch)
        XCTAssertEqual(model.feedState, .empty)
    }

    func testMissingPromptIsRecoverableWithoutInventingLocalPrompt() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.promptError = PromptAPIError.promptNotFound
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()

        XCTAssertEqual(model.promptState, .missing)
        XCTAssertNil(model.cachedPrompt)
        XCTAssertNil(model.promptWords)
        XCTAssertFalse(model.canStartSketch)
        XCTAssertEqual(model.feedState, .empty)
    }

    func testEmptyFeedState() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        fetcher.feed = RecentFeedPage(items: [], nextCursor: nil)
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()

        XCTAssertEqual(model.feedState, .empty)
    }

    func testStartSketchPlaceholderIntent() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()
        model.startSketch()

        XCTAssertTrue(model.showsStartSketchPlaceholder)
        model.dismissStartSketchPlaceholder()
        XCTAssertFalse(model.showsStartSketchPlaceholder)
    }

    func testCachedPromptSurvivesTransientRefreshFailure() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = HomeViewModel(promptFetcher: fetcher, feedFetcher: fetcher)

        await model.load()
        fetcher.promptError = PromptAPIError.underlying("temporary")
        await model.retryPrompt()

        guard case .loaded(let prompt) = model.promptState else {
            return XCTFail("Cached prompt should remain visible")
        }
        XCTAssertEqual(prompt.word1, "Chocolate")
        XCTAssertNotNil(model.cachedPrompt)
    }
}
