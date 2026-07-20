import SwiftUI
import UserNotifications

@main
struct DailySketchApp: App {
    @State private var dependencies = AppDependencies.live

    init() {
        let memoryCapacity = 32 * 1024 * 1024
        let diskCapacity = 256 * 1024 * 1024
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "daily-sketch-image-cache"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .preferredColorScheme(dependencies.appearanceStore.colorScheme)
                .task {
                    UNUserNotificationCenter.current().delegate = dependencies.reminderNotificationDelegate
                    dependencies.analytics.track(.appOpened)
                    await dependencies.auth.bootstrap()
                    await dependencies.hydrateUserPreferences()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await dependencies.hydrateUserPreferences() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await dependencies.hydrateUserPreferences() }
                }
        }
    }
}
