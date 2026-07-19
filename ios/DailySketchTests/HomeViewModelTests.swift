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

    private func makeSketchFlow() -> SketchFlowViewModel {
        let auth = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: RecordingMeFetcher(
                profile: CurrentUserProfile(
                    id: UUID(),
                    username: nil,
                    displayName: "Guest",
                    profileCompleted: false,
                    status: "incomplete"
                )
            )
        )
        return SketchFlowViewModel(
            auth: auth,
            preferencesService: RecordingMeFetcher(
                profile: CurrentUserProfile(
                    id: UUID(),
                    username: nil,
                    displayName: "Guest",
                    profileCompleted: false,
                    status: "incomplete"
                )
            ),
            guestTimerStore: InMemoryGuestTimerPreferenceStore(),
            activeSessionStore: InMemoryActiveSessionStore(),
            sessionService: RecordingSketchSessionRepository(),
            draftStore: InMemoryDraftStore(),
            imageStore: InMemoryDraftImageStore(),
            cameraAuthorizer: FakeCameraAuthorizer()
        )
    }

    private func makeModel(
        fetcher: RecordingPromptFetcher,
        publishedStore: any PublishedSubmissionStoring = InMemoryPublishedSubmissionStore()
    ) -> HomeViewModel {
        HomeViewModel(
            promptFetcher: fetcher,
            feedFetcher: fetcher,
            publishedStore: publishedStore,
            sketchFlow: makeSketchFlow()
        )
    }

    func testLoadRendersThreeWordsInOrder() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = makeModel(fetcher: fetcher)

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
        let model = makeModel(fetcher: fetcher)

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
        let model = makeModel(fetcher: fetcher)

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
        let model = makeModel(fetcher: fetcher)

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
        let model = makeModel(fetcher: fetcher)

        await model.load()

        XCTAssertEqual(model.feedState, .empty)
    }

    func testStartSketchOpensTimerSelectionByDefault() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = makeModel(fetcher: fetcher)

        await model.load()
        model.startSketch()
        // startSketch kicks an async Task — wait briefly for sheet flag.
        let deadline = Date().addingTimeInterval(1)
        while !model.sketchFlow.showsTimerSelection, Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(model.sketchFlow.showsTimerSelection)
        XCTAssertFalse(model.sketchFlow.showsActiveSession)
    }

    func testCachedPromptSurvivesTransientRefreshFailure() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let model = makeModel(fetcher: fetcher)

        await model.load()
        fetcher.promptError = PromptAPIError.underlying("temporary")
        await model.retryPrompt()

        guard case .loaded(let prompt) = model.promptState else {
            return XCTFail("Cached prompt should remain visible")
        }
        XCTAssertEqual(prompt.word1, "Chocolate")
        XCTAssertNotNil(model.cachedPrompt)
    }

    func testHomeCompletionStateAfterLocalPublication() async throws {
        let fetcher = RecordingPromptFetcher()
        let prompt = samplePrompt()
        fetcher.prompt = prompt
        let publishedStore = InMemoryPublishedSubmissionStore()
        try publishedStore.save(
            PublishedLocalSubmission(
                id: UUID(),
                promptId: prompt.id,
                promptDate: prompt.promptDate,
                timerMode: "countdown",
                selectedTimerSeconds: 300,
                caption: "done",
                publishedAt: Date()
            )
        )
        let model = makeModel(fetcher: fetcher, publishedStore: publishedStore)

        await model.load()

        XCTAssertTrue(model.hasSketchedToday)
        XCTAssertEqual(model.primarySketchButtonTitle, "Create Another Sketch")
        XCTAssertEqual(model.viewMySketchTitle, "View My Sketch")
        XCTAssertEqual(model.todaysPublished.count, 1)
        XCTAssertTrue(model.canStartSketch)
    }

    func testHomeCompletionPluralizesViewTitle() async throws {
        let fetcher = RecordingPromptFetcher()
        let prompt = samplePrompt()
        fetcher.prompt = prompt
        let publishedStore = InMemoryPublishedSubmissionStore()
        for _ in 0..<2 {
            try publishedStore.save(
                PublishedLocalSubmission(
                    id: UUID(),
                    promptId: prompt.id,
                    promptDate: prompt.promptDate,
                    timerMode: "no_timer",
                    selectedTimerSeconds: nil,
                    caption: nil,
                    publishedAt: Date()
                )
            )
        }
        let model = makeModel(fetcher: fetcher, publishedStore: publishedStore)
        await model.load()
        XCTAssertEqual(model.viewMySketchTitle, "View My Sketches")
    }

    func testLoadedFeedStateMapsItems() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let item = FeedItemModel.preview
        fetcher.feed = RecentFeedPage(items: [item], nextCursor: "cursor-1")
        let model = makeModel(fetcher: fetcher)

        await model.load()

        guard case .loaded(let items) = model.feedState else {
            return XCTFail("Expected loaded feed")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, item.id)
        XCTAssertEqual(model.nextFeedCursor, "cursor-1")
        XCTAssertEqual(fetcher.lastFeedLimit, 20)
        XCTAssertNil(fetcher.lastFeedCursor)
    }

    func testInfiniteScrollAppendsNextPage() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let first = FeedItemModel.preview
        let second = FeedItemModel(
            id: UUID(),
            imageURL: first.imageURL,
            thumbnailURL: first.thumbnailURL,
            userId: first.userId,
            username: "second",
            displayName: "Second",
            avatarURL: nil,
            promptWords: first.promptWords,
            promptDate: first.promptDate,
            timerMode: first.timerMode,
            timerSeconds: first.timerSeconds,
            captionPreview: "Next page",
            likeCount: 1,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: false,
            publishedAt: first.publishedAt.addingTimeInterval(-3_600)
        )
        fetcher.feedPages[nil] = RecentFeedPage(items: [first], nextCursor: "page-2")
        fetcher.feedPages["page-2"] = RecentFeedPage(items: [second], nextCursor: nil)
        let model = makeModel(fetcher: fetcher)

        await model.load()
        await model.loadMoreFeedIfNeeded(currentItem: first)

        guard case .loaded(let items) = model.feedState else {
            return XCTFail("Expected loaded feed after pagination")
        }
        XCTAssertEqual(items.map(\.id), [first.id, second.id])
        XCTAssertNil(model.nextFeedCursor)
        XCTAssertEqual(fetcher.recentFeedCallCount, 2)
        XCTAssertEqual(fetcher.lastFeedCursor, "page-2")
    }

    func testRefreshReplacesFeedItems() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let first = FeedItemModel.preview
        fetcher.feed = RecentFeedPage(items: [first], nextCursor: nil)
        let model = makeModel(fetcher: fetcher)
        await model.load()

        let refreshed = FeedItemModel(
            id: UUID(),
            imageURL: first.imageURL,
            thumbnailURL: first.thumbnailURL,
            userId: first.userId,
            username: "refreshed",
            displayName: "Refreshed",
            avatarURL: nil,
            promptWords: first.promptWords,
            promptDate: first.promptDate,
            timerMode: first.timerMode,
            timerSeconds: first.timerSeconds,
            captionPreview: nil,
            likeCount: 0,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: false,
            publishedAt: Date()
        )
        fetcher.feed = RecentFeedPage(items: [refreshed], nextCursor: nil)
        await model.refresh()

        guard case .loaded(let items) = model.feedState else {
            return XCTFail("Expected loaded feed after refresh")
        }
        XCTAssertEqual(items.map(\.id), [refreshed.id])
    }

    func testRemoveFeedItemFallsBackToEmpty() async {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let item = FeedItemModel.preview
        fetcher.feed = RecentFeedPage(items: [item], nextCursor: nil)
        let model = makeModel(fetcher: fetcher)
        await model.load()

        model.removeFeedItem(id: item.id)

        XCTAssertEqual(model.feedState, .empty)
        XCTAssertTrue(model.feedItems.isEmpty)
    }

    func testRelativeTimestampFormatter() {
        let now = Date()
        XCTAssertEqual(
            RelativeTimestampFormatter.string(from: now.addingTimeInterval(-30), now: now),
            "just now"
        )
        XCTAssertEqual(
            RelativeTimestampFormatter.string(from: now.addingTimeInterval(-120), now: now),
            "2m ago"
        )
        XCTAssertEqual(
            RelativeTimestampFormatter.string(from: now.addingTimeInterval(-7_200), now: now),
            "2h ago"
        )
    }
}
