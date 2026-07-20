import Foundation
import UserNotifications

enum ReminderNotificationIdentifiers {
    static let dailyReminder = "daily-sketch.daily-reminder"
}

enum ReminderPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
}

@MainActor
protocol ReminderScheduling {
    func authorizationStatus() async -> ReminderPermissionStatus
    func requestAuthorization() async -> Bool
    func scheduleDailyReminder(at timeLocal: String, timezone: TimeZone) async throws
    func cancelDailyReminder() async
}

enum ReminderSchedulerError: LocalizedError, Equatable {
    case invalidTimeFormat

    var errorDescription: String? {
        switch self {
        case .invalidTimeFormat:
            return "Reminder time could not be parsed."
        }
    }
}

enum ReminderTimeParser {
    /// Parses `HH:mm:ss` or `HH:mm` into hour/minute components.
    static func components(from timeLocal: String) throws -> (hour: Int, minute: Int) {
        let parts = timeLocal.split(separator: ":").map(String.init)
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            throw ReminderSchedulerError.invalidTimeFormat
        }
        return (hour, minute)
    }
}

struct SystemReminderScheduler: ReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> ReminderPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        case .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleDailyReminder(at timeLocal: String, timezone: TimeZone) async throws {
        let (hour, minute) = try ReminderTimeParser.components(from: timeLocal)
        await cancelDailyReminder()

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.timeZone = timezone

        let content = UNMutableNotificationContent()
        content.title = "Daily Sketch"
        content.body = "Today’s inspiration is ready."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: ReminderNotificationIdentifiers.dailyReminder,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func cancelDailyReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderNotificationIdentifiers.dailyReminder])
        center.removeDeliveredNotifications(withIdentifiers: [ReminderNotificationIdentifiers.dailyReminder])
    }
}

/// Syncs backend reminder preferences with local notification scheduling.
@MainActor
struct ReminderPreferenceSync {
    let scheduler: any ReminderScheduling

    func sync(preferences: UserPreferencesModel) async {
        guard preferences.notificationsEnabled,
              let timeLocal = preferences.notificationTimeLocal else {
            await scheduler.cancelDailyReminder()
            return
        }

        let status = await scheduler.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return
        }

        let timezone = TimeZone(identifier: preferences.timezone) ?? .current
        try? await scheduler.scheduleDailyReminder(at: timeLocal, timezone: timezone)
    }
}

@MainActor
final class InMemoryReminderScheduler: ReminderScheduling {
    var authorizationStatusValue: ReminderPermissionStatus = .notDetermined
    private(set) var scheduledTimeLocal: String?
    private(set) var scheduledTimezone: TimeZone?
    private(set) var requestAuthorizationCallCount = 0
    private(set) var cancelCallCount = 0

    func authorizationStatus() async -> ReminderPermissionStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        authorizationStatusValue = .authorized
        return true
    }

    func scheduleDailyReminder(at timeLocal: String, timezone: TimeZone) async throws {
        scheduledTimeLocal = timeLocal
        scheduledTimezone = timezone
    }

    func cancelDailyReminder() async {
        cancelCallCount += 1
        scheduledTimeLocal = nil
        scheduledTimezone = nil
    }
}
