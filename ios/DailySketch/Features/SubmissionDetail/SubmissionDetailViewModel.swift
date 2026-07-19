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

    private(set) var state: State = .loading
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?

    private let submissionId: UUID
    private let submissionService: any SubmissionServing
    private let accessTokenProvider: () -> String?
    var onDeleted: (() -> Void)?

    init(
        submissionId: UUID,
        submissionService: any SubmissionServing,
        accessTokenProvider: @escaping () -> String?,
        onDeleted: (() -> Void)? = nil
    ) {
        self.submissionId = submissionId
        self.submissionService = submissionService
        self.accessTokenProvider = accessTokenProvider
        self.onDeleted = onDeleted
    }

    func load() async {
        state = .loading
        deleteErrorMessage = nil
        do {
            let submission = try await submissionService.getSubmission(
                accessToken: accessTokenProvider(),
                submissionId: submissionId
            )
            state = .loaded(submission)
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
}
