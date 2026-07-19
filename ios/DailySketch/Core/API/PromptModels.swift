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
    let imageURL: URL
    let thumbnailURL: URL
    let userId: UUID
    let username: String
    let displayName: String
    let avatarURL: URL?
    let promptWords: [String]
    let promptDate: Date
    let timerMode: String
    let timerSeconds: Int?
    let captionPreview: String?
    let likeCount: Int
    let reflectionCount: Int
    let viewerHasLiked: Bool
    let isOwner: Bool
    let publishedAt: Date

    var relativePublishedAt: String {
        RelativeTimestampFormatter.string(from: publishedAt)
    }

    var timerLabel: String {
        if timerMode == "no_timer" {
            return "No timer"
        }
        guard let timerSeconds else { return "Timer" }
        let minutes = timerSeconds / 60
        if minutes == 1 {
            return "1 min"
        }
        return "\(minutes) min"
    }

    var metadataLine: String {
        let prompt = promptWords.joined(separator: ", ")
        return "Prompt: \(prompt) • \(timerLabel)"
    }

    static var preview: FeedItemModel {
        FeedItemModel(
            id: UUID(uuidString: "d4e5f6a7-b8c9-0123-def0-234567890123")!,
            imageURL: URL(string: "https://example.test/display")!,
            thumbnailURL: URL(string: "https://example.test/thumb")!,
            userId: UUID(uuidString: "f7d7c950-2892-4b6c-9300-ef6c5cbcb2d1")!,
            username: "sketchy_matt",
            displayName: "Matt",
            avatarURL: nil,
            promptWords: ["Chocolate", "Coffee", "Banana"],
            promptDate: Date(timeIntervalSince1970: 1_784_332_800),
            timerMode: "countdown",
            timerSeconds: 300,
            captionPreview: "A quiet coffee and banana sketch.",
            likeCount: 0,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: false,
            publishedAt: Date().addingTimeInterval(-7_200)
        )
    }
}

enum RelativeTimestampFormatter {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = hours / 24
        if days < 7 {
            return "\(days)d ago"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
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
