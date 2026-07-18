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
    case failed(String)
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var promptState: HomePromptState = .loading
    private(set) var feedState: HomeFeedState = .loading
    private(set) var cachedPrompt: DailyPromptModel?
    var showsStartSketchPlaceholder = false

    private let promptFetcher: any PromptFetching
    private let feedFetcher: any FeedFetching

    init(promptFetcher: any PromptFetching, feedFetcher: any FeedFetching) {
        self.promptFetcher = promptFetcher
        self.feedFetcher = feedFetcher
    }

    var canStartSketch: Bool {
        if case .loaded = promptState {
            return true
        }
        return false
    }

    var promptWords: [String]? {
        if case .loaded(let prompt) = promptState {
            return prompt.words
        }
        return cachedPrompt?.words
    }

    var promptAccessibilityLabel: String {
        if case .loaded(let prompt) = promptState {
            return prompt.accessibilityLabel
        }
        return cachedPrompt?.accessibilityLabel ?? "Today’s prompt is loading."
    }

    func load() async {
        async let promptLoad: Void = loadPrompt()
        async let feedLoad: Void = loadFeed()
        _ = await (promptLoad, feedLoad)
    }

    func retryPrompt() async {
        await loadPrompt()
    }

    func retryFeed() async {
        await loadFeed()
    }

    func startSketch() {
        guard canStartSketch else { return }
        showsStartSketchPlaceholder = true
    }

    func dismissStartSketchPlaceholder() {
        showsStartSketchPlaceholder = false
    }

    private func loadPrompt() async {
        // Show cache immediately while refreshing when available.
        if let cachedPrompt {
            promptState = .loaded(cachedPrompt)
        } else {
            promptState = .loading
        }

        do {
            let prompt = try await promptFetcher.fetchTodaysPrompt()
            cachedPrompt = prompt
            promptState = .loaded(prompt)
        } catch let error as PromptAPIError where error == .promptNotFound {
            // Never invent a local prompt when the server has none.
            cachedPrompt = nil
            promptState = .missing
        } catch {
            if cachedPrompt == nil {
                promptState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadFeed() async {
        feedState = .loading
        do {
            _ = try await feedFetcher.fetchRecentFeed(cursor: nil, limit: 20)
            // Phase 4 feed is empty until Submissions exist (Phase 7/8).
            feedState = .empty
        } catch {
            feedState = .failed("Couldn’t load community sketches. Check your connection and try again.")
        }
    }
}
