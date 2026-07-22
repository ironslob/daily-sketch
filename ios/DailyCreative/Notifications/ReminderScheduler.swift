import Foundation
import UserNotifications

enum ReminderNotificationIdentifiers {
    static var dailyReminder: String {
        ProductConfig.current.dailyReminderNotificationId
    }
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

/// Bridges `UNUserNotificationCenter` outside MainActor isolation.
/// The center APIs are nonisolated / thread-safe; calling them from a MainActor type
/// with a stored center trips Swift 6 complete concurrency checking on Xcode 16.4.
enum NotificationCenterBridge {
    static func authorizationStatus() async -> ReminderPermissionStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status: ReminderPermissionStatus
                switch settings.authorizationStatus {
                case .notDetermined: status = .notDetermined
                case .authorized: status = .authorized
                case .denied: status = .denied
                case .provisional: status = .provisional
                case .ephemeral: status = .authorized
                @unknown default: status = .notDetermined
                }
                continuation.resume(returning: status)
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    static func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func cancelDailyReminder() {
        let identifier = ReminderNotificationIdentifiers.dailyReminder
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

struct SystemReminderScheduler: ReminderScheduling {
    func authorizationStatus() async -> ReminderPermissionStatus {
        await NotificationCenterBridge.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await NotificationCenterBridge.requestAuthorization()
    }

    func scheduleDailyReminder(at timeLocal: String, timezone: TimeZone) async throws {
        let (hour, minute) = try ReminderTimeParser.components(from: timeLocal)
        await cancelDailyReminder()

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.timeZone = timezone

        let content = UNMutableNotificationContent()
        content.title = ProductConfig.current.brandName
        content.body = "Today’s inspiration is ready."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: ReminderNotificationIdentifiers.dailyReminder,
            content: content,
            trigger: trigger
        )
        try await NotificationCenterBridge.add(request)
    }

    func cancelDailyReminder() async {
        NotificationCenterBridge.cancelDailyReminder()
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
