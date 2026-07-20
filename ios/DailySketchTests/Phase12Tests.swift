import SwiftUI
import XCTest
@testable import DailySketch

final class ReminderSchedulerTests: XCTestCase {
    @MainActor
    func testScheduleAndRescheduleUsesLatestTime() async throws {
        let scheduler = InMemoryReminderScheduler()
        scheduler.authorizationStatusValue = .authorized

        try await scheduler.scheduleDailyReminder(at: "09:00:00", timezone: .current)
        XCTAssertEqual(scheduler.scheduledTimeLocal, "09:00:00")

        try await scheduler.scheduleDailyReminder(at: "08:30:00", timezone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(scheduler.scheduledTimeLocal, "08:30:00")
        XCTAssertEqual(scheduler.scheduledTimezone?.identifier, "America/Los_Angeles")
    }

    @MainActor
    func testCancelClearsScheduledReminder() async throws {
        let scheduler = InMemoryReminderScheduler()
        try await scheduler.scheduleDailyReminder(at: "09:00:00", timezone: .current)
        await scheduler.cancelDailyReminder()
        XCTAssertNil(scheduler.scheduledTimeLocal)
        XCTAssertEqual(scheduler.cancelCallCount, 1)
    }

    func testInvalidTimeFormatThrows() {
        XCTAssertThrowsError(try ReminderTimeParser.components(from: "invalid")) { error in
            XCTAssertEqual(error as? ReminderSchedulerError, .invalidTimeFormat)
        }
    }

    @MainActor
    func testPreferenceSyncSchedulesWhenEnabled() async {
        let scheduler = InMemoryReminderScheduler()
        scheduler.authorizationStatusValue = .authorized
        let sync = ReminderPreferenceSync(scheduler: scheduler)
        let prefs = UserPreferencesModel(
            notificationsEnabled: true,
            notificationTimeLocal: "07:15:00",
            timezone: "UTC",
            rememberTimerOption: false,
            rememberedTimerMode: nil,
            rememberedTimerSeconds: nil,
            appearance: "system"
        )

        await sync.sync(preferences: prefs)

        XCTAssertEqual(scheduler.scheduledTimeLocal, "07:15:00")
    }

    @MainActor
    func testPreferenceSyncCancelsWhenDisabled() async {
        let scheduler = InMemoryReminderScheduler()
        scheduler.authorizationStatusValue = .authorized
        try? await scheduler.scheduleDailyReminder(at: "09:00:00", timezone: .current)
        let sync = ReminderPreferenceSync(scheduler: scheduler)
        let prefs = UserPreferencesModel.defaults

        await sync.sync(preferences: prefs)

        XCTAssertNil(scheduler.scheduledTimeLocal)
    }
}

@MainActor
final class ReminderNavigationTests: XCTestCase {
    func testNotificationTapOpensHomeTab() {
        let navigation = AppNavigationStore()
        navigation.selectedTab = .profile
        navigation.homePath.append(.settings)

        navigation.openHomeFromReminder()

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.homePath.isEmpty)
    }
}

final class AnalyticsClientTests: XCTestCase {
    func testSanitizerRemovesSensitiveKeys() {
        let sanitized = AnalyticsSanitizer.sanitize([
            "email": "user@example.com",
            "token": "secret",
            "caption": "private",
            "prompt_id": "abc",
            "signed_url": "https://x.test/file?X-Amz-Signature=abc"
        ])

        XCTAssertNil(sanitized["email"])
        XCTAssertNil(sanitized["token"])
        XCTAssertNil(sanitized["caption"])
        XCTAssertEqual(sanitized["prompt_id"], "abc")
        XCTAssertNil(sanitized["signed_url"])
    }

    func testTrackStoresScrubbedRecord() {
        let client = InMemoryAnalyticsClient()
        client.track(.promptViewed, properties: [
            "prompt_id": "123",
            "email": "hidden@example.com"
        ])

        let records = client.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, .promptViewed)
        XCTAssertEqual(records.first?.properties["prompt_id"], "123")
        XCTAssertNil(records.first?.properties["email"])
    }
}

@MainActor
final class HomeOfflineTests: XCTestCase {
    private func samplePrompt() -> DailyPromptModel {
        DailyPromptModel(
            id: UUID(),
            promptDate: Date(timeIntervalSince1970: 1_784_332_800),
            word1: "A",
            word2: "B",
            word3: "C",
            status: "published",
            publishedAt: Date()
        )
    }

    private func makeModel(
        fetcher: RecordingPromptFetcher,
        network: FixedNetworkMonitor,
        cache: InMemoryHomeCacheStore = InMemoryHomeCacheStore()
    ) -> HomeViewModel {
        let auth = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: RecordingMeFetcher(
                profile: CurrentUserProfile(
                    id: UUID(),
                    username: nil,
                    displayName: "Guest",
                    profileCompleted: false,
                    status: "incomplete"
                )
            )
        )
        let sketchFlow = SketchFlowViewModel(
            auth: auth,
            preferencesService: RecordingMeFetcher(
                profile: CurrentUserProfile(
                    id: UUID(),
                    username: nil,
                    displayName: "Guest",
                    profileCompleted: false,
                    status: "incomplete"
                )
            ),
            guestTimerStore: InMemoryGuestTimerPreferenceStore(),
            activeSessionStore: InMemoryActiveSessionStore(),
            sessionService: RecordingSketchSessionRepository(),
            draftStore: InMemoryDraftStore(),
            imageStore: InMemoryDraftImageStore(),
            cameraAuthorizer: FakeCameraAuthorizer()
        )
        return HomeViewModel(
            promptFetcher: fetcher,
            feedFetcher: fetcher,
            socialService: RecordingSocialRepository(),
            publishedStore: InMemoryPublishedSubmissionStore(),
            homeCacheStore: cache,
            networkMonitor: network,
            analytics: InMemoryAnalyticsClient(),
            sketchFlow: sketchFlow
        )
    }

    func testOfflineUsesCachedPromptAndAllowsStartSketch() async throws {
        let fetcher = RecordingPromptFetcher()
        fetcher.prompt = samplePrompt()
        let cache = InMemoryHomeCacheStore()
        try cache.save(
            CachedHomeSnapshot(
                prompt: samplePrompt(),
                feedItems: [],
                nextFeedCursor: nil,
                cachedAt: Date()
            )
        )
        let network = FixedNetworkMonitor(isOnline: false)
        let model = makeModel(fetcher: fetcher, network: network, cache: cache)

        await model.load()

        XCTAssertTrue(model.isOffline)
        XCTAssertTrue(model.canStartSketch)
        XCTAssertNotNil(model.offlineIndicatorMessage)
        XCTAssertEqual(fetcher.todaysPromptCallCount, 0)
    }

    func testOfflineDraftStorePreservesRecoverableDraft() async throws {
        let draftStore = InMemoryDraftStore()
        let imageStore = InMemoryDraftImageStore()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let fileName = try imageStore.write(imageData)
        let draft = LocalDraft(
            id: UUID(),
            localSessionId: UUID(),
            serverSessionId: UUID(),
            promptId: samplePrompt().id,
            promptWords: ["A", "B", "C"],
            promptAccessibilityLabel: "Today’s prompt: A, B, C.",
            promptDate: samplePrompt().promptDate,
            timerMode: "countdown",
            selectedTimerSeconds: 300,
            sessionStartedAt: Date(),
            imageFileName: fileName,
            caption: "offline draft",
            createdAt: Date(),
            updatedAt: Date(),
            pendingAuthentication: false,
            pendingPublication: false
        )
        try draftStore.save(draft)

        XCTAssertEqual(try draftStore.mostRecentRecoverable()?.caption, "offline draft")
    }
}

final class AppearancePreferenceTests: XCTestCase {
    func testAppearanceMapping() {
        XCTAssertNil(AppearancePreferenceMapper.colorScheme(for: "system"))
        XCTAssertEqual(AppearancePreferenceMapper.colorScheme(for: "light"), .light)
        XCTAssertEqual(AppearancePreferenceMapper.colorScheme(for: "dark"), .dark)
    }
}
