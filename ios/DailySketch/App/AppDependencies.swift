import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies {
    let environment: AppEnvironment
    let navigation: AppNavigationStore
    let auth: AuthSessionStore
    let descopeAuthService: DescopeAuthService?
    let preferencesService: any PreferencesServing
    let profileUpdater: any ProfileUpdating
    let profileRepository: any ProfileFetching
    let promptRepository: PromptRepository
    let sketchSessionRepository: any SketchSessionServing
    let uploadRepository: any UploadServing
    let submissionRepository: any SubmissionServing
    let socialRepository: any SocialServing
    let safetyRepository: any SafetyServing
    let accountDeleter: any AccountDeleting
    let directUploader: any DirectUploadTransporting
    let activeSessionStore: any ActiveSessionStoring
    let guestTimerPreferenceStore: any GuestTimerPreferenceStoring
    let draftStore: any DraftStoring
    let draftImageStore: any DraftImageStoring
    let publishedSubmissionStore: any PublishedSubmissionStoring
    let cameraAuthorizer: any CameraAuthorizing
    let reminderScheduler: any ReminderScheduling
    let reminderNotificationDelegate: ReminderNotificationDelegate
    let networkMonitor: NetworkPathMonitorService
    let homeCacheStore: any HomeCacheStoring
    let appearanceStore: AppearanceStore
    let analytics: any AnalyticsTracking

    init(
        environment: AppEnvironment,
        navigation: AppNavigationStore = AppNavigationStore(),
        auth: AuthSessionStore,
        descopeAuthService: DescopeAuthService? = nil,
        preferencesService: any PreferencesServing,
        profileUpdater: any ProfileUpdating,
        profileRepository: any ProfileFetching,
        promptRepository: PromptRepository,
        sketchSessionRepository: any SketchSessionServing,
        uploadRepository: any UploadServing,
        submissionRepository: any SubmissionServing,
        socialRepository: any SocialServing,
        safetyRepository: any SafetyServing,
        accountDeleter: any AccountDeleting,
        directUploader: any DirectUploadTransporting = URLSessionDirectUploader(),
        activeSessionStore: any ActiveSessionStoring,
        guestTimerPreferenceStore: any GuestTimerPreferenceStoring,
        draftStore: any DraftStoring,
        draftImageStore: any DraftImageStoring,
        publishedSubmissionStore: any PublishedSubmissionStoring,
        cameraAuthorizer: any CameraAuthorizing,
        reminderScheduler: any ReminderScheduling = SystemReminderScheduler(),
        reminderNotificationDelegate: ReminderNotificationDelegate? = nil,
        networkMonitor: NetworkPathMonitorService? = nil,
        homeCacheStore: any HomeCacheStoring = HomeCacheStore(),
        appearanceStore: AppearanceStore = AppearanceStore(),
        analytics: any AnalyticsTracking = AnalyticsClient.shared
    ) {
        self.environment = environment
        self.navigation = navigation
        self.auth = auth
        self.descopeAuthService = descopeAuthService
        self.preferencesService = preferencesService
        self.profileUpdater = profileUpdater
        self.profileRepository = profileRepository
        self.promptRepository = promptRepository
        self.sketchSessionRepository = sketchSessionRepository
        self.uploadRepository = uploadRepository
        self.submissionRepository = submissionRepository
        self.socialRepository = socialRepository
        self.safetyRepository = safetyRepository
        self.accountDeleter = accountDeleter
        self.directUploader = directUploader
        self.activeSessionStore = activeSessionStore
        self.guestTimerPreferenceStore = guestTimerPreferenceStore
        self.draftStore = draftStore
        self.draftImageStore = draftImageStore
        self.publishedSubmissionStore = publishedSubmissionStore
        self.cameraAuthorizer = cameraAuthorizer
        self.reminderScheduler = reminderScheduler
        self.reminderNotificationDelegate = reminderNotificationDelegate ?? ReminderNotificationDelegate(navigation: navigation)
        self.networkMonitor = networkMonitor ?? NetworkPathMonitorService()
        self.homeCacheStore = homeCacheStore
        self.appearanceStore = appearanceStore
        self.analytics = analytics
        self.reminderNotificationDelegate.configure(with: navigation)
    }

    var reminderSync: ReminderPreferenceSync {
        ReminderPreferenceSync(scheduler: reminderScheduler)
    }

    @MainActor
    func hydrateUserPreferences() async {
        guard let token = auth.accessToken else { return }
        do {
            let prefs = try await preferencesService.getPreferences(accessToken: token)
            appearanceStore.update(from: prefs)
            await reminderSync.sync(preferences: prefs)
        } catch {
            // Keep last-known appearance and reminder schedule on refresh failure.
        }
    }

    @MainActor
    func makeSketchFlowViewModel(onPublishedToday: (() -> Void)? = nil) -> SketchFlowViewModel {
        SketchFlowViewModel(
            auth: auth,
            preferencesService: preferencesService,
            guestTimerStore: guestTimerPreferenceStore,
            activeSessionStore: activeSessionStore,
            sessionService: sketchSessionRepository,
            draftStore: draftStore,
            imageStore: draftImageStore,
            cameraAuthorizer: cameraAuthorizer,
            uploadService: uploadRepository,
            submissionService: submissionRepository,
            directUploader: directUploader,
            publishedStore: publishedSubmissionStore,
            analytics: analytics,
            onPublishedToday: onPublishedToday
        )
    }

    @MainActor
    static var live: AppDependencies {
        let environment = AppEnvironment.current
        let navigation = AppNavigationStore()
        let repository = MeRepository(baseURL: environment.apiBaseURL)
        let profileRepository = ProfileRepository(baseURL: environment.apiBaseURL)
        let promptRepository = PromptRepository(baseURL: environment.apiBaseURL)
        let sketchSessionRepository = SketchSessionRepository(baseURL: environment.apiBaseURL)
        let uploadRepository = UploadRepository(baseURL: environment.apiBaseURL)
        let submissionRepository = SubmissionRepository(baseURL: environment.apiBaseURL)
        let socialRepository = SocialRepository(baseURL: environment.apiBaseURL)
        let safetyRepository = SafetyRepository(baseURL: environment.apiBaseURL)
        let activeSessionStore = ActiveSessionStore()
        let guestTimerPreferenceStore = GuestTimerPreferenceStore()
        let draftStore = DraftStore()
        let draftImageStore = DraftImageStore()
        let publishedSubmissionStore = PublishedSubmissionStore()
        let cameraAuthorizer = SystemCameraAuthorizer()
        let projectID = environment.descopeProjectID

        if projectID == DescopeConfig.placeholderProjectID || projectID.isEmpty {
            let authService = MockAuthService()
            let auth = AuthSessionStore(
                authService: authService,
                meFetcher: repository,
                profileUpdater: repository
            )
            return AppDependencies(
                environment: environment,
                navigation: navigation,
                auth: auth,
                descopeAuthService: nil,
                preferencesService: repository,
                profileUpdater: repository,
                profileRepository: profileRepository,
                promptRepository: promptRepository,
                sketchSessionRepository: sketchSessionRepository,
                uploadRepository: uploadRepository,
                submissionRepository: submissionRepository,
                socialRepository: socialRepository,
                safetyRepository: safetyRepository,
                accountDeleter: repository,
                activeSessionStore: activeSessionStore,
                guestTimerPreferenceStore: guestTimerPreferenceStore,
                draftStore: draftStore,
                draftImageStore: draftImageStore,
                publishedSubmissionStore: publishedSubmissionStore,
                cameraAuthorizer: cameraAuthorizer
            )
        }

        let descope = DescopeAuthService(projectID: projectID)
        let auth = AuthSessionStore(
            authService: descope,
            meFetcher: repository,
            profileUpdater: repository
        )
        return AppDependencies(
            environment: environment,
            navigation: navigation,
            auth: auth,
            descopeAuthService: descope,
            preferencesService: repository,
            profileUpdater: repository,
            profileRepository: profileRepository,
            promptRepository: promptRepository,
            sketchSessionRepository: sketchSessionRepository,
            uploadRepository: uploadRepository,
            submissionRepository: submissionRepository,
            socialRepository: socialRepository,
            safetyRepository: safetyRepository,
            accountDeleter: repository,
            activeSessionStore: activeSessionStore,
            guestTimerPreferenceStore: guestTimerPreferenceStore,
            draftStore: draftStore,
            draftImageStore: draftImageStore,
            publishedSubmissionStore: publishedSubmissionStore,
            cameraAuthorizer: cameraAuthorizer
        )
    }
}
