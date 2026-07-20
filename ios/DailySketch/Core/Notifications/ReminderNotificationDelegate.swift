import Foundation
import UserNotifications

@MainActor
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var navigation: AppNavigationStore?

    init(navigation: AppNavigationStore) {
        self.navigation = navigation
    }

    func configure(with navigation: AppNavigationStore) {
        self.navigation = navigation
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == ReminderNotificationIdentifiers.dailyReminder else {
            return
        }
        await MainActor.run {
            navigation?.openHomeFromReminder()
        }
    }
}
