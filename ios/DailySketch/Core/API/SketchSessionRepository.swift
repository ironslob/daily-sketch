import Foundation
@preconcurrency import DailySketchAPI

struct SketchSessionModel: Equatable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let promptId: UUID
    let timerMode: String
    let selectedTimerSeconds: Int?
    let status: String
    let startedAt: Date
    let pausedTotalSeconds: Int
    let timerCompletedAt: Date?
    let finishRequestedAt: Date?
    let abandonedAt: Date?
}

enum SketchSessionAPIError: LocalizedError, Equatable {
    case sessionNotFound
    case invalidTimerSelection
    case invalidSessionTransition
    case idempotencyKeyConflict
    case promptNotFound
    case sessionExpired
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "The requested sketch session could not be found."
        case .invalidTimerSelection:
            return "Timer mode and selected seconds are inconsistent."
        case .invalidSessionTransition:
            return "That lifecycle event is not valid for the current session state."
        case .idempotencyKeyConflict:
            return "This idempotency key was already used with a different request."
        case .promptNotFound:
            return "The requested prompt could not be found."
        case .sessionExpired:
            return AuthServiceError.sessionExpired.localizedDescription
        case .underlying(let message):
            return message
        }
    }
}

protocol SketchSessionServing: Sendable {
    func createSession(
        accessToken: String,
        promptId: UUID,
        timerMode: String,
        selectedTimerSeconds: Int?,
        clientTimezone: String?,
        clientSessionId: String?,
        idempotencyKey: String
    ) async throws -> SketchSessionModel

    func postEvent(
        accessToken: String,
        sessionId: UUID,
        eventType: String,
        clientOccurredAt: Date?
    ) async throws -> SketchSessionModel

    func abandonSession(
        accessToken: String,
        sessionId: UUID
    ) async throws -> SketchSessionModel
}

struct SketchSessionRepository: SketchSessionServing {
    let baseURL: URL

    func createSession(
        accessToken: String,
        promptId: UUID,
        timerMode: String,
        selectedTimerSeconds: Int?,
        clientTimezone: String?,
        clientSessionId: String?,
        idempotencyKey: String
    ) async throws -> SketchSessionModel {
        configureClient(accessToken: accessToken)
        guard let mode = TimerMode(rawValue: timerMode) else {
            throw SketchSessionAPIError.invalidTimerSelection
        }
        do {
            let request = CreateSketchSessionRequest(
                promptId: promptId,
                timerMode: mode,
                selectedTimerSeconds: selectedTimerSeconds,
                clientTimezone: clientTimezone,
                clientSessionId: clientSessionId
            )
            let session = try await SketchSessionsAPI.createSketchSession(
                createSketchSessionRequest: request,
                idempotencyKey: idempotencyKey
            )
            return mapSession(session)
        } catch {
            throw mapAPIError(error)
        }
    }

    func postEvent(
        accessToken: String,
        sessionId: UUID,
        eventType: String,
        clientOccurredAt: Date?
    ) async throws -> SketchSessionModel {
        configureClient(accessToken: accessToken)
        guard let type = SketchSessionEventType(rawValue: eventType) else {
            throw SketchSessionAPIError.invalidSessionTransition
        }
        do {
            let request = SketchSessionEventRequest(
                eventType: type,
                clientOccurredAt: clientOccurredAt,
                metadata: nil
            )
            let session = try await SketchSessionsAPI.postSketchSessionEvent(
                sessionId: sessionId,
                sketchSessionEventRequest: request
            )
            return mapSession(session)
        } catch {
            throw mapAPIError(error)
        }
    }

    func abandonSession(
        accessToken: String,
        sessionId: UUID
    ) async throws -> SketchSessionModel {
        configureClient(accessToken: accessToken)
        do {
            let session = try await SketchSessionsAPI.abandonSketchSession(sessionId: sessionId)
            return mapSession(session)
        } catch {
            throw mapAPIError(error)
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

    private func mapSession(_ session: SketchSession) -> SketchSessionModel {
        SketchSessionModel(
            id: session.id,
            userId: session.userId,
            promptId: session.promptId,
            timerMode: session.timerMode.rawValue,
            selectedTimerSeconds: session.selectedTimerSeconds,
            status: session.status.rawValue,
            startedAt: session.startedAt,
            pausedTotalSeconds: session.pausedTotalSeconds,
            timerCompletedAt: session.timerCompletedAt,
            finishRequestedAt: session.finishRequestedAt,
            abandonedAt: session.abandonedAt
        )
    }

    private func mapAPIError(_ error: Error) -> Error {
        if let errorResponse = error as? ErrorResponse {
            switch errorResponse {
            case .error(let code, let data, _, _):
                if code == 401 {
                    return SketchSessionAPIError.sessionExpired
                }
                if let data,
                   let envelope = try? JSONDecoder().decode(SketchSessionAPIErrorEnvelope.self, from: data) {
                    switch envelope.error.code {
                    case "session_not_found":
                        return SketchSessionAPIError.sessionNotFound
                    case "invalid_timer_selection":
                        return SketchSessionAPIError.invalidTimerSelection
                    case "invalid_session_transition":
                        return SketchSessionAPIError.invalidSessionTransition
                    case "idempotency_key_conflict":
                        return SketchSessionAPIError.idempotencyKeyConflict
                    case "prompt_not_found":
                        return SketchSessionAPIError.promptNotFound
                    default:
                        return SketchSessionAPIError.underlying(envelope.error.message)
                    }
                }
            }
        }
        return SketchSessionAPIError.underlying(error.localizedDescription)
    }
}

private struct SketchSessionAPIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}

final class RecordingSketchSessionRepository: SketchSessionServing, @unchecked Sendable {
    private(set) var createCallCount = 0
    private(set) var eventCallCount = 0
    private(set) var abandonCallCount = 0
    private(set) var lastAccessToken: String?
    private(set) var lastEventType: String?
    var createError: Error?
    var eventError: Error?
    var abandonError: Error?
    var nextSession: SketchSessionModel?

    func createSession(
        accessToken: String,
        promptId: UUID,
        timerMode: String,
        selectedTimerSeconds: Int?,
        clientTimezone: String?,
        clientSessionId: String?,
        idempotencyKey: String
    ) async throws -> SketchSessionModel {
        createCallCount += 1
        lastAccessToken = accessToken
        if let createError {
            throw createError
        }
        if let nextSession {
            return nextSession
        }
        return SketchSessionModel(
            id: UUID(),
            userId: UUID(),
            promptId: promptId,
            timerMode: timerMode,
            selectedTimerSeconds: selectedTimerSeconds,
            status: "active",
            startedAt: Date(),
            pausedTotalSeconds: 0,
            timerCompletedAt: nil,
            finishRequestedAt: nil,
            abandonedAt: nil
        )
    }

    func postEvent(
        accessToken: String,
        sessionId: UUID,
        eventType: String,
        clientOccurredAt: Date?
    ) async throws -> SketchSessionModel {
        eventCallCount += 1
        lastAccessToken = accessToken
        lastEventType = eventType
        if let eventError {
            throw eventError
        }
        return SketchSessionModel(
            id: sessionId,
            userId: UUID(),
            promptId: UUID(),
            timerMode: "countdown",
            selectedTimerSeconds: 300,
            status: eventType == "paused" ? "paused" : "active",
            startedAt: Date(),
            pausedTotalSeconds: 0,
            timerCompletedAt: nil,
            finishRequestedAt: nil,
            abandonedAt: nil
        )
    }

    func abandonSession(
        accessToken: String,
        sessionId: UUID
    ) async throws -> SketchSessionModel {
        abandonCallCount += 1
        lastAccessToken = accessToken
        if let abandonError {
            throw abandonError
        }
        return SketchSessionModel(
            id: sessionId,
            userId: UUID(),
            promptId: UUID(),
            timerMode: "countdown",
            selectedTimerSeconds: 300,
            status: "abandoned",
            startedAt: Date(),
            pausedTotalSeconds: 0,
            timerCompletedAt: nil,
            finishRequestedAt: nil,
            abandonedAt: Date()
        )
    }
}
