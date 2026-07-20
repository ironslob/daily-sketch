import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var preferences: UserPreferencesModel = .defaults
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var loadFailed = false
    private(set) var reminderPermissionStatus: ReminderPermissionStatus = .notDetermined

    private let auth: AuthSessionStore
    private let preferencesService: any PreferencesServing
    private let reminderSync: ReminderPreferenceSync
    private let appearanceStore: AppearanceStore
    private let analytics: any AnalyticsTracking

    init(
        auth: AuthSessionStore,
        preferencesService: any PreferencesServing,
        reminderSync: ReminderPreferenceSync,
        appearanceStore: AppearanceStore,
        analytics: any AnalyticsTracking
    ) {
        self.auth = auth
        self.preferencesService = preferencesService
        self.reminderSync = reminderSync
        self.appearanceStore = appearanceStore
        self.analytics = analytics
    }

    var selectedTimer: TimerPreferenceOption? {
        TimerPreferenceOption.from(
            mode: preferences.rememberedTimerMode,
            seconds: preferences.rememberedTimerSeconds
        )
    }

    var reminderTimeDate: Date {
        get {
            Self.date(from: preferences.notificationTimeLocal ?? "09:00:00")
        }
        set {
            preferences.notificationTimeLocal = Self.timeLocal(from: newValue)
        }
    }

    var showsOpenSettingsForNotifications: Bool {
        reminderPermissionStatus == .denied && preferences.notificationsEnabled
    }

    func load() async {
        guard let token = auth.accessToken else {
            loadFailed = false
            preferences = .defaults
            return
        }
        isLoading = true
        errorMessage = nil
        loadFailed = false
        defer { isLoading = false }
        do {
            preferences = try await preferencesService.getPreferences(accessToken: token)
            appearanceStore.update(from: preferences)
            reminderPermissionStatus = await reminderSync.scheduler.authorizationStatus()
            await reminderSync.sync(preferences: preferences)
        } catch {
            loadFailed = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshReminderPermissionStatus() async {
        reminderPermissionStatus = await reminderSync.scheduler.authorizationStatus()
    }

    func setRememberTimer(_ enabled: Bool) async {
        preferences.rememberTimerOption = enabled
        if !enabled {
            preferences.rememberedTimerMode = nil
            preferences.rememberedTimerSeconds = nil
        } else if preferences.rememberedTimerMode == nil {
            preferences.rememberedTimerMode = TimerPreferenceOption.fiveMinutes.mode
            preferences.rememberedTimerSeconds = TimerPreferenceOption.fiveMinutes.seconds
        }
        await save()
    }

    func setTimerOption(_ option: TimerPreferenceOption) async {
        preferences.rememberTimerOption = true
        preferences.rememberedTimerMode = option.mode
        preferences.rememberedTimerSeconds = option.seconds
        await save()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            preferences.notificationsEnabled = true
            if preferences.notificationTimeLocal == nil {
                preferences.notificationTimeLocal = "09:00:00"
            }
            reminderPermissionStatus = await requestReminderAuthorizationIfNeeded()
            if reminderPermissionStatus == .authorized || reminderPermissionStatus == .provisional {
                await reminderSync.sync(preferences: preferences)
            } else {
                await reminderSync.scheduler.cancelDailyReminder()
            }
            analytics.track(.reminderEnabled)
        } else {
            preferences.notificationsEnabled = false
            await reminderSync.scheduler.cancelDailyReminder()
            analytics.track(.reminderDisabled)
        }
        await save()
    }

    func setReminderTime(_ date: Date) async {
        preferences.notificationTimeLocal = Self.timeLocal(from: date)
        if preferences.notificationsEnabled {
            reminderPermissionStatus = await reminderSync.scheduler.authorizationStatus()
            if reminderPermissionStatus == .authorized || reminderPermissionStatus == .provisional {
                await reminderSync.sync(preferences: preferences)
            }
        }
        await save()
    }

    private func requestReminderAuthorizationIfNeeded() async -> ReminderPermissionStatus {
        var status = await reminderSync.scheduler.authorizationStatus()
        if status == .notDetermined {
            let granted = await reminderSync.scheduler.requestAuthorization()
            status = granted ? .authorized : .denied
        }
        return status
    }

    func setAppearance(_ appearance: String) async {
        preferences.appearance = appearance
        appearanceStore.update(from: preferences)
        await save()
    }

    func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            preferences = try await preferencesService.updatePreferences(
                accessToken: token,
                preferences: preferences
            )
            appearanceStore.update(from: preferences)
            await reminderSync.sync(preferences: preferences)
            reminderPermissionStatus = await reminderSync.scheduler.authorizationStatus()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await load()
        }
    }

    private static func date(from timeLocal: String) -> Date {
        let parts = timeLocal.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.first ?? 9
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func timeLocal(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d:00", hour, minute)
    }
}
