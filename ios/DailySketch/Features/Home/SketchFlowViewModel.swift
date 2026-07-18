import Foundation
import Observation

@MainActor
@Observable
final class SketchFlowViewModel {
    var showsTimerSelection = false
    var showsActiveSession = false
    var showsRecoveryBanner = false
    var isCreatingSession = false
    var selectedTimerOption: TimerPreferenceOption?
    var rememberChoice = false
    var changeTimerHintVisible = false
    var syncBannerMessage: String?

    private(set) var sessionViewModel: SketchSessionViewModel?
    private(set) var recoverableSnapshot: ActiveSessionSnapshot?

    private let auth: AuthSessionStore
    private let preferencesService: any PreferencesServing
    private let guestTimerStore: any GuestTimerPreferenceStoring
    private let activeSessionStore: any ActiveSessionStoring
    private let sessionService: any SketchSessionServing
    private let dateProvider: any DateProviding
    private var cachedAuthenticatedPreference: TimerPreferenceOption?

    init(
        auth: AuthSessionStore,
        preferencesService: any PreferencesServing,
        guestTimerStore: any GuestTimerPreferenceStoring,
        activeSessionStore: any ActiveSessionStoring,
        sessionService: any SketchSessionServing,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.auth = auth
        self.preferencesService = preferencesService
        self.guestTimerStore = guestTimerStore
        self.activeSessionStore = activeSessionStore
        self.sessionService = sessionService
        self.dateProvider = dateProvider
    }

    func prepareOnAppear() {
        refreshRecoveryState()
        Task { await refreshRememberedPreference() }
    }

    func startSketch(prompt: DailyPromptModel) {
        Task {
            await refreshRememberedPreference()
            if let remembered = rememberedTimerOption() {
                changeTimerHintVisible = true
                await beginSession(prompt: prompt, option: remembered, remember: false)
            } else {
                selectedTimerOption = nil
                rememberChoice = false
                changeTimerHintVisible = false
                showsTimerSelection = true
            }
        }
    }

    func dismissTimerSelection() {
        showsTimerSelection = false
        selectedTimerOption = nil
        rememberChoice = false
    }

    func confirmTimerSelection(prompt: DailyPromptModel) {
        guard let selectedTimerOption else { return }
        showsTimerSelection = false
        Task {
            await beginSession(
                prompt: prompt,
                option: selectedTimerOption,
                remember: rememberChoice
            )
        }
    }

    func changeTimerNextTime() {
        // Clears remembered preference so the next Start Sketch shows the sheet.
        if auth.isAuthenticated {
            Task { await clearAuthenticatedRememberedTimer() }
        } else {
            guestTimerStore.clear()
        }
        changeTimerHintVisible = false
        cachedAuthenticatedPreference = nil
    }

    func resumeRecoverableSession(promptLookup: (UUID) -> DailyPromptModel?) {
        guard let snapshot = recoverableSnapshot else { return }
        guard let option = TimerPreferenceOption.from(
            mode: snapshot.timerMode,
            seconds: snapshot.selectedTimerSeconds
        ) else {
            discardRecoverableSession()
            return
        }

        let prompt = promptLookup(snapshot.promptId) ?? DailyPromptModel(
            id: snapshot.promptId,
            promptDate: dateProvider.now(),
            word1: snapshot.promptWords[safe: 0] ?? "",
            word2: snapshot.promptWords[safe: 1] ?? "",
            word3: snapshot.promptWords[safe: 2] ?? "",
            status: "published",
            publishedAt: nil
        )

        let model = makeSessionViewModel(
            prompt: prompt,
            option: option,
            localSessionId: snapshot.id,
            serverSessionId: snapshot.serverSessionId,
            startedAt: snapshot.startedAt,
            pausedAt: snapshot.pausedAt,
            pausedTotalSeconds: snapshot.pausedTotalSeconds,
            lifecycle: snapshot.lifecycle,
            syncPending: snapshot.syncPending,
            isGuest: snapshot.isGuest
        )
        sessionViewModel = model
        showsActiveSession = true
        showsRecoveryBanner = false
        model.startTicking()
    }

    func discardRecoverableSession() {
        if let snapshot = recoverableSnapshot,
           let serverId = snapshot.serverSessionId,
           let token = auth.accessToken {
            Task {
                _ = try? await sessionService.abandonSession(
                    accessToken: token,
                    sessionId: serverId
                )
            }
        }
        try? activeSessionStore.clear()
        recoverableSnapshot = nil
        showsRecoveryBanner = false
    }

    func handleSessionEnded() {
        showsActiveSession = false
        sessionViewModel?.stopTicking()
        sessionViewModel = nil
        refreshRecoveryState()
    }

    private func beginSession(
        prompt: DailyPromptModel,
        option: TimerPreferenceOption,
        remember: Bool
    ) async {
        if remember {
            await persistRemembered(option)
        }

        let localId = UUID()
        let isGuest = !auth.isAuthenticated
        isCreatingSession = true
        defer { isCreatingSession = false }

        let model = makeSessionViewModel(
            prompt: prompt,
            option: option,
            localSessionId: localId,
            serverSessionId: nil,
            startedAt: dateProvider.now(),
            pausedAt: nil,
            pausedTotalSeconds: 0,
            lifecycle: .active,
            syncPending: false,
            isGuest: isGuest
        )
        sessionViewModel = model
        showsActiveSession = true
        model.startTicking()

        guard !isGuest, let token = auth.accessToken else { return }

        do {
            let created = try await sessionService.createSession(
                accessToken: token,
                promptId: prompt.id,
                timerMode: option.mode,
                selectedTimerSeconds: option.seconds,
                clientTimezone: TimeZone.current.identifier,
                clientSessionId: localId.uuidString,
                idempotencyKey: localId.uuidString
            )
            model.attachServerSessionId(created.id)
            syncBannerMessage = nil
        } catch {
            // Continue locally and mark sync pending rather than blocking the session.
            model.markSyncPending(error.localizedDescription)
            syncBannerMessage = "Session sync pending. You can keep sketching."
        }
    }

    private func makeSessionViewModel(
        prompt: DailyPromptModel,
        option: TimerPreferenceOption,
        localSessionId: UUID,
        serverSessionId: UUID?,
        startedAt: Date,
        pausedAt: Date?,
        pausedTotalSeconds: Int,
        lifecycle: ActiveSessionLifecycle,
        syncPending: Bool,
        isGuest: Bool
    ) -> SketchSessionViewModel {
        SketchSessionViewModel(
            prompt: prompt,
            timerOption: option,
            localSessionId: localSessionId,
            serverSessionId: serverSessionId,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedTotalSeconds: pausedTotalSeconds,
            lifecycle: lifecycle,
            syncPending: syncPending,
            isGuest: isGuest,
            accessTokenProvider: { [weak self] in self?.auth.accessToken },
            sessionService: sessionService,
            activeSessionStore: activeSessionStore,
            dateProvider: dateProvider,
            onEnded: { [weak self] in
                self?.handleSessionEnded()
            }
        )
    }

    private func rememberedTimerOption() -> TimerPreferenceOption? {
        if auth.isAuthenticated {
            return cachedAuthenticatedPreference
        }
        return guestTimerStore.load()
    }

    private func refreshRememberedPreference() async {
        if auth.isAuthenticated, let token = auth.accessToken {
            do {
                let prefs = try await preferencesService.getPreferences(accessToken: token)
                if prefs.rememberTimerOption {
                    cachedAuthenticatedPreference = TimerPreferenceOption.from(
                        mode: prefs.rememberedTimerMode,
                        seconds: prefs.rememberedTimerSeconds
                    )
                } else {
                    cachedAuthenticatedPreference = nil
                }
            } catch {
                // Keep last known cached preference.
            }
        }
    }

    private func persistRemembered(_ option: TimerPreferenceOption) async {
        if auth.isAuthenticated, let token = auth.accessToken {
            var prefs = UserPreferencesModel.defaults
            do {
                prefs = try await preferencesService.getPreferences(accessToken: token)
            } catch {
                // Fall through with defaults and still attempt write.
            }
            prefs.rememberTimerOption = true
            prefs.rememberedTimerMode = option.mode
            prefs.rememberedTimerSeconds = option.seconds
            do {
                prefs = try await preferencesService.updatePreferences(
                    accessToken: token,
                    preferences: prefs
                )
                cachedAuthenticatedPreference = option
            } catch {
                syncBannerMessage = "Couldn’t save remembered timer."
            }
        } else {
            guestTimerStore.save(option)
        }
    }

    private func clearAuthenticatedRememberedTimer() async {
        guard let token = auth.accessToken else { return }
        do {
            var prefs = try await preferencesService.getPreferences(accessToken: token)
            prefs.rememberTimerOption = false
            prefs.rememberedTimerMode = nil
            prefs.rememberedTimerSeconds = nil
            _ = try await preferencesService.updatePreferences(
                accessToken: token,
                preferences: prefs
            )
            cachedAuthenticatedPreference = nil
        } catch {
            syncBannerMessage = "Couldn’t clear remembered timer."
        }
    }

    private func refreshRecoveryState() {
        guard let snapshot = try? activeSessionStore.load(), snapshot.isRecoverable else {
            recoverableSnapshot = nil
            showsRecoveryBanner = false
            return
        }
        recoverableSnapshot = snapshot
        showsRecoveryBanner = !showsActiveSession
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
