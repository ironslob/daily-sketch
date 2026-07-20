import XCTest
@testable import DailySketch

final class UsernameValidatorTests: XCTestCase {
    func testValidFormats() {
        XCTAssertTrue(UsernameValidator.isValidFormat("abc"))
        XCTAssertTrue(UsernameValidator.isValidFormat("Sketchy_Matt"))
        XCTAssertNil(UsernameValidator.validationMessage(for: "valid_name"))
    }

    func testInvalidFormats() {
        XCTAssertFalse(UsernameValidator.isValidFormat("ab"))
        XCTAssertFalse(UsernameValidator.isValidFormat("bad-name"))
        XCTAssertFalse(UsernameValidator.isValidFormat("has space"))
        XCTAssertNotNil(UsernameValidator.validationMessage(for: "ab"))
    }

    func testTimerPreferenceMapping() {
        XCTAssertEqual(
            TimerPreferenceOption.from(mode: "countdown", seconds: 300),
            .fiveMinutes
        )
        XCTAssertEqual(
            TimerPreferenceOption.from(mode: "no_timer", seconds: nil),
            .noTimer
        )
        XCTAssertNil(TimerPreferenceOption.from(mode: "countdown", seconds: 90))
    }
}

@MainActor
final class ProfileCompletionRoutingTests: XCTestCase {
    func testIncompleteProfileRequiresCompletionBeforePublishing() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Ada",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        let store = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: meFetcher,
            profileUpdater: meFetcher
        )
        await store.signIn(displayName: "Ada")
        XCTAssertTrue(store.needsProfileCompletion)
        XCTAssertFalse(store.requireCompleteProfileForPublishing())
    }

    func testCompletedProfileAllowsPublishingGate() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: "ada",
                displayName: "Ada",
                profileCompleted: true,
                status: "active"
            )
        )
        let store = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: meFetcher,
            profileUpdater: meFetcher
        )
        await store.signIn(displayName: "Ada")
        XCTAssertFalse(store.needsProfileCompletion)
        XCTAssertTrue(store.requireCompleteProfileForPublishing())
    }

    func testCompleteProfileUpdatesCurrentUser() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Ada",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        let store = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: meFetcher,
            profileUpdater: meFetcher
        )
        await store.signIn(displayName: "Ada")
        try? await store.completeProfile(username: "ada_lovelace", displayName: "Ada")
        XCTAssertEqual(store.currentUser?.username, "ada_lovelace")
        XCTAssertTrue(store.currentUser?.profileCompleted == true)
        XCTAssertFalse(store.needsProfileCompletion)
    }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testPreferencesMappingRoundTrip() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: "ada",
                displayName: "Ada",
                profileCompleted: true,
                status: "active"
            )
        )
        meFetcher.preferences = UserPreferencesModel(
            notificationsEnabled: true,
            notificationTimeLocal: "08:30:00",
            timezone: "UTC",
            rememberTimerOption: true,
            rememberedTimerMode: "countdown",
            rememberedTimerSeconds: 180,
            appearance: "dark"
        )
        let store = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: meFetcher,
            profileUpdater: meFetcher
        )
        await store.signIn(displayName: "Ada")
        let viewModel = SettingsViewModel(
            auth: store,
            preferencesService: meFetcher,
            reminderSync: ReminderPreferenceSync(scheduler: InMemoryReminderScheduler()),
            appearanceStore: AppearanceStore(),
            analytics: InMemoryAnalyticsClient()
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.selectedTimer, .threeMinutes)
        XCTAssertEqual(viewModel.preferences.appearance, "dark")

        await viewModel.setTimerOption(.noTimer)
        XCTAssertEqual(meFetcher.preferences.rememberedTimerMode, "no_timer")
        XCTAssertNil(meFetcher.preferences.rememberedTimerSeconds)
    }
}
