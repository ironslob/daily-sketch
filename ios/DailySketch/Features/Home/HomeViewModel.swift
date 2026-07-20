import Foundation
import Observation

enum HomePromptState: Equatable {
    case loading
    case loaded(DailyPromptModel)
    case missing
    case failed(String)
}

enum HomeFeedState: Equatable {
    case loading
    case empty
    case loaded([FeedItemModel])
    case failed(String)
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var promptState: HomePromptState = .loading
    private(set) var feedState: HomeFeedState = .loading
    private(set) var cachedPrompt: DailyPromptModel?
    private(set) var feedItems: [FeedItemModel] = []
    private(set) var nextFeedCursor: String?
    private(set) var isLoadingMoreFeed = false
    private(set) var todaysPublished: [PublishedLocalSubmission] = []
    private(set) var likeErrorMessage: String?
    private(set) var pendingLikeSubmissionId: UUID?
    private(set) var isOffline = false
    private(set) var isRefreshingPrompt = false
    var showsAuthSheet = false
    var authSheetMode: AuthenticationView.Mode = .signUp

    private let promptFetcher: any PromptFetching
    private let feedFetcher: any FeedFetching
    private let socialService: any SocialServing
    private let publishedStore: any PublishedSubmissionStoring
    private let homeCacheStore: any HomeCacheStoring
    private let networkMonitor: any NetworkMonitoring
    private let analytics: any AnalyticsTracking
    private let isAuthenticated: () -> Bool
    private let accessTokenProvider: () -> String?
    let sketchFlow: SketchFlowViewModel
    private let feedPageSize = 20
    private var likeInFlightIDs: Set<UUID> = []

    init(
        promptFetcher: any PromptFetching,
        feedFetcher: any FeedFetching,
        socialService: any SocialServing,
        publishedStore: any PublishedSubmissionStoring,
        homeCacheStore: any HomeCacheStoring,
        networkMonitor: any NetworkMonitoring,
        analytics: any AnalyticsTracking,
        sketchFlow: SketchFlowViewModel,
        isAuthenticated: @escaping () -> Bool = { false },
        accessTokenProvider: @escaping () -> String? = { nil }
    ) {
        self.promptFetcher = promptFetcher
        self.feedFetcher = feedFetcher
        self.socialService = socialService
        self.publishedStore = publishedStore
        self.homeCacheStore = homeCacheStore
        self.networkMonitor = networkMonitor
        self.analytics = analytics
        self.sketchFlow = sketchFlow
        self.isAuthenticated = isAuthenticated
        self.accessTokenProvider = accessTokenProvider
        restoreCachedHomeSnapshot()
    }

    var canStartSketch: Bool {
        loadedPrompt != nil
    }

    var hasSketchedToday: Bool {
        !todaysPublished.isEmpty
    }

    var loadedPrompt: DailyPromptModel? {
        if case .loaded(let prompt) = promptState {
            return prompt
        }
        return cachedPrompt
    }

    var promptWords: [String]? {
        loadedPrompt?.words
    }

    var promptAccessibilityLabel: String {
        loadedPrompt?.accessibilityLabel ?? "Today’s prompt is loading."
    }

    var primarySketchButtonTitle: String {
        hasSketchedToday ? "Create Another Sketch" : "Start Sketch"
    }

    var viewMySketchTitle: String {
        todaysPublished.count > 1 ? "View My Sketches" : "View My Sketch"
    }

    var canLoadMoreFeed: Bool {
        nextFeedCursor != nil && !isLoadingMoreFeed && networkMonitor.isOnline
    }

    var offlineIndicatorMessage: String? {
        guard isOffline else { return nil }
        if loadedPrompt != nil {
            return "You’re offline. Showing cached inspiration."
        }
        return "You’re offline. Some actions need a connection."
    }

    func load() async {
        syncOfflineState()
        sketchFlow.prepareOnAppear()
        refreshPublishedToday()
        async let promptLoad: Void = loadPrompt()
        async let feedLoad: Void = loadFeed(reset: true)
        _ = await (promptLoad, feedLoad)
        analytics.track(.feedViewed)
    }

    func refresh() async {
        syncOfflineState()
        refreshPublishedToday()
        async let promptLoad: Void = loadPrompt()
        async let feedLoad: Void = loadFeed(reset: true)
        _ = await (promptLoad, feedLoad)
    }

    func refreshPublishedToday() {
        guard let prompt = loadedPrompt ?? cachedPrompt else {
            todaysPublished = []
            return
        }
        todaysPublished = (try? publishedStore.forPromptDate(prompt.promptDate)) ?? []
    }

    func retryPrompt() async {
        await loadPrompt()
    }

    func retryFeed() async {
        await loadFeed(reset: true)
    }

    func loadMoreFeedIfNeeded(currentItem item: FeedItemModel) async {
        guard canLoadMoreFeed else { return }
        guard let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let thresholdIndex = max(feedItems.count - 4, 0)
        guard index >= thresholdIndex else { return }
        await loadFeed(reset: false)
    }

    func removeFeedItem(id: UUID) {
        feedItems.removeAll { $0.id == id }
        if feedItems.isEmpty {
            feedState = .empty
            nextFeedCursor = nil
        } else {
            feedState = .loaded(feedItems)
        }
    }

    func applyLikeState(submissionId: UUID, liked: Bool, likeCount: Int) {
        guard let index = feedItems.firstIndex(where: { $0.id == submissionId }) else { return }
        feedItems[index] = feedItems[index].withLikeState(liked: liked, likeCount: likeCount)
        feedState = .loaded(feedItems)
    }

    func toggleLike(itemId: UUID) async {
        guard let index = feedItems.firstIndex(where: { $0.id == itemId }) else { return }
        guard networkMonitor.isOnline else {
            likeErrorMessage = "Reconnect to update Likes."
            return
        }
        guard isAuthenticated(), let token = accessTokenProvider() else {
            pendingLikeSubmissionId = itemId
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        guard !likeInFlightIDs.contains(itemId) else { return }

        let previous = feedItems[index]
        let nextLiked = !previous.viewerHasLiked
        let nextCount = max(0, previous.likeCount + (nextLiked ? 1 : -1))
        feedItems[index] = previous.withLikeState(liked: nextLiked, likeCount: nextCount)
        feedState = .loaded(feedItems)
        likeErrorMessage = nil
        likeInFlightIDs.insert(itemId)
        defer { likeInFlightIDs.remove(itemId) }

        do {
            let result: LikeStateModel
            if nextLiked {
                result = try await socialService.likeSubmission(
                    accessToken: token,
                    submissionId: itemId
                )
                analytics.track(.likeAdded, properties: ["submission_id": itemId.uuidString])
            } else {
                result = try await socialService.unlikeSubmission(
                    accessToken: token,
                    submissionId: itemId
                )
                analytics.track(.likeRemoved, properties: ["submission_id": itemId.uuidString])
            }
            if let refreshedIndex = feedItems.firstIndex(where: { $0.id == itemId }) {
                feedItems[refreshedIndex] = feedItems[refreshedIndex].withLikeState(
                    liked: result.liked,
                    likeCount: result.likeCount
                )
                feedState = .loaded(feedItems)
            }
        } catch {
            if let rollbackIndex = feedItems.firstIndex(where: { $0.id == itemId }) {
                feedItems[rollbackIndex] = previous
                feedState = .loaded(feedItems)
            }
            likeErrorMessage = error.localizedDescription
        }
    }

    func handleAuthenticationCompleted() async {
        showsAuthSheet = false
        guard let pendingId = pendingLikeSubmissionId else { return }
        pendingLikeSubmissionId = nil
        await toggleLike(itemId: pendingId)
    }

    func clearLikeError() {
        likeErrorMessage = nil
    }

    func startSketch() {
        guard let prompt = loadedPrompt else { return }
        analytics.track(.startSketchTapped, properties: ["prompt_id": prompt.id.uuidString])
        sketchFlow.startSketch(prompt: prompt)
    }

    func syncOfflineState() {
        isOffline = !networkMonitor.isOnline
    }

    private func restoreCachedHomeSnapshot() {
        guard let snapshot = try? homeCacheStore.load() else { return }
        cachedPrompt = snapshot.prompt
        if let prompt = snapshot.prompt {
            promptState = .loaded(prompt)
        }
        if !snapshot.feedItems.isEmpty {
            feedItems = snapshot.feedItems
            nextFeedCursor = snapshot.nextFeedCursor
            feedState = .loaded(feedItems)
        }
    }

    private func persistHomeCache() {
        let snapshot = CachedHomeSnapshot(
            prompt: cachedPrompt,
            feedItems: feedItems,
            nextFeedCursor: nextFeedCursor,
            cachedAt: Date()
        )
        try? homeCacheStore.save(snapshot)
    }

    private func loadPrompt() async {
        syncOfflineState()
        if let cachedPrompt {
            promptState = .loaded(cachedPrompt)
        } else {
            promptState = .loading
        }

        guard networkMonitor.isOnline else {
            if cachedPrompt != nil {
                isRefreshingPrompt = false
            } else {
                promptState = .failed("Couldn’t load today’s prompt while offline.")
            }
            return
        }

        isRefreshingPrompt = cachedPrompt != nil
        defer { isRefreshingPrompt = false }

        do {
            let prompt = try await promptFetcher.fetchTodaysPrompt()
            cachedPrompt = prompt
            promptState = .loaded(prompt)
            refreshPublishedToday()
            analytics.track(.promptViewed, properties: ["prompt_id": prompt.id.uuidString])
            persistHomeCache()
        } catch let error as PromptAPIError where error == .promptNotFound {
            cachedPrompt = nil
            promptState = .missing
            todaysPublished = []
            persistHomeCache()
        } catch {
            if cachedPrompt == nil {
                promptState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadFeed(reset: Bool) async {
        syncOfflineState()
        if reset {
            feedState = feedItems.isEmpty ? .loading : feedState
            isLoadingMoreFeed = false
        } else {
            guard let nextFeedCursor, !isLoadingMoreFeed else { return }
            isLoadingMoreFeed = true
            _ = nextFeedCursor
        }

        guard networkMonitor.isOnline else {
            if feedItems.isEmpty {
                feedState = .failed("Couldn’t load community sketches while offline.")
            }
            isLoadingMoreFeed = false
            return
        }

        let cursor = reset ? nil : nextFeedCursor
        do {
            let page = try await feedFetcher.fetchRecentFeed(
                accessToken: accessTokenProvider(),
                cursor: cursor,
                limit: feedPageSize
            )
            if reset {
                feedItems = page.items
            } else {
                let existingIDs = Set(feedItems.map(\.id))
                let appended = page.items.filter { !existingIDs.contains($0.id) }
                feedItems.append(contentsOf: appended)
            }
            nextFeedCursor = page.nextCursor
            feedState = feedItems.isEmpty ? .empty : .loaded(feedItems)
            persistHomeCache()
        } catch {
            if reset && feedItems.isEmpty {
                feedState = .failed(
                    "Couldn’t load community sketches. Check your connection and try again."
                )
            }
        }
        isLoadingMoreFeed = false
    }
}
