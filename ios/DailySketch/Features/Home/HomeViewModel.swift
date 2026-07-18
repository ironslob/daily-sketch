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

    private let promptFetcher: any PromptFetching
    private let feedFetcher: any FeedFetching
    let sketchFlow: SketchFlowViewModel

    init(
        promptFetcher: any PromptFetching,
        feedFetcher: any FeedFetching,
        sketchFlow: SketchFlowViewModel
    ) {
        self.promptFetcher = promptFetcher
        self.feedFetcher = feedFetcher
        self.sketchFlow = sketchFlow
    }

    var canStartSketch: Bool {
        if case .loaded = promptState {
            return true
        }
        return false
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

    func load() async {
        sketchFlow.prepareOnAppear()
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
        } catch let error as PromptAPIError where error == .promptNotFound {
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
            feedState = .empty
        } catch {
            feedState = .failed("Couldn’t load community sketches. Check your connection and try again.")
        }
    }
}
