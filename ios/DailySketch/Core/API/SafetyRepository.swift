import Foundation
@preconcurrency import DailySketchAPI

enum ReportTargetKind: String, Equatable, Sendable, CaseIterable {
    case submission
    case reflection
    case profile
}

enum ReportReasonKind: String, Equatable, Sendable, CaseIterable, Identifiable {
    case inappropriate
    case harassment
    case hate
    case spam
    case intellectualProperty = "intellectual_property"
    case selfHarm = "self_harm"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriate: return "Inappropriate content"
        case .harassment: return "Harassment or abuse"
        case .hate: return "Hate or hateful conduct"
        case .spam: return "Spam"
        case .intellectualProperty: return "Intellectual-property concern"
        case .selfHarm: return "Self-harm concern"
        case .other: return "Other"
        }
    }
}

struct ReportConfirmation: Equatable, Sendable {
    let id: UUID
    let message: String
}

struct BlockStateModel: Equatable, Sendable {
    let blocked: Bool
    let userId: UUID
}

struct BlockedUserModel: Equatable, Sendable, Identifiable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarURL: URL?
}

enum SafetyAPIError: LocalizedError, Equatable {
    case sessionExpired
    case cannotBlockSelf
    case targetNotFound
    case validationError(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Your session expired. Sign in again."
        case .cannotBlockSelf:
            return "You cannot block yourself."
        case .targetNotFound:
            return "That content could not be found."
        case .validationError(let message):
            return message
        case .underlying(let message):
            return message
        }
    }
}

protocol SafetyServing: Sendable {
    func createReport(
        accessToken: String,
        targetType: ReportTargetKind,
        targetId: UUID,
        reason: ReportReasonKind,
        notes: String?
    ) async throws -> ReportConfirmation

    func listBlockedUsers(accessToken: String) async throws -> [BlockedUserModel]

    func blockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel

    func unblockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel
}

struct SafetyRepository: SafetyServing {
    let baseURL: URL

    func createReport(
        accessToken: String,
        targetType: ReportTargetKind,
        targetId: UUID,
        reason: ReportReasonKind,
        notes: String?
    ) async throws -> ReportConfirmation {
        configureClient(accessToken: accessToken)
        do {
            let request = CreateReportRequest(
                targetType: ReportTargetType(rawValue: targetType.rawValue) ?? .submission,
                targetId: targetId,
                reason: ReportReason(rawValue: reason.rawValue) ?? .other,
                notes: notes
            )
            let response = try await ReportsAPI.createReport(createReportRequest: request)
            return ReportConfirmation(id: response.id, message: response.message)
        } catch {
            throw mapSafetyAPIError(error)
        }
    }

    func listBlockedUsers(accessToken: String) async throws -> [BlockedUserModel] {
        configureClient(accessToken: accessToken)
        do {
            let response = try await MeAPI.listMyBlockedUsers()
            return response.items.map {
                BlockedUserModel(
                    id: $0.userId,
                    username: $0.username,
                    displayName: $0.displayName,
                    avatarURL: $0.avatarUrl.flatMap(URL.init(string:))
                )
            }
        } catch {
            throw mapSafetyAPIError(error)
        }
    }

    func blockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel {
        configureClient(accessToken: accessToken)
        do {
            let state = try await UsersAPI.blockUser(userId: userId)
            return BlockStateModel(blocked: state.blocked, userId: state.userId)
        } catch {
            throw mapSafetyAPIError(error)
        }
    }

    func unblockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel {
        configureClient(accessToken: accessToken)
        do {
            let state = try await UsersAPI.unblockUser(userId: userId)
            return BlockStateModel(blocked: state.blocked, userId: state.userId)
        } catch {
            throw mapSafetyAPIError(error)
        }
    }

    private func configureClient(accessToken: String) {
        var base = baseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        DailySketchAPIAPI.basePath = base
        DailySketchAPIAPI.customHeaders["Authorization"] = "Bearer \(accessToken)"
        DailySketchAPITokenBridge.setBearerToken(accessToken)
    }
}

func mapSafetyAPIError(_ error: Error) -> Error {
    if let errorResponse = error as? ErrorResponse {
        switch errorResponse {
        case .error(let code, let data, _, _):
            if code == 401 {
                return SafetyAPIError.sessionExpired
            }
            if let data,
               let envelope = try? JSONDecoder().decode(SafetyAPIErrorEnvelope.self, from: data) {
                switch envelope.error.code {
                case "cannot_block_self":
                    return SafetyAPIError.cannotBlockSelf
                case "report_target_not_found", "user_not_found", "submission_not_found":
                    return SafetyAPIError.targetNotFound
                case "report_invalid", "validation_error":
                    return SafetyAPIError.validationError(envelope.error.message)
                default:
                    return SafetyAPIError.underlying(envelope.error.message)
                }
            }
        }
    }
    return SafetyAPIError.underlying(error.localizedDescription)
}

private struct SafetyAPIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}

final class RecordingSafetyRepository: SafetyServing, AccountDeleting, @unchecked Sendable {
    private(set) var reportCallCount = 0
    private(set) var blockCallCount = 0
    private(set) var unblockCallCount = 0
    private(set) var deleteAccountCallCount = 0
    private(set) var lastBlockedUserId: UUID?
    private(set) var lastReportTargetId: UUID?

    var blockedUsers: [BlockedUserModel] = []
    var reportError: Error?
    var blockError: Error?
    var deleteError: Error?

    func createReport(
        accessToken: String,
        targetType: ReportTargetKind,
        targetId: UUID,
        reason: ReportReasonKind,
        notes: String?
    ) async throws -> ReportConfirmation {
        reportCallCount += 1
        lastReportTargetId = targetId
        if let reportError { throw reportError }
        return ReportConfirmation(id: UUID(), message: "Thank you. Your report has been received.")
    }

    func listBlockedUsers(accessToken: String) async throws -> [BlockedUserModel] {
        blockedUsers
    }

    func blockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel {
        blockCallCount += 1
        lastBlockedUserId = userId
        if let blockError { throw blockError }
        return BlockStateModel(blocked: true, userId: userId)
    }

    func unblockUser(accessToken: String, userId: UUID) async throws -> BlockStateModel {
        unblockCallCount += 1
        lastBlockedUserId = userId
        return BlockStateModel(blocked: false, userId: userId)
    }

    func deleteAccount(accessToken: String, idempotencyKey: String?) async throws {
        deleteAccountCallCount += 1
        if let deleteError { throw deleteError }
    }
}
