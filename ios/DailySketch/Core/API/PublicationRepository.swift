import Foundation
@preconcurrency import DailySketchAPI

struct UploadSlotModel: Equatable, Sendable, Identifiable {
    let id: UUID
    let status: String
    let contentType: String
    let signedUploadURL: URL?
    let signedUploadMethod: String?
    let signedUploadHeaders: [String: String]
    let maxBytes: Int?
}

struct SubmissionModel: Equatable, Sendable, Identifiable {
    let id: UUID
    let caption: String?
    let status: String
    let timerMode: String
    let timerSeconds: Int?
    let likeCount: Int
    let reflectionCount: Int
    let viewerHasLiked: Bool
    let isOwner: Bool
    let imageURL: URL
    let thumbnailURL: URL
    let userId: UUID
    let username: String
    let displayName: String
    let promptWords: [String]
    let promptDate: Date
    let sketchSessionId: UUID
    let publishedAt: Date

    func withLikeState(liked: Bool, likeCount: Int) -> SubmissionModel {
        SubmissionModel(
            id: id,
            caption: caption,
            status: status,
            timerMode: timerMode,
            timerSeconds: timerSeconds,
            likeCount: likeCount,
            reflectionCount: reflectionCount,
            viewerHasLiked: liked,
            isOwner: isOwner,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            userId: userId,
            username: username,
            displayName: displayName,
            promptWords: promptWords,
            promptDate: promptDate,
            sketchSessionId: sketchSessionId,
            publishedAt: publishedAt
        )
    }

    func withReflectionCount(_ count: Int) -> SubmissionModel {
        SubmissionModel(
            id: id,
            caption: caption,
            status: status,
            timerMode: timerMode,
            timerSeconds: timerSeconds,
            likeCount: likeCount,
            reflectionCount: count,
            viewerHasLiked: viewerHasLiked,
            isOwner: isOwner,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            userId: userId,
            username: username,
            displayName: displayName,
            promptWords: promptWords,
            promptDate: promptDate,
            sketchSessionId: sketchSessionId,
            publishedAt: publishedAt
        )
    }
}

enum PublicationAPIError: LocalizedError, Equatable {
    case profileIncomplete
    case uploadNotFound
    case uploadNotReady
    case uploadAlreadyConsumed
    case sessionAlreadySubmitted
    case sessionNotFound
    case submissionNotFound
    case unsupportedMediaType
    case imageTooLarge
    case objectMissing
    case invalidImage
    case idempotencyKeyConflict
    case sessionExpired
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .profileIncomplete:
            return "Complete your profile before publishing."
        case .uploadNotFound:
            return "The requested upload could not be found."
        case .uploadNotReady:
            return "This upload is not ready to publish yet."
        case .uploadAlreadyConsumed:
            return "This upload has already been used."
        case .sessionAlreadySubmitted:
            return "This sketch session already has a published submission."
        case .sessionNotFound:
            return "The requested sketch session could not be found."
        case .submissionNotFound:
            return "The requested sketch could not be found."
        case .unsupportedMediaType:
            return "That image type is not supported."
        case .imageTooLarge:
            return "That image is too large to upload."
        case .objectMissing:
            return "The uploaded image could not be found. Please try again."
        case .invalidImage:
            return "The uploaded file is not a valid image."
        case .idempotencyKeyConflict:
            return "This idempotency key was already used with a different request."
        case .sessionExpired:
            return AuthServiceError.sessionExpired.localizedDescription
        case .underlying(let message):
            return message
        }
    }
}

enum AppUploadPurpose: String, Sendable {
    case submission
    case avatar
}

protocol UploadServing: Sendable {
    func createUpload(
        accessToken: String,
        contentType: String,
        byteSize: Int,
        purpose: AppUploadPurpose,
        idempotencyKey: String?
    ) async throws -> UploadSlotModel

    func completeUpload(
        accessToken: String,
        uploadId: UUID
    ) async throws -> UploadSlotModel
}

protocol SubmissionServing: Sendable {
    func createSubmission(
        accessToken: String,
        sketchSessionId: UUID,
        uploadId: UUID,
        caption: String?,
        idempotencyKey: String?
    ) async throws -> SubmissionModel

    func getSubmission(
        accessToken: String?,
        submissionId: UUID
    ) async throws -> SubmissionModel

    func deleteSubmission(
        accessToken: String,
        submissionId: UUID
    ) async throws
}

protocol DirectUploadTransporting: Sendable {
    func upload(
        data: Data,
        to url: URL,
        method: String,
        headers: [String: String],
        progress: (@Sendable (Double) -> Void)?
    ) async throws
}

struct URLSessionDirectUploader: DirectUploadTransporting {
    func upload(
        data: Data,
        to url: URL,
        method: String,
        headers: [String: String],
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        progress?(0)
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PublicationAPIError.underlying("Upload to storage failed.")
        }
        progress?(1)
    }
}

struct UploadRepository: UploadServing {
    let baseURL: URL

    func createUpload(
        accessToken: String,
        contentType: String,
        byteSize: Int,
        purpose: AppUploadPurpose,
        idempotencyKey: String?
    ) async throws -> UploadSlotModel {
        configureClient(accessToken: accessToken)
        do {
            let apiPurpose: UploadPurpose = purpose == .avatar ? .avatar : .submission
            let request = CreateUploadRequest(
                purpose: apiPurpose,
                contentType: contentType,
                byteSize: byteSize
            )
            let upload = try await UploadsAPI.createUpload(
                createUploadRequest: request,
                idempotencyKey: idempotencyKey
            )
            return mapUpload(upload)
        } catch {
            throw mapAPIError(error)
        }
    }

    func completeUpload(
        accessToken: String,
        uploadId: UUID
    ) async throws -> UploadSlotModel {
        configureClient(accessToken: accessToken)
        do {
            let upload = try await UploadsAPI.completeUpload(uploadId: uploadId)
            return mapUpload(upload)
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

    private func mapUpload(_ upload: Upload) -> UploadSlotModel {
        UploadSlotModel(
            id: upload.id,
            status: upload.status.rawValue,
            contentType: upload.contentType,
            signedUploadURL: upload.signedUpload.flatMap { URL(string: $0.url) },
            signedUploadMethod: upload.signedUpload?.method.rawValue,
            signedUploadHeaders: upload.signedUpload?.headers ?? [:],
            maxBytes: upload.signedUpload?.maxBytes
        )
    }
}

struct SubmissionRepository: SubmissionServing {
    let baseURL: URL

    func createSubmission(
        accessToken: String,
        sketchSessionId: UUID,
        uploadId: UUID,
        caption: String?,
        idempotencyKey: String?
    ) async throws -> SubmissionModel {
        configureClient(accessToken: accessToken)
        do {
            let request = CreateSubmissionRequest(
                sketchSessionId: sketchSessionId,
                uploadId: uploadId,
                caption: caption
            )
            let submission = try await SubmissionsAPI.createSubmission(
                createSubmissionRequest: request,
                idempotencyKey: idempotencyKey
            )
            return mapSubmission(submission)
        } catch {
            throw mapAPIError(error)
        }
    }

    func getSubmission(
        accessToken: String?,
        submissionId: UUID
    ) async throws -> SubmissionModel {
        configureClient(accessToken: accessToken)
        do {
            let submission = try await SubmissionsAPI.getSubmission(submissionId: submissionId)
            return mapSubmission(submission)
        } catch {
            throw mapAPIError(error)
        }
    }

    func deleteSubmission(
        accessToken: String,
        submissionId: UUID
    ) async throws {
        configureClient(accessToken: accessToken)
        do {
            try await SubmissionsAPI.deleteSubmission(submissionId: submissionId)
        } catch {
            throw mapAPIError(error)
        }
    }

    private func configureClient(accessToken: String?) {
        var base = baseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        DailySketchAPIAPI.basePath = base
        if let accessToken {
            DailySketchAPIAPI.customHeaders["Authorization"] = "Bearer \(accessToken)"
            DailySketchAPITokenBridge.setBearerToken(accessToken)
        } else {
            DailySketchAPIAPI.customHeaders.removeValue(forKey: "Authorization")
        }
    }

    private func mapSubmission(_ submission: Submission) -> SubmissionModel {
        SubmissionModel(
            id: submission.id,
            caption: submission.caption,
            status: submission.status.rawValue,
            timerMode: submission.timerMode.rawValue,
            timerSeconds: submission.timerSeconds,
            likeCount: submission.likeCount,
            reflectionCount: submission.reflectionCount,
            viewerHasLiked: submission.viewerHasLiked,
            isOwner: submission.isOwner,
            imageURL: URL(string: submission.imageUrl) ?? URL(string: "about:blank")!,
            thumbnailURL: URL(string: submission.thumbnailUrl) ?? URL(string: "about:blank")!,
            userId: submission.user.id,
            username: submission.user.username,
            displayName: submission.user.displayName,
            promptWords: [
                submission.prompt.word1,
                submission.prompt.word2,
                submission.prompt.word3,
            ],
            promptDate: submission.prompt.promptDate,
            sketchSessionId: submission.sketchSessionId,
            publishedAt: submission.publishedAt
        )
    }
}

func mapAPIError(_ error: Error) -> Error {
    if let errorResponse = error as? ErrorResponse {
        switch errorResponse {
        case .error(let code, let data, _, _):
            if code == 401 {
                return PublicationAPIError.sessionExpired
            }
            if let data,
               let envelope = try? JSONDecoder().decode(PublicationAPIErrorEnvelope.self, from: data) {
                switch envelope.error.code {
                case "profile_incomplete":
                    return PublicationAPIError.profileIncomplete
                case "upload_not_found":
                    return PublicationAPIError.uploadNotFound
                case "upload_not_ready":
                    return PublicationAPIError.uploadNotReady
                case "upload_already_consumed":
                    return PublicationAPIError.uploadAlreadyConsumed
                case "session_already_submitted":
                    return PublicationAPIError.sessionAlreadySubmitted
                case "session_not_found":
                    return PublicationAPIError.sessionNotFound
                case "submission_not_found":
                    return PublicationAPIError.submissionNotFound
                case "unsupported_media_type":
                    return PublicationAPIError.unsupportedMediaType
                case "image_too_large":
                    return PublicationAPIError.imageTooLarge
                case "object_missing":
                    return PublicationAPIError.objectMissing
                case "invalid_image":
                    return PublicationAPIError.invalidImage
                case "idempotency_key_conflict":
                    return PublicationAPIError.idempotencyKeyConflict
                default:
                    return PublicationAPIError.underlying(envelope.error.message)
                }
            }
        }
    }
    return PublicationAPIError.underlying(error.localizedDescription)
}

private struct PublicationAPIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}

final class RecordingUploadRepository: UploadServing, @unchecked Sendable {
    private(set) var createCallCount = 0
    private(set) var completeCallCount = 0
    var createError: Error?
    var completeError: Error?
    var nextSlot: UploadSlotModel?
    var nextReady: UploadSlotModel?

    func createUpload(
        accessToken: String,
        contentType: String,
        byteSize: Int,
        purpose: AppUploadPurpose,
        idempotencyKey: String?
    ) async throws -> UploadSlotModel {
        createCallCount += 1
        _ = purpose
        if let createError { throw createError }
        if let nextSlot { return nextSlot }
        return UploadSlotModel(
            id: UUID(),
            status: "pending",
            contentType: contentType,
            signedUploadURL: URL(string: "https://example.test/upload"),
            signedUploadMethod: "PUT",
            signedUploadHeaders: ["Content-Type": contentType],
            maxBytes: max(byteSize, 1)
        )
    }

    func completeUpload(accessToken: String, uploadId: UUID) async throws -> UploadSlotModel {
        completeCallCount += 1
        if let completeError { throw completeError }
        if let nextReady { return nextReady }
        return UploadSlotModel(
            id: uploadId,
            status: "ready",
            contentType: "image/jpeg",
            signedUploadURL: nil,
            signedUploadMethod: nil,
            signedUploadHeaders: [:],
            maxBytes: nil
        )
    }
}

final class RecordingSubmissionRepository: SubmissionServing, @unchecked Sendable {
    private(set) var createCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastDeletedSubmissionId: UUID?
    private(set) var lastIdempotencyKey: String?
    var createError: Error?
    var deleteError: Error?
    var nextSubmission: SubmissionModel?

    func createSubmission(
        accessToken: String,
        sketchSessionId: UUID,
        uploadId: UUID,
        caption: String?,
        idempotencyKey: String?
    ) async throws -> SubmissionModel {
        createCallCount += 1
        lastIdempotencyKey = idempotencyKey
        if let createError { throw createError }
        if let nextSubmission { return nextSubmission }
        return SubmissionModel(
            id: UUID(),
            caption: caption,
            status: "published",
            timerMode: "countdown",
            timerSeconds: 300,
            likeCount: 0,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: true,
            imageURL: URL(string: "https://example.test/display")!,
            thumbnailURL: URL(string: "https://example.test/thumb")!,
            userId: UUID(),
            username: "sketchy",
            displayName: "Sketcher",
            promptWords: ["A", "B", "C"],
            promptDate: Date(),
            sketchSessionId: sketchSessionId,
            publishedAt: Date()
        )
    }

    func getSubmission(accessToken: String?, submissionId: UUID) async throws -> SubmissionModel {
        if let nextSubmission { return nextSubmission }
        throw PublicationAPIError.submissionNotFound
    }

    func deleteSubmission(accessToken: String, submissionId: UUID) async throws {
        deleteCallCount += 1
        lastDeletedSubmissionId = submissionId
        if let deleteError { throw deleteError }
    }
}

final class RecordingDirectUploader: DirectUploadTransporting, @unchecked Sendable {
    private(set) var uploadCallCount = 0
    var uploadError: Error?

    func upload(
        data: Data,
        to url: URL,
        method: String,
        headers: [String: String],
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        uploadCallCount += 1
        progress?(0.5)
        if let uploadError { throw uploadError }
        progress?(1)
    }
}
