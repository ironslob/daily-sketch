import Foundation

struct DailyPromptModel: Equatable, Sendable, Identifiable {
    let id: UUID
    let promptDate: Date
    let word1: String
    let word2: String
    let word3: String
    let status: String
    let publishedAt: Date?

    var words: [String] { [word1, word2, word3] }

    var accessibilityLabel: String {
        "Today’s prompt: \(word1), \(word2), \(word3)."
    }
}

struct RecentFeedPage: Equatable, Sendable {
    let items: [FeedItemModel]
    let nextCursor: String?
}

struct FeedItemModel: Equatable, Sendable, Identifiable {
    let id: UUID
}

enum PromptAPIError: Error, Equatable, LocalizedError {
    case promptNotFound
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .promptNotFound:
            return "Today’s prompt is not available yet."
        case .underlying(let message):
            return message
        }
    }
}
