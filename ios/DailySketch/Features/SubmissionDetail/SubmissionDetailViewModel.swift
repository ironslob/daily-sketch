import Foundation
import Observation

@MainActor
@Observable
final class SubmissionDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(SubmissionModel)
        case failed(String)
        case deleted
    }

    enum ReflectionsState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum PendingSocialAction: Equatable {
        case like
        case postReflection
        case reportSubmission
        case blockAuthor
        case reportReflection(UUID)
    }

    static let reflectionMaxLength = 500

    private(set) var state: State = .loading
    private(set) var reflectionsState: ReflectionsState = .loading
    private(set) var reflections: [ReflectionModel] = []
    private(set) var reflectionsNextCursor: String?
    private(set) var isLoadingMoreReflections = false
    private(set) var isDeleting = false
    private(set) var isLikeInFlight = false
    private(set) var isPostingReflection = false
    private(set) var deleteErrorMessage: String?
    private(set) var likeErrorMessage: String?
    private(set) var reflectionErrorMessage: String?
    private(set) var pendingSocialAction: PendingSocialAction?
    var composerText = ""
    var showsAuthSheet = false
    var authSheetMode: AuthenticationView.Mode = .signUp

    private let submissionId: UUID
    private let submissionService: any SubmissionServing
    private let socialService: any SocialServing
    private let safetyService: any SafetyServing
    private let isAuthenticated: () -> Bool
    private let accessTokenProvider: () -> String?
    var onDeleted: (() -> Void)?
    var onLikeChanged: ((UUID, Bool, Int) -> Void)?
    var onBlockedUser: ((UUID) -> Void)?
    private(set) var blockErrorMessage: String?
    private(set) var didBlockAuthor = false

    init(
        submissionId: UUID,
        submissionService: any SubmissionServing,
        socialService: any SocialServing,
        safetyService: any SafetyServing = RecordingSafetyRepository(),
        isAuthenticated: @escaping () -> Bool = { false },
        accessTokenProvider: @escaping () -> String?,
        onDeleted: (() -> Void)? = nil,
        onLikeChanged: ((UUID, Bool, Int) -> Void)? = nil,
        onBlockedUser: ((UUID) -> Void)? = nil
    ) {
        self.submissionId = submissionId
        self.submissionService = submissionService
        self.socialService = socialService
        self.safetyService = safetyService
        self.isAuthenticated = isAuthenticated
        self.accessTokenProvider = accessTokenProvider
        self.onDeleted = onDeleted
        self.onLikeChanged = onLikeChanged
        self.onBlockedUser = onBlockedUser
    }

    func load() async {
        state = .loading
        deleteErrorMessage = nil
        likeErrorMessage = nil
        do {
            let submission = try await submissionService.getSubmission(
                accessToken: accessTokenProvider(),
                submissionId: submissionId
            )
            state = .loaded(submission)
            await loadReflections(reset: true)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var navigationTitle: String {
        guard case .loaded(let submission) = state else { return "Sketch" }
        if let caption = submission.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            let limit = 28
            if caption.count <= limit {
                return caption
            }
            return String(caption.prefix(limit - 1)) + "…"
        }
        return "Sketch"
    }

    var timerLabel: String {
        guard case .loaded(let submission) = state else { return "" }
        if submission.timerMode == "no_timer" {
            return "No timer"
        }
        if let seconds = submission.timerSeconds {
            let minutes = seconds / 60
            return minutes == 1 ? "1 min" : "\(minutes) min"
        }
        return "Timer"
    }

    var promptDateLabel: String {
        guard case .loaded(let submission) = state else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: submission.promptDate)
    }

    var isOwner: Bool {
        if case .loaded(let submission) = state {
            return submission.isOwner
        }
        return false
    }

    var canPostReflection: Bool {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= Self.reflectionMaxLength
            && !isPostingReflection
    }

    var remainingReflectionCharacters: Int {
        Self.reflectionMaxLength - composerText.count
    }

    func deleteSubmission() async {
        guard case .loaded = state else { return }
        guard let token = accessTokenProvider() else {
            deleteErrorMessage = "Sign in to delete this sketch."
            return
        }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }
        do {
            try await submissionService.deleteSubmission(
                accessToken: token,
                submissionId: submissionId
            )
            state = .deleted
            onDeleted?()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    func toggleLike() async {
        guard case .loaded(let submission) = state else { return }
        guard isAuthenticated(), let token = accessTokenProvider() else {
            pendingSocialAction = .like
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        guard !isLikeInFlight else { return }

        let previous = submission
        let nextLiked = !submission.viewerHasLiked
        let nextCount = max(0, submission.likeCount + (nextLiked ? 1 : -1))
        let optimistic = submission.withLikeState(liked: nextLiked, likeCount: nextCount)
        state = .loaded(optimistic)
        onLikeChanged?(submissionId, nextLiked, nextCount)
        likeErrorMessage = nil
        isLikeInFlight = true
        defer { isLikeInFlight = false }

        do {
            let result: LikeStateModel
            if nextLiked {
                result = try await socialService.likeSubmission(
                    accessToken: token,
                    submissionId: submissionId
                )
            } else {
                result = try await socialService.unlikeSubmission(
                    accessToken: token,
                    submissionId: submissionId
                )
            }
            if case .loaded(let current) = state {
                let confirmed = current.withLikeState(liked: result.liked, likeCount: result.likeCount)
                state = .loaded(confirmed)
                onLikeChanged?(submissionId, result.liked, result.likeCount)
            }
        } catch {
            state = .loaded(previous)
            onLikeChanged?(submissionId, previous.viewerHasLiked, previous.likeCount)
            likeErrorMessage = error.localizedDescription
        }
    }

    func loadReflections(reset: Bool) async {
        if reset {
            reflectionsState = .loading
            isLoadingMoreReflections = false
        } else {
            guard reflectionsNextCursor != nil, !isLoadingMoreReflections else { return }
            isLoadingMoreReflections = true
        }

        let cursor = reset ? nil : reflectionsNextCursor
        do {
            let page = try await socialService.listReflections(
                accessToken: accessTokenProvider(),
                submissionId: submissionId,
                cursor: cursor,
                limit: 20
            )
            if reset {
                reflections = page.items
            } else {
                let existing = Set(reflections.map(\.id))
                reflections.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            reflectionsNextCursor = page.nextCursor
            reflectionsState = .loaded
        } catch {
            if reset && reflections.isEmpty {
                reflectionsState = .failed(error.localizedDescription)
            }
        }
        isLoadingMoreReflections = false
    }

    func loadMoreReflectionsIfNeeded(currentItem item: ReflectionModel) async {
        guard reflectionsNextCursor != nil, !isLoadingMoreReflections else { return }
        guard let index = reflections.firstIndex(where: { $0.id == item.id }) else { return }
        let threshold = max(reflections.count - 4, 0)
        guard index >= threshold else { return }
        await loadReflections(reset: false)
    }

    func postReflection() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= Self.reflectionMaxLength else {
            reflectionErrorMessage = "Reflections can be at most \(Self.reflectionMaxLength) characters."
            return
        }
        guard isAuthenticated(), let token = accessTokenProvider() else {
            pendingSocialAction = .postReflection
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        guard !isPostingReflection else { return }

        isPostingReflection = true
        reflectionErrorMessage = nil
        defer { isPostingReflection = false }

        do {
            let created = try await socialService.createReflection(
                accessToken: token,
                submissionId: submissionId,
                body: trimmed,
                idempotencyKey: UUID().uuidString
            )
            reflections.append(created)
            reflectionsState = .loaded
            composerText = ""
            if case .loaded(let submission) = state {
                state = .loaded(submission.withReflectionCount(submission.reflectionCount + 1))
            }
        } catch {
            reflectionErrorMessage = error.localizedDescription
        }
    }

    func deleteReflection(_ reflection: ReflectionModel) async {
        guard reflection.isAuthor else { return }
        guard let token = accessTokenProvider() else {
            reflectionErrorMessage = "Sign in to delete this reflection."
            return
        }
        do {
            try await socialService.deleteReflection(
                accessToken: token,
                reflectionId: reflection.id
            )
            reflections.removeAll { $0.id == reflection.id }
            if case .loaded(let submission) = state {
                state = .loaded(
                    submission.withReflectionCount(max(0, submission.reflectionCount - 1))
                )
            }
        } catch {
            reflectionErrorMessage = error.localizedDescription
        }
    }

    func clearLikeError() {
        likeErrorMessage = nil
    }

    func clearBlockError() {
        blockErrorMessage = nil
    }

    func presentSignIn() {
        authSheetMode = .signIn
        showsAuthSheet = true
    }

    func presentCreateAccount() {
        authSheetMode = .signUp
        showsAuthSheet = true
    }

    func requestReportSubmission() {
        guard isAuthenticated() else {
            pendingSocialAction = .reportSubmission
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
    }

    func requestBlockAuthor() {
        guard isAuthenticated() else {
            pendingSocialAction = .blockAuthor
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
    }

    func requestReportReflection(_ reflectionId: UUID) {
        guard isAuthenticated() else {
            pendingSocialAction = .reportReflection(reflectionId)
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
    }

    func blockAuthor(userId: UUID) async {
        guard let token = accessTokenProvider() else {
            pendingSocialAction = .blockAuthor
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        blockErrorMessage = nil
        do {
            _ = try await safetyService.blockUser(accessToken: token, userId: userId)
            didBlockAuthor = true
            onBlockedUser?(userId)
            state = .deleted
        } catch {
            blockErrorMessage = error.localizedDescription
        }
    }

    func handleAuthenticationCompleted() async {
        showsAuthSheet = false
        guard let pending = pendingSocialAction else { return }
        switch pending {
        case .like:
            pendingSocialAction = nil
            await toggleLike()
        case .postReflection:
            pendingSocialAction = nil
            await postReflection()
        case .reportSubmission, .blockAuthor, .reportReflection:
            // View presents report/block UI once authenticated.
            break
        }
    }

    func consumePendingSafetyAction() -> PendingSocialAction? {
        guard let pending = pendingSocialAction else { return nil }
        switch pending {
        case .reportSubmission, .blockAuthor, .reportReflection:
            pendingSocialAction = nil
            return pending
        case .like, .postReflection:
            return nil
        }
    }
}
