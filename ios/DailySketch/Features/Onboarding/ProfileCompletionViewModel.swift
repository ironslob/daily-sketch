import Foundation
import Observation

@MainActor
@Observable
final class ProfileCompletionViewModel {
    var username: String = ""
    var displayName: String = ""
    var enableReminder: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var usernameHint: String?

    private let auth: AuthSessionStore
    private let preferencesService: (any PreferencesServing)?
    private let reminderSync: ReminderPreferenceSync?
    private let analytics: (any AnalyticsTracking)?

    init(
        auth: AuthSessionStore,
        preferencesService: (any PreferencesServing)? = nil,
        reminderSync: ReminderPreferenceSync? = nil,
        analytics: (any AnalyticsTracking)? = nil
    ) {
        self.auth = auth
        self.preferencesService = preferencesService
        self.reminderSync = reminderSync
        self.analytics = analytics
        self.displayName = auth.currentUser?.displayName ?? ""
        self.username = auth.currentUser?.username ?? ""
    }

    var canSave: Bool {
        UsernameValidator.isValidFormat(username)
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    func validateUsernameLive() {
        usernameHint = UsernameValidator.validationMessage(for: username)
    }

    func save() async -> Bool {
        validateUsernameLive()
        guard canSave else {
            errorMessage = usernameHint ?? "Enter a username and display name."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await auth.completeProfile(username: trimmedUsername, displayName: trimmedDisplay)
            if enableReminder, let token = auth.accessToken, let preferencesService {
                var prefs = try await preferencesService.getPreferences(accessToken: token)
                prefs.notificationsEnabled = true
                if prefs.notificationTimeLocal == nil {
                    prefs.notificationTimeLocal = "09:00:00"
                }
                if let reminderSync {
                    var status = await reminderSync.scheduler.authorizationStatus()
                    if status == .notDetermined {
                        let granted = await reminderSync.scheduler.requestAuthorization()
                        status = granted ? .authorized : .denied
                    }
                    if status == .authorized || status == .provisional {
                        await reminderSync.sync(preferences: prefs)
                    }
                }
                _ = try await preferencesService.updatePreferences(accessToken: token, preferences: prefs)
                analytics?.track(.reminderEnabled)
            }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
