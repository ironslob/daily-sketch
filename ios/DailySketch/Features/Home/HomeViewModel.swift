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

    private let promptFetcher: any PromptFetching
    private let feedFetcher: any FeedFetching
    private let publishedStore: any PublishedSubmissionStoring
    let sketchFlow: SketchFlowViewModel
    private let feedPageSize = 20

    init(
        promptFetcher: any PromptFetching,
        feedFetcher: any FeedFetching,
        publishedStore: any PublishedSubmissionStoring,
        sketchFlow: SketchFlowViewModel
    ) {
        self.promptFetcher = promptFetcher
        self.feedFetcher = feedFetcher
        self.publishedStore = publishedStore
        self.sketchFlow = sketchFlow
    }

    var canStartSketch: Bool {
        if case .loaded = promptState {
            return true
        }
        return false
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
        nextFeedCursor != nil && !isLoadingMoreFeed
    }

    func load() async {
        sketchFlow.prepareOnAppear()
        refreshPublishedToday()
        async let promptLoad: Void = loadPrompt()
        async let feedLoad: Void = loadFeed(reset: true)
        _ = await (promptLoad, feedLoad)
    }

    func refresh() async {
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

    func startSketch() {
        guard let prompt = loadedPrompt else { return }
        sketchFlow.startSketch(prompt: prompt)
    }

    private func loadPrompt() async {
        if let cachedPrompt {
            promptState = .loaded(cachedPrompt)
        } else {
            promptState = .loading
        }

        do {
            let prompt = try await promptFetcher.fetchTodaysPrompt()
            cachedPrompt = prompt
            promptState = .loaded(prompt)
            refreshPublishedToday()
        } catch let error as PromptAPIError where error == .promptNotFound {
            cachedPrompt = nil
            promptState = .missing
            todaysPublished = []
        } catch {
            if cachedPrompt == nil {
                promptState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadFeed(reset: Bool) async {
        if reset {
            feedState = feedItems.isEmpty ? .loading : feedState
            isLoadingMoreFeed = false
        } else {
            guard let nextFeedCursor, !isLoadingMoreFeed else { return }
            isLoadingMoreFeed = true
            _ = nextFeedCursor
        }

        let cursor = reset ? nil : nextFeedCursor
        do {
            let page = try await feedFetcher.fetchRecentFeed(cursor: cursor, limit: feedPageSize)
            if reset {
                feedItems = page.items
            } else {
                let existingIDs = Set(feedItems.map(\.id))
                let appended = page.items.filter { !existingIDs.contains($0.id) }
                feedItems.append(contentsOf: appended)
            }
            nextFeedCursor = page.nextCursor
            feedState = feedItems.isEmpty ? .empty : .loaded(feedItems)
        } catch {
            if reset && feedItems.isEmpty {
                feedState = .failed(
                    "Couldn’t load community sketches. Check your connection and try again."
                )
            }
            // Keep previously loaded feed visible on pagination failure.
        }
        isLoadingMoreFeed = false
    }
}
