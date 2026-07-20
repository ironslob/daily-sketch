import Foundation
import OSLog

enum AnalyticsEventName: String, Sendable {
    case appOpened = "app_opened"
    case promptViewed = "prompt_viewed"
    case startSketchTapped = "start_sketch_tapped"
    case timerOptionSelected = "timer_option_selected"
    case sketchSessionStarted = "sketch_session_started"
    case sketchSessionPaused = "sketch_session_paused"
    case sketchSessionResumed = "sketch_session_resumed"
    case timerCompleted = "timer_completed"
    case sessionFinishedEarly = "session_finished_early"
    case sessionAbandoned = "session_abandoned"
    case photoCapturedOrSelected = "photo_captured_or_selected"
    case reviewSubmissionViewed = "review_submission_viewed"
    case authCheckpointShown = "auth_checkpoint_shown"
    case draftSaved = "draft_saved"
    case uploadStarted = "upload_started"
    case uploadCompleted = "upload_completed"
    case uploadFailed = "upload_failed"
    case submissionPublished = "submission_published"
    case feedViewed = "feed_viewed"
    case submissionDetailViewed = "submission_detail_viewed"
    case likeAdded = "like_added"
    case likeRemoved = "like_removed"
    case reflectionPosted = "reflection_posted"
    case reflectionDeleted = "reflection_deleted"
    case profileViewed = "profile_viewed"
    case reminderEnabled = "reminder_enabled"
    case reminderDisabled = "reminder_disabled"
}

struct AnalyticsRecord: Equatable, Sendable {
    let name: AnalyticsEventName
    let properties: [String: String]
    let timestamp: Date
}

protocol AnalyticsTracking: Sendable {
    func track(_ name: AnalyticsEventName, properties: [String: String])
    func records() -> [AnalyticsRecord]
}

extension AnalyticsTracking {
    func track(_ name: AnalyticsEventName) {
        track(name, properties: [:])
    }
}

enum AnalyticsSanitizer {
    private static let blockedKeys: Set<String> = [
        "email",
        "token",
        "access_token",
        "caption",
        "image",
        "image_data",
        "descope_subject",
        "descope_id",
        "password",
        "authorization"
    ]

    static func sanitize(_ properties: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (key, value) in properties {
            let lowered = key.lowercased()
            if blockedKeys.contains(lowered) { continue }
            if lowered.contains("token") { continue }
            if lowered.contains("email") { continue }
            if value.contains("X-Amz-") || value.contains("Signature=") { continue }
            if value.hasPrefix("Bearer ") { continue }
            sanitized[key] = value
        }
        return sanitized
    }
}

final class AnalyticsClient: AnalyticsTracking, @unchecked Sendable {
    static let shared = AnalyticsClient()

    private let lock = NSLock()
    nonisolated(unsafe) private var buffer: [AnalyticsRecord] = []
    private let logger = Logger(subsystem: "com.example.dailysketch", category: "analytics")
    private let maxRecords = 500

    func track(_ name: AnalyticsEventName, properties: [String: String] = [:]) {
        let sanitized = AnalyticsSanitizer.sanitize(properties)
        let record = AnalyticsRecord(name: name, properties: sanitized, timestamp: Date())
        lock.lock()
        buffer.append(record)
        if buffer.count > maxRecords {
            buffer.removeFirst(buffer.count - maxRecords)
        }
        lock.unlock()
        logger.info("event=\(name.rawValue, privacy: .public) props=\(sanitized.description, privacy: .public)")
    }

    func records() -> [AnalyticsRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

final class InMemoryAnalyticsClient: AnalyticsTracking, @unchecked Sendable {
    private var buffer: [AnalyticsRecord] = []

    func track(_ name: AnalyticsEventName, properties: [String: String] = [:]) {
        let sanitized = AnalyticsSanitizer.sanitize(properties)
        buffer.append(AnalyticsRecord(name: name, properties: sanitized, timestamp: Date()))
    }

    func records() -> [AnalyticsRecord] {
        buffer
    }
}
