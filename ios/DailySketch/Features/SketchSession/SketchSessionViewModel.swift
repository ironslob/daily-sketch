import Foundation
import Observation

enum SketchSessionPhase: Equatable {
    case running
    case paused
    case timerCompleted
    case readyForPhoto
    case abandoned
}

@MainActor
@Observable
final class SketchSessionViewModel {
    private(set) var phase: SketchSessionPhase
    private(set) var displayedCountdownSeconds: Int
    private(set) var displayedElapsedSeconds: Int
    private(set) var syncPending = false
    private(set) var syncErrorMessage: String?
    private(set) var showsCancelConfirmation = false
    private(set) var showsPhotoPlaceholder = false

    let promptId: UUID
    let promptWords: [String]
    let promptAccessibilityLabel: String
    let timerOption: TimerPreferenceOption
    let localSessionId: UUID

    private var serverSessionId: UUID?
    private var startedAt: Date
    private var pausedAt: Date?
    private var pausedTotalSeconds: Int
    private let isGuest: Bool
    private var tickTask: Task<Void, Never>?
    private var didEmitTimerCompleted = false

    private let accessTokenProvider: () -> String?
    private let sessionService: any SketchSessionServing
    private let activeSessionStore: any ActiveSessionStoring
    private let dateProvider: any DateProviding
    private let onEnded: () -> Void

    init(
        prompt: DailyPromptModel,
        timerOption: TimerPreferenceOption,
        localSessionId: UUID = UUID(),
        serverSessionId: UUID? = nil,
        startedAt: Date? = nil,
        pausedAt: Date? = nil,
        pausedTotalSeconds: Int = 0,
        lifecycle: ActiveSessionLifecycle = .active,
        syncPending: Bool = false,
        isGuest: Bool,
        accessTokenProvider: @escaping () -> String?,
        sessionService: any SketchSessionServing,
        activeSessionStore: any ActiveSessionStoring,
        dateProvider: any DateProviding = SystemDateProvider(),
        onEnded: @escaping () -> Void
    ) {
        self.promptId = prompt.id
        self.promptWords = prompt.words
        self.promptAccessibilityLabel = prompt.accessibilityLabel
        self.timerOption = timerOption
        self.localSessionId = localSessionId
        self.serverSessionId = serverSessionId
        let now = dateProvider.now()
        self.startedAt = startedAt ?? now
        self.pausedAt = pausedAt
        self.pausedTotalSeconds = pausedTotalSeconds
        self.isGuest = isGuest
        self.syncPending = syncPending
        self.accessTokenProvider = accessTokenProvider
        self.sessionService = sessionService
        self.activeSessionStore = activeSessionStore
        self.dateProvider = dateProvider
        self.onEnded = onEnded

        switch lifecycle {
        case .active:
            self.phase = .running
        case .paused:
            self.phase = .paused
        case .timerCompleted:
            self.phase = .timerCompleted
            self.didEmitTimerCompleted = true
        case .readyForPhoto:
            self.phase = .readyForPhoto
        case .abandoned:
            self.phase = .abandoned
        }

        self.displayedCountdownSeconds = timerOption.seconds ?? 0
        self.displayedElapsedSeconds = 0
        refreshDisplayedTime()
    }

    var isCountdown: Bool {
        timerOption != .noTimer
    }

    var canPause: Bool {
        phase == .running && isCountdown
    }

    var canResume: Bool {
        phase == .paused
    }

    var formattedCountdown: String {
        Self.formatClock(displayedCountdownSeconds)
    }

    var formattedElapsed: String {
        Self.formatClock(displayedElapsedSeconds)
    }

    func startTicking() {
        refreshDisplayedTime()
        persistSnapshot()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.refreshDisplayedTime()
            }
        }
    }

    func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    func pause() {
        guard canPause else { return }
        phase = .paused
        pausedAt = dateProvider.now()
        refreshDisplayedTime()
        persistSnapshot()
        Task { await postEvent("paused") }
    }

    func resume() {
        guard canResume, let pausedAt else { return }
        let delta = max(0, Int(dateProvider.now().timeIntervalSince(pausedAt)))
        pausedTotalSeconds += delta
        self.pausedAt = nil
        phase = .running
        refreshDisplayedTime()
        persistSnapshot()
        Task { await postEvent("resumed") }
    }

    func finish() {
        guard phase == .running || phase == .paused || phase == .timerCompleted else { return }
        if phase == .paused, let pausedAt {
            let delta = max(0, Int(dateProvider.now().timeIntervalSince(pausedAt)))
            pausedTotalSeconds += delta
            self.pausedAt = nil
        }
        phase = .readyForPhoto
        showsPhotoPlaceholder = true
        persistSnapshot()
        Task { await postEvent("finished_early") }
    }

    func requestCancel() {
        showsCancelConfirmation = true
    }

    func dismissCancelConfirmation() {
        showsCancelConfirmation = false
    }

    func confirmCancel() {
        showsCancelConfirmation = false
        phase = .abandoned
        stopTicking()
        Task {
            await abandonRemote()
            try? activeSessionStore.clear()
            onEnded()
        }
    }

    func keepSketchingAfterTimer() {
        guard phase == .timerCompleted else { return }
        phase = .readyForPhoto
        showsPhotoPlaceholder = false
        persistSnapshot()
    }

    func takePhotoPlaceholder() {
        showsPhotoPlaceholder = true
        phase = .readyForPhoto
        persistSnapshot()
    }

    func dismissPhotoPlaceholder() {
        showsPhotoPlaceholder = false
        stopTicking()
        onEnded()
    }

    func attachServerSessionId(_ id: UUID) {
        serverSessionId = id
        syncPending = false
        syncErrorMessage = nil
        persistSnapshot()
    }

    func markSyncPending(_ message: String?) {
        syncPending = true
        syncErrorMessage = message
        persistSnapshot()
    }

    private func refreshDisplayedTime() {
        let now = dateProvider.now()
        let pausedExtra: TimeInterval
        if phase == .paused, let pausedAt {
            pausedExtra = now.timeIntervalSince(pausedAt)
        } else {
            pausedExtra = 0
        }
        let elapsed = max(
            0,
            Int(now.timeIntervalSince(startedAt) - TimeInterval(pausedTotalSeconds) - pausedExtra)
        )
        displayedElapsedSeconds = elapsed

        guard isCountdown, let total = timerOption.seconds else { return }
        let remaining = max(0, total - elapsed)
        displayedCountdownSeconds = remaining

        if phase == .running, remaining == 0, !didEmitTimerCompleted {
            didEmitTimerCompleted = true
            phase = .timerCompleted
            persistSnapshot()
            Task { await postEvent("timer_completed") }
        }
    }

    private func persistSnapshot() {
        let lifecycle: ActiveSessionLifecycle
        switch phase {
        case .running:
            lifecycle = .active
        case .paused:
            lifecycle = .paused
        case .timerCompleted:
            lifecycle = .timerCompleted
        case .readyForPhoto:
            lifecycle = .readyForPhoto
        case .abandoned:
            lifecycle = .abandoned
        }

        let snapshot = ActiveSessionSnapshot(
            id: localSessionId,
            serverSessionId: serverSessionId,
            promptId: promptId,
            promptWords: promptWords,
            promptAccessibilityLabel: promptAccessibilityLabel,
            timerMode: timerOption.mode,
            selectedTimerSeconds: timerOption.seconds,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedTotalSeconds: pausedTotalSeconds,
            lifecycle: lifecycle,
            syncPending: syncPending,
            isGuest: isGuest
        )
        try? activeSessionStore.save(snapshot)
    }

    private func postEvent(_ eventType: String) async {
        guard let serverSessionId, let token = accessTokenProvider() else { return }
        do {
            _ = try await sessionService.postEvent(
                accessToken: token,
                sessionId: serverSessionId,
                eventType: eventType,
                clientOccurredAt: dateProvider.now()
            )
        } catch {
            markSyncPending(error.localizedDescription)
        }
    }

    private func abandonRemote() async {
        guard let serverSessionId, let token = accessTokenProvider() else { return }
        do {
            _ = try await sessionService.abandonSession(
                accessToken: token,
                sessionId: serverSessionId
            )
        } catch {
            markSyncPending(error.localizedDescription)
        }
    }

    static func formatClock(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
