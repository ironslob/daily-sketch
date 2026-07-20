import Foundation
import Observation

@Observable
@MainActor
final class ReportViewModel {
    enum Phase: Equatable {
        case pickingReason
        case confirming
        case success(message: String)
        case failed(String)
    }

    let targetType: ReportTargetKind
    let targetId: UUID
    let blockableUserId: UUID?
    private let safetyService: any SafetyServing
    private let accessTokenProvider: () -> String?

    var selectedReason: ReportReasonKind?
    var notes = ""
    var phase: Phase = .pickingReason
    var isSubmitting = false
    var offeredBlockAfterReport = false

    init(
        targetType: ReportTargetKind,
        targetId: UUID,
        blockableUserId: UUID? = nil,
        safetyService: any SafetyServing,
        accessTokenProvider: @escaping () -> String?
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.blockableUserId = blockableUserId
        self.safetyService = safetyService
        self.accessTokenProvider = accessTokenProvider
    }

    var title: String {
        switch targetType {
        case .submission: return "Report this sketch"
        case .reflection: return "Report this reflection"
        case .profile: return "Report this profile"
        }
    }

    var canSubmit: Bool {
        guard let selectedReason else { return false }
        if selectedReason == .other {
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func submit() async {
        guard canSubmit, let selectedReason else { return }
        guard let token = accessTokenProvider() else {
            phase = .failed("Sign in to report.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let notesValue = selectedReason == .other ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let confirmation = try await safetyService.createReport(
                accessToken: token,
                targetType: targetType,
                targetId: targetId,
                reason: selectedReason,
                notes: notesValue
            )
            offeredBlockAfterReport = blockableUserId != nil
            phase = .success(message: confirmation.message)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
